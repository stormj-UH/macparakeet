import XCTest
@testable import MacParakeetCore
@testable import MacParakeetViewModels

@MainActor
final class SettingsEngineCharacterizationTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private var testDefaultsSuiteName: String!
    private var youtubeDownloadsTestDir: URL!
    private var meetingRecordingsTestDir: URL!

    private func waitUntil(
        timeout: Duration = .seconds(1),
        pollInterval: Duration = .milliseconds(10),
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            if clock.now >= deadline {
                XCTFail("Timed out waiting for condition", file: file, line: line)
                return
            }
            try await Task.sleep(for: pollInterval)
        }
    }

    override func setUp() {
        youtubeDownloadsTestDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mp-youtube-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: youtubeDownloadsTestDir, withIntermediateDirectories: true)
        meetingRecordingsTestDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mp-meetings-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: meetingRecordingsTestDir, withIntermediateDirectories: true)

        testDefaultsSuiteName = "com.macparakeet.tests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testDefaultsSuiteName)!
    }

    override func tearDown() {
        Telemetry.configure(NoOpTelemetryService())

        if let testDefaultsSuiteName {
            testDefaults.removePersistentDomain(forName: testDefaultsSuiteName)
        }
        if let youtubeDownloadsTestDir {
            try? FileManager.default.removeItem(at: youtubeDownloadsTestDir)
        }
        if let meetingRecordingsTestDir {
            try? FileManager.default.removeItem(at: meetingRecordingsTestDir)
        }
        testDefaults = nil
        testDefaultsSuiteName = nil
    }

    private func makeViewModel(
        parakeetCached: @escaping @Sendable (ParakeetModelVariant) -> Bool = { _ in false },
        nemotronCached: @escaping @Sendable (NemotronModelVariant, String?) -> Bool = { _, _ in false }
    ) -> SettingsViewModel {
        SettingsViewModel(
            defaults: testDefaults,
            youtubeDownloadsDirPath: { [youtubeDownloadsTestDir] in
                youtubeDownloadsTestDir?.path ?? AppPaths.youtubeDownloadsDir
            },
            meetingRecordingsDirPath: { [meetingRecordingsTestDir] in
                meetingRecordingsTestDir?.path ?? AppPaths.meetingRecordingsDir
            },
            parakeetModelVariantCached: parakeetCached,
            nemotronModelVariantCached: nemotronCached
        )
    }

    private func waitForModelStatusRefreshToFinish(
        _ vm: SettingsViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        try await waitUntil(file: file, line: line) {
            vm.nemotronModelStatus != .checking &&
                vm.whisperModelStatus != .checking
        }
    }

    func testSelectionDefaultsReadFromSpeechEnginePreferenceHelpers() {
        let vm = makeViewModel()

        XCTAssertEqual(vm.speechEnginePreference, SpeechEnginePreference.current(defaults: testDefaults))
        XCTAssertEqual(vm.parakeetModelVariant, SpeechEnginePreference.parakeetModelVariant(defaults: testDefaults))
        XCTAssertEqual(vm.nemotronModelVariant, SpeechEnginePreference.nemotronModelVariant(defaults: testDefaults))
        XCTAssertEqual(vm.whisperDefaultLanguage, SpeechEnginePreference.whisperDefaultLanguage(defaults: testDefaults) ?? "auto")
        XCTAssertEqual(vm.whisperDefaultLanguage, "auto")
    }

    func testSetSpeechEnginePreferencePersistsWhenTargetModelIsMarkedDownloaded() {
        let vm = makeViewModel()
        vm.whisperModelStatus = .notLoaded

        vm.speechEnginePreference = .whisper

        let reloaded = makeViewModel()
        XCTAssertEqual(reloaded.speechEnginePreference, .whisper)
        XCTAssertEqual(SpeechEnginePreference.current(defaults: testDefaults), .whisper)
        XCTAssertNil(vm.speechEngineError)
    }

    func testSetParakeetModelVariantPersists() {
        let vm = makeViewModel()

        vm.parakeetModelVariant = .v2

        let reloaded = makeViewModel()
        XCTAssertEqual(reloaded.parakeetModelVariant, .v2)
        XCTAssertEqual(SpeechEnginePreference.parakeetModelVariant(defaults: testDefaults), .v2)
    }

    func testSetNemotronModelVariantPersists() {
        let vm = makeViewModel()

        vm.nemotronModelVariant = .english1120

        let reloaded = makeViewModel()
        XCTAssertEqual(reloaded.nemotronModelVariant, .english1120)
        XCTAssertEqual(SpeechEnginePreference.nemotronModelVariant(defaults: testDefaults), .english1120)
    }

    func testSetWhisperDefaultLanguagePersistsNormalizedValue() {
        let vm = makeViewModel()

        vm.whisperDefaultLanguage = "KO_kr"

        let reloaded = makeViewModel()
        XCTAssertEqual(reloaded.whisperDefaultLanguage, "ko")
        XCTAssertEqual(SpeechEnginePreference.whisperDefaultLanguage(defaults: testDefaults), "ko")
    }

    func testRequestConfirmationSetsPendingAndClearsExistingError() {
        let vm = makeViewModel()
        vm.speechEngineError = "previous error"

        vm.requestSpeechEngineSwitchConfirmation(to: .whisper)

        XCTAssertEqual(vm.pendingSpeechEngineSwitchConfirmation, .whisper)
        XCTAssertNil(vm.speechEngineError)
    }

    func testRequestConfirmationIgnoresCurrentEngine() {
        let vm = makeViewModel()

        vm.requestSpeechEngineSwitchConfirmation(to: .parakeet)

        XCTAssertNil(vm.pendingSpeechEngineSwitchConfirmation)
    }

    func testCancelPendingConfirmationClearsPending() {
        let vm = makeViewModel()
        vm.requestSpeechEngineSwitchConfirmation(to: .whisper)

        vm.cancelPendingSpeechEngineSwitchConfirmation()

        XCTAssertNil(vm.pendingSpeechEngineSwitchConfirmation)
    }

    func testConfirmPendingSwitchClearsPendingAndPersistsWhenTargetModelIsMarkedDownloaded() {
        let vm = makeViewModel()
        vm.whisperModelStatus = .notLoaded
        vm.requestSpeechEngineSwitchConfirmation(to: .whisper)

        vm.confirmPendingSpeechEngineSwitch()

        XCTAssertNil(vm.pendingSpeechEngineSwitchConfirmation)
        XCTAssertEqual(vm.speechEnginePreference, .whisper)
        XCTAssertEqual(SpeechEnginePreference.current(defaults: testDefaults), .whisper)
        XCTAssertNil(vm.speechEngineError)
        XCTAssertFalse(vm.speechEngineSwitching)
        XCTAssertNil(vm.speechEngineSwitchTarget)
    }

    func testConfirmPendingSwitchClearsPendingAndRestoresCurrentEngineWhenTargetModelIsMissing() {
        let vm = makeViewModel()
        vm.requestSpeechEngineSwitchConfirmation(to: .whisper)

        vm.confirmPendingSpeechEngineSwitch()

        XCTAssertNil(vm.pendingSpeechEngineSwitchConfirmation)
        XCTAssertEqual(vm.speechEnginePreference, .parakeet)
        XCTAssertEqual(SpeechEnginePreference.current(defaults: testDefaults), .parakeet)
        XCTAssertEqual(vm.speechEngineError, "Download the Whisper model before switching engines.")
        XCTAssertFalse(vm.speechEngineSwitching)
        XCTAssertNil(vm.speechEngineSwitchTarget)
    }

    func testSwitchUnavailableMessageReturnsNilWhenAvailable() {
        XCTAssertNil(SettingsViewModel.speechEngineSwitchUnavailableMessage(for: .available))
    }

    func testSwitchUnavailableMessagePinsCurrentCopyForUnavailableStates() {
        let cases: [(SpeechEngineSwitchAvailability, String)] = [
            (.meetingActive, "Stop the meeting recording to switch engines"),
            (.transcribing, "Finishing transcription — switch when it completes"),
            (.switchInProgress, "Finishing engine switch — try again in a moment"),
            (.unavailable, "Speech engine is temporarily unavailable"),
        ]

        for (availability, message) in cases {
            XCTAssertEqual(
                SettingsViewModel.speechEngineSwitchUnavailableMessage(for: availability),
                message
            )
        }
    }

    func testInstanceSwitchUnavailableMessageReflectsStoredAvailability() {
        let vm = makeViewModel()

        vm.speechEngineSwitchAvailability = .switchInProgress

        XCTAssertEqual(
            vm.speechEngineSwitchUnavailableMessage,
            "Finishing engine switch — try again in a moment"
        )
    }

    // `refreshModelStatus()` also checks Whisper's real on-disk cache; there is
    // no injection seam for that path, so these tests assert only the
    // deterministic Parakeet/Nemotron cache subset and the public Whisper status
    // predicate below.
    func testDownloadedParakeetVariantsReflectsTrueCachedStub() async throws {
        let vm = makeViewModel(parakeetCached: { _ in true })

        vm.refreshModelStatus()

        try await waitUntil { vm.downloadedParakeetVariants == Set(ParakeetModelVariant.allCases) }
        XCTAssertEqual(vm.downloadedParakeetVariants, Set(ParakeetModelVariant.allCases))
        XCTAssertEqual(vm.parakeetStatus, .unknown)
        XCTAssertEqual(vm.parakeetStatusDetail, "Unavailable in this runtime.")
    }

    func testDownloadedParakeetVariantsReflectsFalseCachedStub() async throws {
        let vm = makeViewModel(parakeetCached: { _ in false })

        vm.refreshModelStatus()

        try await waitForModelStatusRefreshToFinish(vm)
        XCTAssertTrue(vm.downloadedParakeetVariants.isEmpty)
        XCTAssertEqual(vm.parakeetStatus, .unknown)
        XCTAssertEqual(vm.parakeetStatusDetail, "Unavailable in this runtime.")
    }

    func testDownloadedNemotronVariantsReflectsTrueCachedStubAndMarksSelectedVariantAvailable() async throws {
        let vm = makeViewModel(nemotronCached: { _, _ in true })

        vm.refreshModelStatus()

        try await waitUntil { vm.downloadedNemotronVariants == Set(NemotronModelVariant.allCases) }
        XCTAssertEqual(vm.downloadedNemotronVariants, Set(NemotronModelVariant.allCases))
        XCTAssertTrue(vm.isNemotronModelAvailable)
        XCTAssertEqual(vm.nemotronModelStatus, .notLoaded)
        XCTAssertEqual(
            vm.nemotronModelStatusDetail,
            "Nemotron 3.5 ASR Streaming 0.6B · Installed locally, loads when selected."
        )
    }

    func testDownloadedNemotronVariantsReflectsFalseCachedStubAndMarksSelectedVariantUnavailable() async throws {
        let vm = makeViewModel(nemotronCached: { _, _ in false })

        vm.refreshModelStatus()

        try await waitForModelStatusRefreshToFinish(vm)
        XCTAssertTrue(vm.downloadedNemotronVariants.isEmpty)
        XCTAssertFalse(vm.isNemotronModelAvailable)
        XCTAssertEqual(vm.nemotronModelStatus, .notDownloaded)
        XCTAssertEqual(
            vm.nemotronModelStatusDetail,
            "Nemotron 3.5 ASR Streaming 0.6B · Needs download before use."
        )
    }

    func testRefreshModelStatusPassesStoredNemotronLanguageToCachedStub() async throws {
        SpeechEnginePreference.saveNemotronDefaultLanguage("en_US", defaults: testDefaults)
        let recorder = NemotronCacheCheckRecorder()
        let vm = makeViewModel(nemotronCached: { variant, language in
            recorder.record(variant, language)
            return variant == .english1120
        })

        vm.refreshModelStatus()

        try await waitUntil { vm.downloadedNemotronVariants == [.english1120] }
        XCTAssertEqual(vm.downloadedNemotronVariants, [.english1120])
        XCTAssertTrue(recorder.calls.contains { $0.variant == .multilingual1120 && $0.language == "en-US" })
        XCTAssertTrue(recorder.calls.contains { $0.variant == .english1120 && $0.language == "en-US" })
    }

    func testIsWhisperModelDownloadedReflectsPublicStatus() {
        let vm = makeViewModel()

        vm.whisperModelStatus = .notDownloaded
        XCTAssertFalse(vm.isWhisperModelDownloaded)

        vm.whisperModelStatus = .notLoaded
        XCTAssertTrue(vm.isWhisperModelDownloaded)

        vm.whisperModelStatus = .ready
        XCTAssertTrue(vm.isWhisperModelDownloaded)
    }
}

private final class NemotronCacheCheckRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCalls: [(variant: NemotronModelVariant, language: String?)] = []

    func record(_ variant: NemotronModelVariant, _ language: String?) {
        lock.lock()
        recordedCalls.append((variant, language))
        lock.unlock()
    }

    var calls: [(variant: NemotronModelVariant, language: String?)] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCalls
    }
}
