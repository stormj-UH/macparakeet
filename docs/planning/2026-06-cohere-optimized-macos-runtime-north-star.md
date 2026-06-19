# Cohere Transcribe Optimized macOS Runtime North Star

Last updated: 2026-06-19

Status: North Star challenge for a future coding agent. This is not a committed
product roadmap until a benchmark spike proves the model/runtime tradeoff.

Related research:

- `docs/research/cohere-transcribe-stt-2026-06.md`
- `docs/planning/2026-06-nemotron-stt-benchmark-report.md`
- `spec/06-stt-engine.md`
- `spec/adr/002-local-only.md`
- `spec/adr/021-whisperkit-multilingual-stt.md`

## Challenge Statement

Build the best local Apple Silicon runtime path for Cohere Transcribe that could
eventually make MacParakeet the strongest private, local-first final transcript
app on macOS.

The target is not "make Cohere run." The target is a Mac-native, benchmarked,
memory-aware, user-trust-preserving runtime that makes Cohere useful inside a
shipping desktop app:

```text
Cohere Transcribe weights
  -> optimized local Apple Silicon runtime
    -> MacParakeet CohereEngine
      -> final transcript workflows with explicit product tradeoffs
```

The worthy version of this project is a "FluidAudio-grade path for Cohere":
native, fast enough, stable under real app workloads, explicit about language
selection, honest about missing timestamps, and measured against Parakeet,
Nemotron, and Whisper on MacParakeet audio.

## Why This Is Worth Exploring

Cohere Transcribe is locally available, open-weight, and benchmarked as a strong
final transcript model. Its public model card reports strong WER and throughput
numbers on the Hugging Face Open ASR leaderboard, and the model supports
English, German, French, Italian, Spanish, Portuguese, Greek, Dutch, Polish,
Vietnamese, Chinese, Arabic, Japanese, and Korean.

The product gap is clear:

- MacParakeet's default Parakeet path is extremely fast, small, local, and
  timestamped.
- Nemotron gives a local streaming beta path.
- Whisper gives broad mature language fallback.
- Cohere may offer a distinct "best final text" lane for users who care most
  about final transcript quality and can tolerate manual language selection.

If Cohere's quality advantage survives real MacParakeet benchmarks, an optimized
runtime could be worth real engineering effort. If it does not, the project
should stop at the research/benchmark result.

## Non-Negotiables

1. **Local-first STT remains the contract.** Core dictation, transcription, and
   meeting recording must not send audio to Cohere's hosted API.
2. **Parakeet remains default until proven otherwise.** Cohere starts as an
   optional final transcript candidate, not a default engine replacement.
3. **Benchmark first.** No Settings UI, onboarding, marketing copy, or product
   claim before same-corpus benchmark data exists.
4. **Manual language is product truth.** Cohere requires an explicit language;
   do not paper over this with fake auto-detect unless a separate local language
   detector is intentionally added and measured.
5. **No timestamp claims.** Cohere currently has no ASR timestamp support in the
   paths researched. Export and meeting workflows must degrade honestly.
6. **No moving branch dependency in shipping code.** If using `mlx-audio-swift`,
   pin a commit or wait for a release tag containing Cohere support.
7. **Converted weight distribution needs explicit due diligence.** Do not assume
   that a community MLX conversion can be silently redistributed or auto-
   downloaded by MacParakeet without checking the upstream terms and conversion
   repo metadata.
8. **Agent work must preserve dirty worktrees.** Use isolated worktrees or stage
   only owned files.

## North Star Outcome

The long-term outcome is a first-class local Cohere runtime with this shape:

```swift
public actor CohereTranscribeEngine {
    public func prepare(modelURL: URL, onProgress: (@Sendable (String) -> Void)?) async throws
    public func transcribe(
        audioURL: URL,
        language: CohereTranscribeLanguage,
        job: STTJobKind,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> STTResult
    public func unload() async
    public func isReady() async -> Bool
}
```

This engine should:

- run locally on Apple Silicon;
- have no Python subprocess in the shipping app path;
- load explicit model artifacts from a controlled cache;
- normalize audio to mono 16 kHz;
- choose deterministic decoding by default;
- support cancellation boundaries;
- expose coarse progress for long files;
- serialize inference initially until profiling justifies concurrency;
- unload under memory pressure;
- return `STTResult` with `words: []` unless real timestamp support is added;
- report `engine: .cohere` and a precise engine variant.

## Runtime Strategy

### Starting Point

Start with MLXAudio Swift, not a from-scratch runtime.

Reasoning:

- It is native Swift.
- It uses MLX on Apple Silicon.
- It already has a Cohere Transcribe wrapper on `main`.
- It documents `CohereTranscribeModel.fromPretrained(...)`.
- It documents mono 16 kHz input and token streaming over an audio buffer.

Use it to get a baseline and to learn where time and memory go.

### Worthy End State

The optimized end state may still use MLXAudio Swift, or it may become a
MacParakeet-owned wrapper/fork if measurement shows generic abstractions are
holding back the app. The runtime should be specialized around:

- Cohere's Conformer encoder;
- Cohere's lightweight decoder;
- long-form transcript chunking;
- MacParakeet's file, dictation, and meeting jobs;
- Apple Silicon unified memory behavior;
- deterministic app integration rather than research flexibility.

### Runtime Layers

The future runtime should have clear layers:

1. **Artifact manager**
   - model variant manifest;
   - cache path;
   - download/install/delete/status;
   - checksum or file inventory validation;
   - license/terms metadata.

2. **Audio input layer**
   - file decode;
   - mono conversion;
   - 16 kHz resampling;
   - silence/noise trim;
   - optional VAD segmentation.

3. **Feature layer**
   - mel feature computation;
   - shape normalization;
   - batching/chunk input layout where useful.

4. **Inference layer**
   - encoder execution;
   - decoder generation;
   - KV/cache handling;
   - deterministic decoding defaults;
   - cancellation and memory cleanup points.

5. **Long-form layer**
   - chunk boundaries;
   - overlap policy;
   - duplicate suppression;
   - paragraph stitching;
   - failure recovery per chunk.

6. **MacParakeet adapter**
   - `STTTranscribing`;
   - `SpeechEngineRoutedTranscribing`;
   - `STTRuntime` dispatch;
   - `STTScheduler` slot policy;
   - CLI engine selection;
   - Settings model state later.

7. **Benchmark/profiling layer**
   - corpus runner;
   - WER/CER scoring;
   - `/usr/bin/time -lp`;
   - os_signpost or logging spans;
   - per-stage timings;
   - memory-pressure probes.

## Workstreams

### 1. Baseline Reproduction

Goal: prove the model runs locally and produce a reproducible baseline.

Tasks:

- Create a temporary external harness using `transformers` or MLX Python.
- Create a Swift harness using MLXAudio Swift at a pinned commit.
- Run both on the same audio.
- Save transcripts and timing/memory metrics.
- Verify that explicit language selection is wired correctly.

Outputs:

- baseline command log;
- model artifact inventory;
- WER/CER table;
- latency/memory table;
- first failure list.

### 2. Corpus Design

Goal: avoid optimizing for toy audio.

Minimum corpus:

- short English dictation;
- long English dictation;
- meeting audio with names, owners, and product terms;
- quiet microphone input;
- noisy microphone input;
- silence/non-speech input;
- code-switched or mixed-language sample;
- at least two non-English supported languages;
- 10-30 minute meeting/file sample;
- repeated sample for warm/cold comparisons.

Each sample needs:

- source file;
- duration;
- expected language;
- ground-truth reference transcript where possible;
- notes about source conditions;
- permission to keep or regenerate it in repo/local artifacts.

### 3. Weight Conversion And Artifact Strategy

Goal: know exactly which weights are being evaluated and whether they are
ship-ready.

Questions:

- Are we using upstream `CohereLabs/cohere-transcribe-03-2026` directly?
- Are we using `beshkenadze/cohere-transcribe-03-2026-mlx-fp16`?
- Are we evaluating `appautomaton/cohere-asr-mlx` int8?
- Do we need a MacParakeet-owned conversion?
- Can a GPL app direct-download these artifacts?
- Should user acceptance/HF token handling be required?

Required evidence:

- model repo URL;
- commit/revision;
- file list;
- total disk size;
- license metadata;
- conversion script or provenance;
- checksum manifest.

### 4. MLX Runtime Performance

Goal: identify whether the bottleneck is audio preprocessing, encoder compute,
decoder generation, chunking, or memory churn.

Measure:

- cold load time;
- warm prepare time;
- feature extraction time;
- encoder time;
- decoder time;
- total wall time;
- realtime factor;
- peak resident memory;
- MLX peak memory if available;
- memory released after unload;
- repeated-run stability.

Optimization candidates:

- reduce redundant audio copies;
- keep arrays in MLX unified memory;
- batch `eval()` calls intentionally;
- compile pure MLX array functions where useful;
- avoid unnecessary transposes;
- reuse mel filter banks and tokenizer state;
- reduce per-chunk allocation churn;
- clear MLX caches only at deliberate points;
- test fp16 versus int8 quality and memory.

### 5. Audio Preprocessing

Goal: make the non-model path fast and safe.

Tasks:

- Compare MacParakeet's existing audio conversion path with MLXAudio's loader.
- Measure resampling time separately from inference.
- Confirm mono downmix behavior.
- Add VAD/noise gating for silence hallucination tests.
- Ensure long meeting source files do not create unbounded memory spikes.

Success:

- preprocessing timings are visible in benchmark output;
- silence/non-speech samples do not produce confident garbage transcripts;
- preprocessing failures are surfaced as normal MacParakeet errors.

### 6. Long-Form Chunking And Stitching

Goal: make Cohere usable for meetings and long files despite no timestamps.

Problems:

- no native word timestamps;
- no diarization;
- chunk boundaries can cut words/sentences;
- overlap can duplicate text;
- language is fixed per run;
- long chunks can spike memory.

Potential approach:

- VAD-guided chunks when speech boundaries are reliable;
- fixed maximum chunk length fallback;
- small overlap only if needed;
- text-level duplicate suppression;
- paragraph stitching by punctuation and whitespace;
- per-chunk retry and failure isolation;
- explicit note that timings are chunk-level approximations only.

### 7. Quantization

Goal: reduce footprint without losing the quality that makes Cohere worth using.

Evaluate:

- fp16 baseline;
- int8 conversion;
- possible mixed precision;
- per-language WER deltas;
- punctuation and named-entity deltas;
- speed delta;
- memory delta;
- load-time delta.

Rule:

Do not ship quantization solely because it is smaller. Ship it only if quality
loss is acceptable on the MacParakeet corpus.

### 8. MacParakeet CLI Spike

Goal: prove integration through the real app control plane without GUI
commitment.

Tasks:

- Add `.cohere` to `SpeechEnginePreference` in an experiment branch.
- Add Cohere language enum/catalog for the 14 supported languages.
- Add `CohereEngine` behind the existing STT protocols.
- Add CLI support:

```bash
macparakeet-cli transcribe sample.wav --engine cohere --language en --format json
```

- Return empty `words` until real timestamp support exists.
- Keep Parakeet default.
- Do not add Settings UI yet.

Success:

- a single CLI command runs Cohere locally;
- the result records engine/language/variant correctly;
- cancellation and missing model errors behave predictably;
- benchmarks can run through the same CLI harness as other engines.

### 9. Product Integration

Only after the CLI spike and benchmark gates pass:

- add Settings engine tile;
- add required language picker with no auto option;
- add model download/status/delete row;
- add clear copy for "final text quality, no timestamps";
- update CLI docs;
- update `spec/06-stt-engine.md`;
- update telemetry allowlists if engine enum appears there;
- add export behavior tests for empty word timestamps.

## Benchmark Gates

### Gate 0 - Runs Locally

Pass if:

- local Cohere runs on an Apple Silicon Mac;
- exact model artifact is recorded;
- language selection works;
- no cloud API is used;
- output text matches basic sanity expectations.

Fail if:

- local inference requires a server/cloud path;
- artifact provenance is unclear;
- runtime cannot be pinned.

### Gate 1 - Quality Signal

Pass if:

- Cohere beats at least one current engine by a meaningful margin on a
  user-relevant subset;
- silence/non-speech behavior is controlled by VAD/noise gating;
- named entities and punctuation are visibly strong.

Fail if:

- Parakeet or Whisper wins on the key target corpus;
- Cohere only wins on cherry-picked synthetic audio;
- hallucination on silence is unacceptable.

### Gate 2 - Latency And Throughput

Pass if:

- short dictation stop-to-text latency is acceptable for an optional quality
  engine;
- long files run faster than realtime by a comfortable margin;
- meeting finalization is practical.

Fail if:

- dictation feels broken compared with Parakeet;
- long meetings are too slow to justify quality gains.

### Gate 3 - Memory And Stability

Pass if:

- 16 GB Macs can run the engine without app instability;
- unload releases enough memory;
- repeated runs do not climb in memory;
- 8 GB behavior is explicitly measured and documented.

Fail if:

- the runtime destabilizes the app or the system;
- memory cannot be reclaimed;
- the product would need hidden hardware requirements.

### Gate 4 - Integration Safety

Pass if:

- engine switching remains blocked during active work;
- meeting leases pin engine/language at start;
- CLI output is additive-compatible;
- export degradation is explicit;
- tests cover empty word timestamps.

Fail if:

- Cohere creates a separate STT control plane;
- it bypasses scheduler/runtime ownership;
- settings can create mixed-engine meetings.

### Gate 5 - Product Worthiness

Pass if:

- Cohere has a clear user segment;
- quality win is measurable;
- product limitations are honest and understandable;
- support burden is acceptable.

Fail if:

- the only benefit is novelty;
- timestamps/diarization losses make the product worse;
- model distribution is not clean.

## Future Agent Operating Protocol

A future coding agent should run this project as a sequence of narrow,
evidence-producing PRs. Each PR should have one goal, one benchmark artifact,
and one rollback story.

Rules:

1. Re-check live docs and model/runtime repos at the start of each milestone.
2. Work in an isolated worktree if the current checkout is dirty.
3. Do not modify product UI before CLI and benchmark proof.
4. Do not change the default engine.
5. Do not add a branch dependency to shipping code.
6. Preserve MacParakeet's `STTRuntime` and `STTScheduler` control plane.
7. Attach benchmark TSV/JSON and summary tables to every optimization claim.
8. Profile before optimizing.
9. Optimize one bottleneck at a time.
10. Stop if the benchmark data does not justify the next phase.

## Suggested Agent Prompts

### Prompt 1 - Baseline Research Refresh

```text
Refresh the Cohere Transcribe local runtime landscape for MacParakeet.
Verify Cohere model docs, Hugging Face model card, MLXAudio Swift Cohere
support, vLLM support, and available MLX conversions. Update
docs/research/cohere-transcribe-stt-2026-06.md only if facts changed.
Do not implement code. Include source links and exact model/runtime revisions.
```

### Prompt 2 - Benchmark Harness

```text
Create a reproducible benchmark harness for Cohere Transcribe against
MacParakeet's Parakeet v3, Parakeet v2, Nemotron, and Whisper paths. Keep the
first version outside product UI. Capture WER/CER, wall time, realtime factor,
cold/warm load, peak memory, and transcript outputs. Document commands and raw
artifact paths. Do not claim product readiness.
```

### Prompt 3 - CLI-Only Cohere Spike

```text
Implement a CLI-only experimental Cohere engine behind MacParakeet's existing
STT runtime/scheduler architecture. Add explicit language selection and return
empty word timestamps. Keep Parakeet default and do not add Settings UI. Run the
benchmark harness through the real CLI path and summarize quality, latency, and
memory against current engines.
```

### Prompt 4 - Runtime Profiling

```text
Profile the experimental Cohere CLI path and identify the top three bottlenecks
by measured time and memory. Separate audio decode/resample, feature extraction,
encoder, decoder, chunking, and result assembly. Propose exactly one
optimization PR based on evidence.
```

### Prompt 5 - Quantization Evaluation

```text
Evaluate fp16 and int8 Cohere MLX artifacts on the MacParakeet corpus. Report
WER/CER deltas, named-entity changes, punctuation changes, latency, disk size,
and memory. Do not switch defaults or product copy. Recommend whether int8 is
acceptable for a future optional engine.
```

### Prompt 6 - Product Decision Memo

```text
Write a product decision memo for whether MacParakeet should ship Cohere as an
optional local engine. Ground the decision in benchmark data, local-first
constraints, timestamp/export degradation, model distribution, and support
risk. Include a clear yes/no recommendation.
```

## Engineering Deliverables

Minimum useful deliverables:

- updated research note if external facts drifted;
- benchmark corpus manifest;
- benchmark harness;
- raw benchmark artifacts;
- summary report;
- CLI-only Cohere experiment branch;
- runtime profile;
- quantization comparison;
- product decision memo.

Only after those:

- Settings integration;
- docs/spec updates;
- release notes;
- support copy.

## Kill Criteria

Stop the project if any of these are true:

- Cohere does not beat current engines on a meaningful real corpus.
- Memory footprint is unacceptable on target Macs.
- Converted weight distribution cannot be made clean.
- Runtime cannot be made reliable without a Python/server dependency.
- Missing timestamps make the target workflows worse than current engines.
- Engineering cost crowds out higher-trust capture/recovery work.

## Success Criteria

This project becomes worth product integration if:

- Cohere produces clearly better final text for at least one important user
  segment;
- the local runtime is stable on supported Apple Silicon Macs;
- memory behavior is understood and acceptable;
- model artifacts have a clean download/distribution story;
- MacParakeet can present the limitation honestly:
  "High-quality final text, manual language, no word timestamps";
- the implementation stays inside the shared STT runtime/scheduler control
  plane.

## Reference Links

Cohere:

- https://docs.cohere.com/docs/transcribe
- https://docs.cohere.com/reference/create-audio-transcription
- https://docs.cohere.com/changelog
- https://huggingface.co/CohereLabs/cohere-transcribe-03-2026
- https://huggingface.co/blog/CohereLabs/cohere-transcribe-03-2026-release

Apple Silicon runtimes:

- https://github.com/ml-explore/mlx-swift
- https://github.com/ml-explore/mlx-swift-lm
- https://github.com/Blaizzy/mlx-audio-swift
- https://github.com/Blaizzy/mlx-audio-swift/blob/main/Sources/MLXAudioSTT/Models/CohereTranscribe/README.md
- https://github.com/Blaizzy/mlx-audio-swift/blob/main/Package.swift
- https://huggingface.co/beshkenadze/cohere-transcribe-03-2026-mlx-fp16
- https://huggingface.co/appautomaton/cohere-asr-mlx

Server/reference runtimes:

- https://docs.vllm.ai/en/latest/models/supported_models/
- https://docs.vllm.ai/en/latest/contributing/model/transcription/

MacParakeet:

- `docs/research/cohere-transcribe-stt-2026-06.md`
- `docs/planning/2026-06-nemotron-stt-benchmark-report.md`
- `spec/06-stt-engine.md`
- `spec/adr/002-local-only.md`
- `spec/adr/021-whisperkit-multilingual-stt.md`
