# Codebase Audit — 2026-06-22

> **Status:** ACTIVE. Read-only deep-dive audit of the `macparakeet` codebase at
> `main` HEAD `390e5ee` (post-v0.6.24). Covers the surface landed since the
> 2026-06-09 audit (AUDIT-071..082): direct SRT/VTT CLI output, Library/Meetings
> bulk-delete fixes, stranded meeting `filePath` healing, RefinementValidator
> plan, Spoken Transforms plan. Numbering continues at **AUDIT-083+**. Findings
> retained with file:line evidence per house style.
>
> **Environment caveat:** this pass ran on a Linux container with **no Swift
> toolchain**, so it is a static read-only review — `swift build`/`swift test`
> were **not** run. All findings are source-derived and line-cited; none are
> backed by a fresh green baseline. Re-run `swift test` on macOS before acting.

| | Count |
|---|---:|
| Workstreams (parallel read-only agents) | 5 |
| Confirmed findings | 33 |
| P0 (data loss / crash / security-critical) | 0 |
| P1 (correctness / reliability / security) | 13 |
| P2 (polish / hygiene / latent) | 20 |
| Independently spot-verified by lead | C1, D1, D4, CLI-confirm precedent |

Severity legend: **P0** = data loss/crash/security · **P1** =
correctness/reliability · **P2** = polish/hygiene/latent. All statuses OPEN.

---

## Methodology

Five parallel read-only agents, each scoped and instructed to report only
defensible findings with `file:line`, severity, concrete risk, and fix:

| Workstream | Scope |
|---|---|
| Concurrency & Swift 6 | Audio, STT, Services, coordinators — continuations, actor isolation, `@unchecked Sendable`, Task lifetime, MainActor blocking |
| Privacy & network egress | Every outbound call, telemetry payload contents, LLM data flow vs local-first promise |
| Persistence & file lifecycle | GRDB migrations, UUID-SQL pitfall, delete/heal flows, meeting-artifact safety |
| Core capture flows | Dictation/meeting/transcription state machines, audio buffers, crash/leak sites |
| CLI + secrets + process exec | CLI contract, Keychain handling, shell/Process safety |

The lead independently re-read and confirmed the two headline findings (C1, D1),
the word-timing boundary bug (D4), and the CLI-confirmation precedent before
publishing.

**Codebase health signals (static):** zero `TODO`/`FIXME`/`HACK` markers, zero
`fatalError`, zero `as!`, one `try!` (a constant regex pattern — safe), no stray
`print()`. 233 test files against 412 sources. The defensive discipline noted in
prior audits holds; most grep hits for risky patterns are correctly guarded.

---

## Confirmed findings — P1

### AUDIT-083 — Continuation leak / shutdown hang in meeting-flow settlement wait
**`Sources/MacParakeet/App/MeetingRecordingFlowCoordinator.swift:349-355`**
(waiters parked at `:91`, resumed only via `sendEvent` → `:363-370`; callers
`:264`, `:272`). *Lead-verified.*
`waitForActiveFlowToSettle()` uses `withCheckedContinuation` (no
`withTaskCancellationHandler`) and parks the continuation in
`activeFlowSettlementWaiters`, depending on a future `sendEvent(...)` to resume
it. If the awaiting task (`stopRecordingAndWaitForCompletion` /
`discardRecordingAndWaitForCompletion`) is cancelled, or the flow settles via any
path that bypasses `sendEvent`, the continuation is never resumed: the caller
hangs and the runtime logs a leaked `CheckedContinuation`. These are
await-on-quit paths, so a stuck shutdown is plausible.
**Fix:** wrap in `withTaskCancellationHandler`; on cancel remove+resume the
pending continuation; re-check `isMeetingRecordingActive` before suspending.

### AUDIT-084 — Dictation-preview drain timeout orphans runtime task, wedges interactive lane
**`Sources/MacParakeetCore/STT/STTScheduler.swift:718-731`** (`waitForDictationPreviewDrain`)
The drain races `task.result` against `Task.sleep(timeout)`. On timeout it
resumes the gate and returns but never cancels the runtime task nor clears
`dictationPreviewExecution`. Because `beginLiveDictation` /
`transcribeDictationPreview` / engine-switch all guard on
`dictationPreviewExecution == nil`, a slow/stuck preview silently rejects new
dictation (`unavailable`/`engineBusy`) until the orphaned call finishes. The
losing `Task.sleep` also leaks for the full timeout on the fast path.
**Fix:** cancel the losing child in both branches; on timeout cancel
`execution.task` / mark the entry for reaping.

### AUDIT-085 — `.success`→`.idle` 500 ms timer races the flow consumer (dictation state lost)
**`Sources/MacParakeetCore/Services/Dictation/DictationService.swift:472-477`**
(same pattern in `undoCancel()` ~`:676`). *Lead-verified.*
After a successful stop, the service sleeps a fixed 500 ms then sets
`_state = .idle`. The flow coordinator polls `serviceSession.state`; if the
consumer is delayed past 500 ms (it runs its own sleeps + LLM formatting) it
observes `.idle` for a session that actually succeeded, erasing the observable
success state. The function returns `result` to its direct caller, so impact is
on the observable-state contract used by the poller.
**Fix:** don't auto-reset from `.success` on a timer; let the consumer (or the
next `startRecording`) drive the `.success`→`.idle` transition.

### AUDIT-086 — Telemetry is opt-out (default ON) with no first-run disclosure
**`Sources/MacParakeetCore/Services/Telemetry/TelemetryService.swift:102`,
`Sources/MacParakeetCore/AppPreferences.swift:17`, `OnboardingViewModel`**
`telemetryEnabled` defaults to `true`; onboarding fires `appLaunched` /
`onboardingStep` / `onboardingCompleted` before the user ever sees the Settings →
Privacy toggle. The payload itself is genuinely non-identifying (per-launch
session UUID, allowlisted low-cardinality metadata, multi-layer scrubbing of
paths/URLs/content — no transcript/audio/PII), and it is disclosed in
`docs/telemetry.md`. But "analytics on by default with no onboarding consent" is
the single largest deviation from a strict privacy-first posture and the most
likely to draw user/reviewer criticism.
**Fix:** add a one-line consent/disclosure in onboarding, or suppress
non-essential telemetry until the privacy screen has been shown.

### AUDIT-087 — Destructive CLI commands delete user data with no confirmation or `--force`
**`Sources/CLI/Commands/HistoryCommand.swift:251` (`delete-dictation`, also
deletes audio), `:301` (`delete-transcription`), `:328` (`delete-meeting-audio`),
`:366` (`clear-meeting-audio`, deletes ALL meeting audio).** *Lead-verified
precedent.*
These execute immediately with no interactive confirm and no `--force`/`--yes`
gate. A fat-fingered `clear-meeting-audio` or a wrong UUID prefix is
irreversible. This contradicts the project's "treat user data as user data; do
not delete outside explicit flows" rule, and it is the highest-impact issue on
the agent-facing CLI surface. The codebase **already has the pattern**:
`QuickPromptsCommand.swift:659-709` uses a `--yes` flag + interactive "Type
'yes'" prompt, auto-implied by `--json`.
**Fix:** add the same `--yes`/`--force` gate (interactive prompt when TTY) to the
destructive `history` subcommands; note in `Sources/CLI/CHANGELOG.md`.

### AUDIT-088 — Gemini API key can leak via unscrubbed `connectionFailed` errors
**`Sources/MacParakeetCore/Services/LLM/LLMClient.swift:708-724`** (model-list URL
builds `key=<apiKey>` in the query string) → catch blocks throw
`LLMError.connectionFailed(error.localizedDescription)` at `:88`, `:151`, `:235`,
`:286`.
`connectionFailed` is **not** routed through `scrubAPIKeyArtifacts` (only
`mapError`/`mapStreamingError` scrub). `URLError.localizedDescription` /
`failingURL` can include the full request URL, and that message flows to CLI
stderr and the `--json` envelope. Exposure is limited to the model-listing path
(Gemini chat uses the `Authorization: Bearer` header, `:607-608`), but a Gemini
key can still be printed to a terminal/log/CI on a DNS or TLS error.
**Fix:** scrub `connectionFailed` messages too, and/or prefer the
`x-goog-api-key` header over the `key=` query param for Gemini listing.

### AUDIT-089 — `isKnownMeetingFolder` manifest probe can authorize deletion outside an app-owned root
**`Sources/MacParakeetCore/Utilities/TranscriptionAssetCleanup.swift:290-310`**
The guard returns `true` for *any* folder — even outside Application Support — if
it contains a `metadata.json` or schema-matching `manifest`. Callers feed only
DB-derived paths today, so it is bounded in practice, but if a row's
`filePath`/`meetingArtifactFolderPath` were ever corrupted to point at a user
folder that happens to carry a MacParakeet manifest (e.g. a session copied into
Documents), deletion would proceed.
**Fix:** require the prefix-root check to pass AND treat manifest/metadata only
as a secondary signal *within* a known root.

### AUDIT-090 — Custom recording-folder history isn't in `knownRoots` (durable cleanup gap)
**`Sources/MacParakeetCore/Utilities/TranscriptionAssetCleanup.swift` +
`AppPaths.swift:55-80`**
`meetingRecordingsDir` is user-configurable. After a user changes their
recordings folder, transcriptions under the *previous* custom folder fall outside
both `knownRoots` entries and can only be cleaned via the manifest fallback
(AUDIT-089). If the manifest is absent (older/audio-only sessions),
`removeOwnedMeetingAudio` silently refuses and the user can't delete that audio
from within the app. Not data loss, but a durable-cleanup gap.
**Fix:** persist and consult previously-configured recording roots, or trust the
stored `meetingArtifactFolderPath` parent as a root.

### AUDIT-091 — `cancelledJobIDs` grows unbounded from post-completion cancel handlers
**`Sources/MacParakeetCore/STT/STTScheduler.swift:~628-647`** (`cancel(jobID:)`)
`cancel` unconditionally inserts into `cancelledJobIDs` even when the job isn't
in-flight. Cancellation handlers fire via detached tasks that can run after the
job already completed and was removed, re-inserting a stale ID that is never
consumed — unbounded set growth over process lifetime, plus a busy-guard that can
be misled.
**Fix:** only insert if the ID is actually pending/running.

### AUDIT-092 — Meeting auto-start/auto-prompt re-emits every tick with no policy-level latch
**`Sources/MacParakeetCore/MeetingDetection/MeetingActivityDetector.swift:67-74`**
`autoStart`/`prompt` modes re-emit `.autoStartDue`/`.promptToRecord` on every
tick; the pure policy has no per-identity latch, so correctness depends entirely
on the coordinator synchronously suppressing the identity. Latent repeated-prompt
/ double-start risk if the coordinator dedupe ever changes.
**Fix:** latch per identity in the policy, or document the contract loudly.

### AUDIT-093 — Interior `▁` in a token produces a word with an embedded space and merged timing
**`Sources/MacParakeetCore/STT/STTWordTimingBuilder.swift:36-54`** *Lead-verified.*
Only `normalizedToken.first?.isWhitespace` is checked, so a token like
`"foo▁bar"` (→ `"foo bar"`) takes the append branch and yields a single
`TimestampedWord` containing a space with merged start/end. Corrupts
word-timing exports, diarization word-merge, and karaoke highlighting. Low
likelihood (sentencepiece `▁` is conventionally a prefix) but a real boundary
bug.
**Fix:** split `trimmedToken` on internal whitespace and flush per segment.

### AUDIT-094 — Timing-less engines yield `nil` duration; zero-sample audio reported as success
**`Sources/MacParakeetCore/Services/TranscriptionService.swift:1432` +
`Sources/MacParakeetCore/STT/NemotronEnglishEngine.swift:77-84`**
`durationMs` is derived only from `words.map(\.endMs).max()`, so engines that
return no word timings (Parakeet Unified, Nemotron offline) leave
`durationMs == nil` for file/URL transcriptions (the meeting path has a
`recording.durationSeconds` floor; the file path doesn't). Separately, the
Nemotron file path reports zero-sample/empty audio as a *successful empty
transcription* (the preview path has the `!samples.isEmpty` guard; the file path
doesn't).
**Fix:** floor `durationMs` with decoded sample-count/sample-rate; add the
empty-audio guard to the file path and throw `invalidAudioData`.

### AUDIT-095 — Meeting cancel/stop ignore `startingSessionID` (teardown can interleave with in-flight start)
**`Sources/MacParakeetCore/Services/MeetingRecording/MeetingRecordingService.swift`**
(`cancelRecording`/`stopRecording`)
A cancel landing after `currentSession` is set but before capture fully starts
can interleave teardown with the in-flight start's own `cleanupFailedStart`
(double `removeItem`/lock delete). Mostly idempotent today but fragile.
**Fix:** have cancel/stop coordinate when `startingSessionID != nil &&
currentSession == nil`.

---

## Confirmed findings — P2

### AUDIT-096 — `resumeForTermination()` blocks the MainActor on a semaphore (≤2.8 s)
**`Sources/MacParakeet/App/DictationMediaPauseCoordinator.swift:117-129`**
(analogous ~0.35 s at `AppDelegate.swift:387-392`). Safe only because reached
from `applicationWillTerminate`; would deadlock if invoked elsewhere or if the
detached work hopped back to main. **Fix:** keep termination-only (assert/guard),
or use the existing `.terminateLater` async handshake.

### AUDIT-097 — `MeetingRecordingFlowCoordinator` owns ~10 unstructured tasks with no `deinit`
**`Sources/MacParakeet/App/MeetingRecordingFlowCoordinator.swift`** (tasks at
`:382/532/608/683/749/769/794/889/989/1029/1055`). Unlike sibling coordinators
that cancel in `deinit`, this one has none; `transcriptObservationTask` /
`speechWarmUpObservationTask` block on `for await` and won't wake until the next
element. Latent (coordinator is app-lifetime). **Fix:** add a teardown entry
point cancelling all stored tasks, or document app-lifetime as an invariant.

### AUDIT-098 — `Timer.invalidate()` from a `nonisolated deinit` is off-main
**`Sources/MacParakeet/App/MeetingAutoStopCoordinator.swift:93`** (timer at `:37`).
`Timer.invalidate()` is only reliable on the scheduling run loop (main). Bounded
because `stop()` already invalidates on main and the block weak-captures self.
**Fix:** rely on `stop()`; in `deinit` hop to main or drop the line.

### AUDIT-099 — Orphaned heartbeat timer on stop/delivery race
**`Sources/MacParakeetCore/Audio/SystemAudioStream.swift:308-313`** vs
`:350-361`. `recordBufferDelivery()` starts the heartbeat outside the
`watchdogLock`, so a concurrent `stop()`→`resetDiagnosticsState()` can leave a
fresh repeating `DispatchSourceTimer` after stop nilled it. Resource leak only
(no data race; `checkHeartbeat` re-guards). **Fix:** start/gate the heartbeat
inside the locked section.

### AUDIT-100 — Inconsistent warm-up error mapping for concurrent `prepare()` joiners
**`Sources/MacParakeetCore/STT/NemotronEngine.swift:171-174` +
`NemotronEnglishEngine.swift`** (vs `ParakeetUnifiedEngine.swift:187-193`). A
second concurrent caller joining the in-flight `initializationTask` gets the raw
FluidAudio/`CancellationError` while the creator gets a mapped `STTError`.
Behavioral inconsistency only. **Fix:** route the joiner through
`mapWarmUpError` too.

### AUDIT-101 — `aiFormatterEnabledForTranscriptions` defaults `true`
**`Sources/MacParakeetCore/AppRuntimePreferences.swift:571`** (global
`aiFormatterEnabled` defaults `false` at `:553`). Cannot cause egress on its own
(no LLM provider configured by default), but it pre-enables cloud transcription
formatting the moment a user later adds a cloud provider. **Fix:** confirm the
intended UX; consider defaulting off or surfacing a confirm.

### AUDIT-102 — `try? printJSON(envelope)` can silently drop the `--json` failure envelope
**`Sources/CLI/Commands/CLIHelpers.swift:487`**. If encoding/printing the error
envelope fails the command still exits non-zero but emits no JSON, breaking the
"failure always prints a JSON object" contract (exit code stays correct, so
impact is low). **Fix:** fall back to a hand-written minimal JSON line.

### AUDIT-103 — PATH-resolved `node`/`deno`/`qjs` and fallback `ffmpeg` run unverified
**`Sources/MacParakeetCore/Services/YouTubeAudioPlaybackConverter`/`YouTubeDownloader.swift:643-689`,
`BinaryBootstrap.swift:302-312`**. `extendedPATH` appends `/usr/local/bin`
(world-known, sometimes group-writable); a planted `node`/`ffmpeg` there could
execute. Mitigated by preferring bundled/Homebrew paths first, and yt-dlp itself
is SHA-256 verified. Defense-in-depth note. **Fix:** prefer bundled JS runtime /
ffmpeg; pin discovery to trusted dirs.

### AUDIT-104 — Local-CLI LLM calls run `/bin/zsh -lc` (sources login profile each call)
**`Sources/MacParakeetCore/Services/LLM/LocalCLIExecutor.swift:547`** (PATH probe
`-i -l -c` at `:946-963`). Each transform sources `.zshrc`/`.zprofile` — small
dotfile attack surface + per-call cost. Prompt/transcript is correctly fed via
**stdin** (not the shell string), so no injection. **Fix:** cache and avoid `-l`
on the hot path where feasible.

### AUDIT-105 — `computeDurationMs` splits on ASCII space only
**`Sources/MacParakeetCore/Services/Dictation/DictationService.swift:1287`**.
Uses `text.split(separator: " ")` while the rest of the file uses
`split(whereSeparator: \.isWhitespace)`; newline/tab transcripts collapse to one
"word" and under-report duration (telemetry only). **Fix:** use the whitespace
splitter; keep the 150 ms floor.

### AUDIT-106 — `LiveTranscriptStabilizer` can shrink the displayed readout
**`Sources/MacParakeetCore/.../LiveTranscriptStabilizer.swift:60-79`**. A shorter
cumulative update can replace `hypothesisWords` with a shorter tail, so
`committed+hypothesis` jumps backward, contradicting the append-only contract.
Display-only. **Fix:** never shrink committed prefix; only extend hypothesis.

### AUDIT-107 — Live meeting timestamps move backward on min-`startMs` recompute
**`Sources/MacParakeetCore/.../MeetingTranscriptAssembler.swift:204-219`**
(`normalizedWords`). Per-update re-normalization against a recomputed global min
`startMs` makes already-displayed live timestamps shift backward (worse across
pause/resume). Live-preview only. **Fix:** fix the origin at the first word.

### AUDIT-108 — `repairIfNeeded` leaves `-repaired.m4a` on disk when `replaceItemAt` throws
**`Sources/MacParakeetCore/Services/MeetingRecording/MeetingRecordingRecoveryService.swift:383-417`**.
Accumulates across failed recoveries. **Fix:** `try?` remove the temp export in
the catch.

### AUDIT-109 — `FnKeyStateMachine` timestamp subtraction can underflow
**`Sources/MacParakeet/Hotkey/FnKeyStateMachine.swift:63/105`**. `UInt64`
subtraction across two clocks (`event.timestamp` vs synthesized
`DispatchTime.now()` on recovery) can underflow and misclassify tap vs hold.
**Fix:** saturating subtraction + single clock source.

### AUDIT-110 — Dictation double-start during `.processing` yields a spurious failure message
**`Sources/MacParakeetCore/Services/Dictation/DictationService.swift:289`**.
Returns silently, leading the flow to emit "Recording could not start." **Fix:**
distinguish "busy, ignore" from "failed."

### AUDIT-111 — Aliased reusable silent mic buffer passed into async `append`
**`Sources/MacParakeetCore/Services/MeetingRecording/MeetingRecordingService.swift:1491`**
(`silentMicrophoneBufferLike`, used ~`:859-878`). A single
`reusableMicrophoneSilentBuffer` is zeroed, handed to
`AVAssetWriterInput.append`/`writer.write` (which may read asynchronously), then
re-zeroed and re-appended. Masked because content is always silence; would
corrupt audio if that buffer ever carried real samples. **Fix:** allocate
per-call or copy before append.

### AUDIT-112 — `recover()` proceeds when `mixToM4A` fails, silently degrading playback
**`Sources/MacParakeetCore/Services/MeetingRecording/MeetingRecordingRecoveryService.swift:178-186`**.
The user keeps the transcript (correct trade) but `filePath`/playback may point
at a missing/partial `meeting.m4a`; self-heals on next sweep. **Fix:** surface a
degraded-state flag.

### AUDIT-113 — Empty-audio / metadata-save throw paths can orphan a session folder
**`Sources/MacParakeetCore/Services/MeetingRecording/MeetingRecordingService.swift:522-557/563-576`**.
The empty path `try?`-swallows a `removeItem` failure that then has no lock for
recovery. Minor leak. **Fix:** ensure lock-or-cleanup on these throw paths.

### AUDIT-114 — `activeTranscriptionCount` possible double-decrement (low confidence)
**`Sources/MacParakeetCore/STT/STTRuntime.swift:254-301`**. Finish-vs-shutdown/
cancel interleavings could double-decrement, permanently weakening the
engine-busy guard. **Fix:** add a targeted test; make the decrement idempotent
per job.

### AUDIT-115 — File-then-row delete ordering leaves recoverable orphan rows
**Multiple delete call sites.** Pattern is files-first then DB row; a failed row
delete leaves a row pointing at missing audio (benign, healed by
`clearMissingAudioPaths`). Documented for completeness. **Fix (optional):**
reconcile pass, or wrap so a failed row delete rolls back.

---

## Examined and refuted / verified-safe (highlights)

- **No raw UUID-string SQL bug.** The only `.uuidString` in SQL
  (`TransformHistoryRepository.delete:115`) is a deliberate legacy fallback after
  the correct GRDB `deleteOne(db, key:)`; all live paths use key-based CRUD.
- **Migrations are additive and re-run-safe**; column adds pre-check
  `db.columns(in:)`, creates use `ifNotExists`. The one destructive migration
  (v0.21 hidden-dictation content wipe) is an intentional privacy backfill
  matching the runtime invariant.
- **Single `DatabaseQueue`** (serialized writes) + cross-process `busyMode`/flock;
  no multi-writer hazard.
- **Concurrency primitives are sound:** `OneShotContinuation`, `AsyncPermit`,
  `LocalCLIExecutor.claimContinuation`, `CrashReporter` signal-handler statics —
  all single-resume / lock-guarded / async-signal-safe.
- **Audio teardown is clean:** taps/observers/timers removed on every failure and
  in `deinit`; generation guards prevent post-finish delivery.
- **Secrets handled correctly:** API keys in Keychain
  (`AfterFirstUnlockThisDeviceOnly`, non-synchronizable), excluded from `Codable`
  config blobs, never in feedback bundles; LLM run logging uses `privacy:
  .private`.
- **yt-dlp is SHA-256 verified** against the published `SHA2-256SUMS` before
  install with an atomic staged swap; all invocations terminate options with `--`
  and pass the URL as a discrete argument (no shell).
- **Local-first promise holds:** no path sends transcript/audio to the network
  without the user explicitly configuring a cloud LLM provider; there is no
  default cloud provider and no bundled key.

---

## Recommended order of work

1. **AUDIT-085** (dictation `.success` lost) and **AUDIT-083** (shutdown hang) —
   user-visible reliability, both lead-verified.
2. **AUDIT-087** (CLI destructive-delete confirm) and **AUDIT-088** (Gemini key
   scrub) — data-safety + secret-hygiene on the agent-facing surface; the
   confirmation pattern already exists to copy.
3. **AUDIT-086** (telemetry first-run consent) — privacy posture; cheap and
   high-trust-value.
4. **AUDIT-084 / 091 / 094 / 089** — lane wedge, unbounded set, duration/empty
   audio, deletion-authority scoping.
5. P2 batch as hygiene PRs, with regression tests for the two historically
   destructive migrations and for `activeTranscriptionCount` (AUDIT-114).

> **Before landing any fix:** run `swift test` on macOS (not possible in this
> audit's Linux environment) to establish the green baseline this pass lacked.
