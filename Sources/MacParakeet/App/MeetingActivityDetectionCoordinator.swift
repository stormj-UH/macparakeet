import AppKit
import MacParakeetCore
import MacParakeetViewModels
import OSLog

protocol AudioProcessActivityCollecting: AnyObject {
    typealias SnapshotHandler = @Sendable (ProcessAudioSnapshot) -> Void

    func start(handler: @escaping SnapshotHandler)
    func stop()
    func snapshot() -> ProcessAudioSnapshot
}

extension AudioProcessActivityCollector: AudioProcessActivityCollecting {}

protocol CameraActivityCollecting: AnyObject {
    typealias StateHandler = @Sendable (Bool) -> Void

    func start(handler: @escaping StateHandler)
    func stop()
    func cameraRunning() -> Bool
}

extension CameraActivityCollector: CameraActivityCollecting {}

enum MeetingActivityPromptOutcome: Sendable {
    case accepted
    case declined
}

/// ADR-024 app-layer owner. It observes metadata-only meeting activity while
/// detection is enabled and no recording is active, then prompts before routing
/// the user through the normal meeting recording flow.
@MainActor
final class MeetingActivityDetectionCoordinator {
    typealias PromptPresenter = @MainActor (
        _ identity: MeetingIdentity,
        _ onOutcome: @escaping @MainActor (MeetingActivityPromptOutcome) -> Void
    ) -> Void

    private let settingsViewModel: SettingsViewModel
    private let audioCollector: any AudioProcessActivityCollecting
    private let cameraCollector: any CameraActivityCollecting
    private let isRecordingActive: @MainActor () -> Bool
    private let frontmostBundleIDProvider: @MainActor () -> String?
    private let recognizedMeetingURLProvider: @MainActor () -> String?
    private let onRecordingConfirmed: @MainActor (TelemetryMeetingRecordingTrigger) -> Int?
    private let showPrompt: PromptPresenter
    private let closePrompt: @MainActor () -> Void
    private let featureEnabled: Bool
    private let baseConfig: MeetingActivityDetector.Config
    private let debounceInterval: TimeInterval
    private let logger = Logger(subsystem: "com.macparakeet", category: "MeetingActivityDetection")

    private var latestAudioSnapshot = ProcessAudioSnapshot(processes: [])
    private var latestCameraRunning = false
    private var candidateSince: Date?
    private var candidateIdentity: MeetingIdentity?
    private var suppressedIdentities: [MeetingIdentity: Date] = [:]
    private var promptIdentity: MeetingIdentity?
    private var isEvaluating = false
    private var evaluateAgainRequested = false

    nonisolated(unsafe) private var settingsObserver: NSObjectProtocol?
    nonisolated(unsafe) private var appActivationObserver: NSObjectProtocol?
    nonisolated(unsafe) private var wakeObserver: NSObjectProtocol?
    nonisolated(unsafe) private var debounceTimer: Timer?
    private var audioCollectorStarted = false
    private var cameraCollectorStarted = false

    init(
        settingsViewModel: SettingsViewModel,
        audioCollector: any AudioProcessActivityCollecting = AudioProcessActivityCollector(),
        cameraCollector: any CameraActivityCollecting = CameraActivityCollector(),
        isRecordingActive: @escaping @MainActor () -> Bool,
        frontmostBundleIDProvider: @escaping @MainActor () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        },
        recognizedMeetingURLProvider: @escaping @MainActor () -> String? = { nil },
        onRecordingConfirmed: @escaping @MainActor (TelemetryMeetingRecordingTrigger) -> Int?,
        promptController: MeetingActivityPromptController? = nil,
        showPrompt: PromptPresenter? = nil,
        closePrompt: (@MainActor () -> Void)? = nil,
        featureEnabled: Bool = AppFeatures.meetingActivityDetectionEnabled,
        config: MeetingActivityDetector.Config = .default,
        debounceInterval: TimeInterval = 0.5
    ) {
        self.settingsViewModel = settingsViewModel
        self.audioCollector = audioCollector
        self.cameraCollector = cameraCollector
        self.isRecordingActive = isRecordingActive
        self.frontmostBundleIDProvider = frontmostBundleIDProvider
        self.recognizedMeetingURLProvider = recognizedMeetingURLProvider
        self.onRecordingConfirmed = onRecordingConfirmed
        let promptController = promptController ?? MeetingActivityPromptController()
        self.showPrompt = showPrompt ?? { _, onOutcome in
            promptController.show(onOutcome: onOutcome)
        }
        self.closePrompt = closePrompt ?? {
            promptController.close()
        }
        self.featureEnabled = featureEnabled
        self.baseConfig = config
        self.debounceInterval = debounceInterval
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        debounceTimer?.invalidate()
    }

    func start() {
        guard featureEnabled, AppFeatures.meetingRecordingEnabled else { return }
        registerSettingsObserver()
        refreshObservation()
        logger.info("Meeting activity detection coordinator started")
    }

    func stop() {
        stopObservation(clearSession: true)
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }
        logger.info("Meeting activity detection coordinator stopped")
    }

    func recordingDidStart() {
        refreshObservation()
    }

    func recordingDidEnd() {
        refreshObservation()
    }

    // MARK: - Observers

    private func registerSettingsObserver() {
        guard settingsObserver == nil else { return }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .macParakeetMeetingActivitySettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshObservation() }
        }
    }

    private func registerWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        if appActivationObserver == nil {
            appActivationObserver = center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.scheduleEvaluation() }
            }
        }
        if wakeObserver == nil {
            wakeObserver = center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshObservation() }
            }
        }
    }

    private func unregisterWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        if let appActivationObserver {
            center.removeObserver(appActivationObserver)
            self.appActivationObserver = nil
        }
        if let wakeObserver {
            center.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    private func refreshObservation() {
        guard shouldObserve else {
            stopObservation(clearSession: true)
            return
        }

        registerWorkspaceObservers()
        startAudioCollectorIfNeeded()
        latestAudioSnapshot = audioCollector.snapshot()
        updateCameraCollectorForAudio()
        scheduleEvaluation()
    }

    private func startAudioCollectorIfNeeded() {
        guard !audioCollectorStarted else { return }
        audioCollectorStarted = true
        audioCollector.start { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.handleAudioSnapshot(snapshot)
            }
        }
    }

    private func stopObservation(clearSession: Bool) {
        debounceTimer?.invalidate()
        debounceTimer = nil
        if audioCollectorStarted {
            audioCollector.stop()
            audioCollectorStarted = false
        }
        stopCameraCollector(resetState: true)
        unregisterWorkspaceObservers()
        closePrompt()
        latestAudioSnapshot = ProcessAudioSnapshot(processes: [])
        promptIdentity = nil
        candidateSince = nil
        candidateIdentity = nil
        if clearSession {
            suppressedIdentities = [:]
        }
    }

    private func handleAudioSnapshot(_ snapshot: ProcessAudioSnapshot) {
        latestAudioSnapshot = snapshot
        updateCameraCollectorForAudio()
        scheduleEvaluation()
    }

    private func handleCameraState(_ running: Bool) {
        latestCameraRunning = running
        scheduleEvaluation()
    }

    private func updateCameraCollectorForAudio() {
        guard !latestAudioSnapshot.inputHolders.isEmpty else {
            stopCameraCollector(resetState: true)
            return
        }
        guard !cameraCollectorStarted else {
            latestCameraRunning = cameraCollector.cameraRunning()
            return
        }
        cameraCollectorStarted = true
        latestCameraRunning = cameraCollector.cameraRunning()
        cameraCollector.start { [weak self] running in
            Task { @MainActor [weak self] in
                self?.handleCameraState(running)
            }
        }
    }

    private func stopCameraCollector(resetState: Bool) {
        if cameraCollectorStarted {
            cameraCollector.stop()
            cameraCollectorStarted = false
        }
        if resetState {
            latestCameraRunning = false
        }
    }

    private func scheduleEvaluation() {
        guard shouldObserve else {
            stopObservation(clearSession: true)
            return
        }

        debounceTimer?.invalidate()
        guard debounceInterval > 0 else {
            evaluate(now: Date())
            return
        }
        let timer = Timer(timeInterval: debounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.evaluate(now: Date()) }
        }
        RunLoop.main.add(timer, forMode: .common)
        debounceTimer = timer
    }

    // MARK: - Evaluation

    private func evaluate(now: Date) {
        guard !isEvaluating else {
            evaluateAgainRequested = true
            return
        }
        isEvaluating = true
        defer {
            isEvaluating = false
            if evaluateAgainRequested {
                evaluateAgainRequested = false
                scheduleEvaluation()
            }
        }

        guard shouldObserve else {
            stopObservation(clearSession: true)
            return
        }

        suppressedIdentities = suppressedIdentities.filter { $0.value > now }

        let signal = ActivitySignalSnapshot(
            audio: latestAudioSnapshot,
            cameraRunning: latestCameraRunning,
            frontmostBundleID: frontmostBundleIDProvider(),
            hasRecognizedMeetingURL: recognizedMeetingURLProvider()
                .map { MeetingLinkParser.shared.isMeetingUrl($0) } ?? false
        )
        let currentIdentity = MeetingActivityDetector.candidateIdentity(for: signal)
        let detectorCandidateSince = updateCandidateState(identity: currentIdentity, now: now)
        var config = baseConfig
        config.mode = effectiveMode

        let events = MeetingActivityDetector.evaluate(
            signal: signal,
            now: now,
            config: config,
            activeRecording: isRecordingActive(),
            candidateSince: detectorCandidateSince,
            suppressedIdentities: suppressedIdentities
        )
        handle(events: events, now: now)
    }

    private func updateCandidateState(identity: MeetingIdentity?, now: Date) -> Date? {
        guard identity != candidateIdentity else { return candidateSince }

        if let identity {
            candidateIdentity = identity
            candidateSince = now
            return candidateSince
        }

        let previousCandidateSince = candidateSince
        candidateIdentity = nil
        candidateSince = nil
        return previousCandidateSince
    }

    private func handle(events: [MeetingActivityDetector.DetectionEvent], now: Date) {
        for event in events {
            switch event {
            case .signalCleared:
                closePrompt()
                promptIdentity = nil
            case .promptToRecord(let identity), .autoStartDue(let identity):
                presentPrompt(for: identity)
            }
        }
    }

    private func presentPrompt(for identity: MeetingIdentity) {
        guard promptIdentity != identity else { return }
        closePrompt()
        promptIdentity = identity
        let telemetry = Self.telemetryShape(for: identity)
        Telemetry.send(.meetingActivityDetectionShown(
            signalSource: telemetry.source,
            appCategory: telemetry.category
        ))
        showPrompt(identity) { [weak self] outcome in
            self?.handlePromptOutcome(outcome, identity: identity, now: Date())
        }
    }

    private func handlePromptOutcome(
        _ outcome: MeetingActivityPromptOutcome,
        identity: MeetingIdentity,
        now: Date
    ) {
        guard promptIdentity == identity else { return }
        promptIdentity = nil
        let telemetry = Self.telemetryShape(for: identity)

        switch outcome {
        case .accepted:
            Telemetry.send(.meetingActivityDetectionAccepted(
                signalSource: telemetry.source,
                appCategory: telemetry.category
            ))
            if onRecordingConfirmed(.activityDetection) != nil {
                stopObservation(clearSession: true)
            } else {
                scheduleEvaluation()
            }
        case .declined:
            suppressedIdentities[identity] = now.addingTimeInterval(baseConfig.declineCooldownSeconds)
            Telemetry.send(.meetingActivityDetectionDeclined(
                signalSource: telemetry.source,
                appCategory: telemetry.category
            ))
        }
    }

    private var effectiveMode: MeetingActivityDetectionMode {
        switch settingsViewModel.meetingActivityDetectionMode {
        case .off:
            return .off
        case .prompt, .autoStart:
            // Phase C ships prompt mode only. A hand-edited `.autoStart`
            // preference is clamped to prompt until Phase D adds countdown
            // auto-start wiring.
            return .prompt
        }
    }

    private var shouldObserve: Bool {
        featureEnabled
            && AppFeatures.meetingRecordingEnabled
            && settingsViewModel.meetingActivityDetectionMode != .off
            && !isRecordingActive()
    }

    private static func telemetryShape(
        for identity: MeetingIdentity
    ) -> (source: TelemetryMeetingActivitySignalSource, category: TelemetryMeetingActivityAppCategory) {
        switch identity.source {
        case .camera:
            return (.camera, .unknown)
        case .app:
            return (.app, telemetryCategory(for: identity.app))
        }
    }

    private static func telemetryCategory(for app: MeetingApp?) -> TelemetryMeetingActivityAppCategory {
        switch app {
        case .zoom, .teams, .webex, .facetime:
            return .dedicated
        case .slack:
            return .chat
        case .browser:
            return .browser
        case .none:
            return .unknown
        }
    }
}

extension MeetingActivityDetectionCoordinator {
    var testHook_isAudioCollectorStarted: Bool { audioCollectorStarted }
    var testHook_isCameraCollectorStarted: Bool { cameraCollectorStarted }
    var testHook_promptIdentity: MeetingIdentity? { promptIdentity }
    var testHook_suppressedIdentities: [MeetingIdentity: Date] { suppressedIdentities }

    func testHook_handleAudioSnapshot(_ snapshot: ProcessAudioSnapshot) {
        handleAudioSnapshot(snapshot)
    }

    func testHook_setAudioSnapshotWithoutScheduling(_ snapshot: ProcessAudioSnapshot) {
        latestAudioSnapshot = snapshot
        updateCameraCollectorForAudio()
    }

    func testHook_handleCameraState(_ running: Bool) {
        handleCameraState(running)
    }

    func testHook_forceEvaluate(now: Date = Date()) {
        debounceTimer?.invalidate()
        debounceTimer = nil
        evaluate(now: now)
    }

    func testHook_handlePromptOutcome(
        _ outcome: MeetingActivityPromptOutcome,
        identity: MeetingIdentity,
        now: Date
    ) {
        handlePromptOutcome(outcome, identity: identity, now: now)
    }
}
