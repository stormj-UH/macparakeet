import XCTest
@testable import MacParakeet
@testable import MacParakeetCore
@testable import MacParakeetViewModels

@MainActor
final class MeetingActivityDetectionCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var settings: SettingsViewModel!
    private var audioCollector: FakeAudioCollector!
    private var cameraCollector: FakeCameraCollector!
    private var recordingActive = false
    private var promptIdentities: [MeetingIdentity] = []
    private var promptCallbacks: [MeetingIdentity: @MainActor (MeetingActivityPromptOutcome) -> Void] = [:]
    private var closePromptCount = 0
    private var confirmedTriggers: [TelemetryMeetingRecordingTrigger] = []
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        suiteName = "com.macparakeet.tests.activity-detection.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(
            MeetingActivityDetectionMode.prompt.rawValue,
            forKey: MeetingActivityDetectionPreferences.modeKey
        )
        Telemetry.configure(NoOpTelemetryService())
        settings = SettingsViewModel(defaults: defaults)
        audioCollector = FakeAudioCollector()
        cameraCollector = FakeCameraCollector()
        recordingActive = false
        promptIdentities = []
        promptCallbacks = [:]
        closePromptCount = 0
        confirmedTriggers = []
    }

    override func tearDown() {
        Telemetry.configure(NoOpTelemetryService())
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        settings = nil
        audioCollector = nil
        cameraCollector = nil
        promptCallbacks = [:]
        super.tearDown()
    }

    func testActiveRecordingSuppressesPromptAndCollectors() {
        recordingActive = true
        let coordinator = makeCoordinator()

        coordinator.start()
        coordinator.testHook_setAudioSnapshotWithoutScheduling(snapshot(input: [.zoom]))
        coordinator.testHook_forceEvaluate(now: now.addingTimeInterval(10))

        XCTAssertFalse(audioCollector.isStarted)
        XCTAssertFalse(cameraCollector.isStarted)
        XCTAssertTrue(promptIdentities.isEmpty)

        coordinator.stop()
    }

    func testModeOffTearsCollectorsDown() async {
        let coordinator = makeCoordinator()
        coordinator.start()

        XCTAssertTrue(audioCollector.isStarted)

        settings.meetingActivityDetectionMode = .off
        await waitForRunLoop()

        XCTAssertFalse(audioCollector.isStarted)
        XCTAssertFalse(cameraCollector.isStarted)
        XCTAssertGreaterThan(closePromptCount, 0)

        coordinator.stop()
    }

    func testPromptShowsAfterDwellAndConfirmRoutesActivityDetectionTrigger() {
        let coordinator = makeCoordinator()
        let identity = MeetingIdentity(source: .app, app: .zoom)
        coordinator.start()
        coordinator.testHook_setAudioSnapshotWithoutScheduling(snapshot(input: [.zoom]))

        coordinator.testHook_forceEvaluate(now: now)
        XCTAssertTrue(promptIdentities.isEmpty)

        coordinator.testHook_forceEvaluate(now: now.addingTimeInterval(3))
        XCTAssertEqual(promptIdentities, [identity])

        promptCallbacks[identity]?(.accepted)

        XCTAssertEqual(confirmedTriggers, [.activityDetection])
        XCTAssertFalse(audioCollector.isStarted)
        XCTAssertFalse(cameraCollector.isStarted)

        coordinator.stop()
    }

    func testDeclineSuppressesSameIdentityForCooldown() {
        let coordinator = makeCoordinator()
        let identity = MeetingIdentity(source: .app, app: .zoom)
        coordinator.start()
        coordinator.testHook_setAudioSnapshotWithoutScheduling(snapshot(input: [.zoom]))

        coordinator.testHook_forceEvaluate(now: now)
        coordinator.testHook_forceEvaluate(now: now.addingTimeInterval(3))
        XCTAssertEqual(promptIdentities, [identity])

        coordinator.testHook_handlePromptOutcome(.declined, identity: identity, now: now.addingTimeInterval(3))

        XCTAssertEqual(coordinator.testHook_suppressedIdentities[identity], now.addingTimeInterval(3 + 30 * 60))

        coordinator.testHook_forceEvaluate(now: now.addingTimeInterval(60))
        XCTAssertEqual(promptIdentities, [identity])

        coordinator.testHook_forceEvaluate(now: now.addingTimeInterval(31 * 60))
        XCTAssertEqual(promptIdentities, [identity, identity])

        coordinator.stop()
    }

    func testCameraCollectorRunsOnlyWhileMicHoldersExist() {
        let coordinator = makeCoordinator()
        coordinator.start()

        coordinator.testHook_setAudioSnapshotWithoutScheduling(snapshot())
        XCTAssertFalse(cameraCollector.isStarted)

        coordinator.testHook_setAudioSnapshotWithoutScheduling(snapshot(input: [.unknown]))
        XCTAssertTrue(cameraCollector.isStarted)

        coordinator.testHook_setAudioSnapshotWithoutScheduling(snapshot())
        XCTAssertFalse(cameraCollector.isStarted)

        coordinator.stop()
    }

    func testDebounceCoalescesAudioBurstsIntoOnePrompt() async {
        let coordinator = makeCoordinator(
            config: MeetingActivityDetector.Config(mode: .prompt, candidateDwellSeconds: 0),
            debounceInterval: 0.05
        )
        coordinator.start()

        audioCollector.emit(snapshot(input: [.zoom]))
        audioCollector.emit(snapshot(input: [.zoom]))
        audioCollector.emit(snapshot(input: [.zoom]))

        try? await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(promptIdentities, [MeetingIdentity(source: .app, app: .zoom)])

        coordinator.stop()
    }

    private func makeCoordinator(
        config: MeetingActivityDetector.Config = MeetingActivityDetector.Config(
            mode: .prompt,
            candidateDwellSeconds: 3,
            declineCooldownSeconds: 30 * 60
        ),
        debounceInterval: TimeInterval = 0
    ) -> MeetingActivityDetectionCoordinator {
        MeetingActivityDetectionCoordinator(
            settingsViewModel: settings,
            audioCollector: audioCollector,
            cameraCollector: cameraCollector,
            isRecordingActive: { [weak self] in self?.recordingActive ?? false },
            frontmostBundleIDProvider: { nil },
            recognizedMeetingURLProvider: { nil },
            onRecordingConfirmed: { [weak self] trigger in
                self?.confirmedTriggers.append(trigger)
                return 1
            },
            showPrompt: { [weak self] identity, callback in
                self?.promptIdentities.append(identity)
                self?.promptCallbacks[identity] = callback
            },
            closePrompt: { [weak self] in
                self?.closePromptCount += 1
            },
            featureEnabled: true,
            config: config,
            debounceInterval: debounceInterval
        )
    }

    private func waitForRunLoop() async {
        for _ in 0..<5 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func snapshot(
        input: [TestProcess] = [],
        output: [TestProcess] = []
    ) -> ProcessAudioSnapshot {
        let inputActivities = input.map { activity($0, input: true, output: output.contains($0)) }
        let inputPIDs = Set(inputActivities.map(\.pid))
        let outputOnlyActivities = output
            .filter { process in !inputPIDs.contains(process.pid) }
            .map { activity($0, input: false, output: true) }
        return ProcessAudioSnapshot(processes: inputActivities + outputOnlyActivities)
    }

    private func activity(
        _ process: TestProcess,
        input: Bool,
        output: Bool = false
    ) -> AudioProcessActivity {
        AudioProcessActivity(
            pid: process.pid,
            bundleID: process.bundleID,
            isRunningInput: input,
            isRunningOutput: output
        )
    }
}

private final class FakeAudioCollector: AudioProcessActivityCollecting {
    private(set) var isStarted = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var currentSnapshot = ProcessAudioSnapshot(processes: [])
    private var handler: AudioProcessActivityCollecting.SnapshotHandler?

    func start(handler: @escaping AudioProcessActivityCollecting.SnapshotHandler) {
        isStarted = true
        startCount += 1
        self.handler = handler
    }

    func stop() {
        isStarted = false
        stopCount += 1
        handler = nil
    }

    func snapshot() -> ProcessAudioSnapshot {
        currentSnapshot
    }

    func emit(_ snapshot: ProcessAudioSnapshot) {
        currentSnapshot = snapshot
        handler?(snapshot)
    }
}

private final class FakeCameraCollector: CameraActivityCollecting {
    private(set) var isStarted = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var running = false
    private var handler: CameraActivityCollecting.StateHandler?

    func start(handler: @escaping CameraActivityCollecting.StateHandler) {
        isStarted = true
        startCount += 1
        self.handler = handler
    }

    func stop() {
        isStarted = false
        stopCount += 1
        handler = nil
    }

    func cameraRunning() -> Bool {
        running
    }

    func emit(_ running: Bool) {
        self.running = running
        handler?(running)
    }
}

private enum TestProcess {
    case zoom
    case unknown

    var pid: Int32 {
        switch self {
        case .zoom: return 100
        case .unknown: return 200
        }
    }

    var bundleID: String? {
        switch self {
        case .zoom: return "us.zoom.xos"
        case .unknown: return "com.example.unknown"
        }
    }
}
