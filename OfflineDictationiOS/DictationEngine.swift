import AVFoundation
import Observation
import UIKit
import WhisperKit

// Records audio, talks to the keyboard through SharedStorage, and transcribes with the model.
//
// The first dictation started from the keyboard opens this app. After that the app keeps the microphone
// "ready" in the background: audio is measured but not saved, and nothing is transcribed. Each later tap
// on the keyboard's mic starts a dictation straight away, with no trip back to the app. The mic turns off
// after a while without use, or when the user turns it off.
@MainActor @Observable
final class DictationEngine {
    enum Phase { case idle, recording, transcribing }

    let model = ModelManager()

    private(set) var phase: Phase = .idle
    private(set) var hint = "Tap to dictate"
    private(set) var transcript = ""
    private(set) var elapsed: TimeInterval = 0
    private(set) var levels: [Double] = []
    private(set) var micDenied = false
    // True when the keyboard's mic started this session, so the app can guide the user back.
    private(set) var startedFromKeyboard = false
    // True while the on-device model is tidying the transcript, so the UI can offer to skip it.
    private(set) var isPolishing = false
    // The microphone is being kept ready in the background between dictations.
    private(set) var isArmed = false
    private(set) var standbySecondsLeft = 0

    // How long the microphone stays ready without any dictation before it turns itself off.
    static let standbyTimeout: TimeInterval = 600

    @ObservationIgnored private let capture = AudioCapture()
    @ObservationIgnored private var recordingURL: URL?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private let liveActivity = LiveActivityManager()
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var transcriptionTask: Task<Void, Never>?
    @ObservationIgnored private var transcribeWatchdog: Timer?
    // Bumped whenever a transcription starts or is cancelled, so a stale run can't touch newer state.
    @ObservationIgnored private var transcriptionGeneration = 0
    @ObservationIgnored private var lastActivity = Date()

    private let maxLevelSamples = 40

    private static var didTidyOnLaunch = false

    init() {
        // Closing the app (swiping it away in the app switcher) turns the microphone off.
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.shutDownForTermination() }
        }

        // If the system takes the microphone away (a call, Siri), stop being "ready" instead of pretending.
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                if raw == AVAudioSession.InterruptionType.began.rawValue { self?.handleInterruption() }
            }
        }
        // A route change (headphones, Bluetooth) restarts the audio engine; try to carry on.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        }
    }

    // Runs once per launch. A previous run may have been killed while "ready", so make sure nothing still
    // claims the mic is on. (Not done in init: SwiftUI may build and discard extra engines at startup.)
    func tidyOnLaunch() {
        guard !Self.didTidyOnLaunch else { return }
        Self.didTidyOnLaunch = true
        SharedStorage.setArmed(false)
        SharedStorage.setRecordingActive(false)
        SharedStorage.setRecordingLevel(0)
        SharedStorage.setPolishing(false)
        LiveActivityManager.endLeftovers()
    }

    // MARK: Entry points

    func toggle() {
        switch phase {
        case .idle: start(fromKeyboard: false)
        case .recording: stop()
        case .transcribing: break
        }
    }

    // The keyboard asked for a recording (via the shared flag). Safe to call any time.
    func startIfRequested() {
        guard SharedStorage.isRecordingRequested(), phase == .idle else { return }
        start(fromKeyboard: true)
    }

    func start(fromKeyboard: Bool) {
        guard phase == .idle, !isStarting else { return }

        // Already listening in the background: start at once, with no permission or audio session work.
        if isArmed, capture.isRunning {
            startCapturing(fromKeyboard: fromKeyboard)
            return
        }

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            micDenied = false
            Task { await beginRecording(fromKeyboard: fromKeyboard) }
        case .undetermined:
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if granted {
                            self.micDenied = false
                            Task { await self.beginRecording(fromKeyboard: fromKeyboard) }
                        } else {
                            self.denyMicrophone()
                        }
                    }
                }
            }
        default:
            denyMicrophone()
        }
    }

    private func denyMicrophone() {
        micDenied = true
        hint = "Allow microphone access in Settings"
        SharedStorage.clearRecordingRequest()
    }

    // The app is being closed: stop the microphone and clear every sign that it was ready.
    private func shutDownForTermination() {
        isArmed = false
        SharedStorage.setArmed(false)
        SharedStorage.setRecordingActive(false)
        SharedStorage.setRecordingLevel(0)
        SharedStorage.setPolishing(false)
        capture.endRecording()
        capture.stop()
        timer?.invalidate()
        timer = nil
        liveActivity.endNow()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // The user turned the ready microphone off (or asked to from the app).
    func turnOffMic() {
        if phase == .recording { cancel() }
        disarm(reason: nil)
    }

    // MARK: Starting the microphone

    // Cold start: opens the audio session and the microphone, then starts the first dictation.
    private func beginRecording(fromKeyboard: Bool) async {
        guard phase == .idle, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        if SharedStorage.isCancelRequested() {
            SharedStorage.clearCancelRequest()
            SharedStorage.clearRecordingRequest()
            hint = "Dictation cancelled"
            return
        }

        // Used from the keyboard, the keyboard plays its own cue; used here, the app does. It plays before
        // recording starts so it isn't captured, and it obeys the silent switch.
        if !fromKeyboard {
            CuePlayer.shared.play(.start, deactivateAfter: false)
            try? await Task.sleep(for: .milliseconds(320))
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
        } catch {
            hint = "Couldn't access the microphone"
            return
        }

        do {
            try capture.start()
        } catch {
            hint = "Couldn't start the microphone"
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            return
        }

        // A dictation started from the keyboard keeps the microphone ready afterwards.
        if fromKeyboard { arm() }
        startCapturing(fromKeyboard: fromKeyboard)
    }

    private func arm() {
        guard !isArmed else { return }
        isArmed = true
        lastActivity = Date()
        SharedStorage.setArmed(true)
        ensureTimer()
    }

    private func disarm(reason: String?) {
        guard isArmed else { return }
        isArmed = false
        SharedStorage.setArmed(false)
        capture.stop()
        levels = []
        standbySecondsLeft = 0
        if let reason { hint = reason }

        // If a transcription is still running, it cleans up when it finishes.
        if phase == .idle {
            liveActivity.end()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            stopTimerIfIdle()
        }
    }

    private func handleInterruption() {
        guard isArmed else { return }
        if phase == .recording { stop() }
        disarm(reason: "The microphone was interrupted, so it turned off.")
    }

    private func handleConfigurationChange() {
        guard isArmed || phase == .recording else { return }
        do {
            try capture.restart()
        } catch {
            if phase == .recording { stop() }
            disarm(reason: "The microphone stopped, so it turned off.")
        }
    }

    // MARK: Recording

    // Starts saving speech. The microphone is already running at this point.
    private func startCapturing(fromKeyboard: Bool) {
        if SharedStorage.isCancelRequested() {
            SharedStorage.clearCancelRequest()
            SharedStorage.clearRecordingRequest()
            hint = "Dictation cancelled"
            if !isArmed { shutDownMicrophone() }
            return
        }

        SharedStorage.clearStopRequest()

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("liveRecording.wav")
        recordingURL = fileURL
        do {
            try capture.beginRecording(to: fileURL)
        } catch {
            hint = "Couldn't start recording: \(error.localizedDescription)"
            SharedStorage.clearRecordingRequest()
            if !isArmed { shutDownMicrophone() }
            return
        }

        SharedStorage.clearRecordingRequest()
        SharedStorage.setInputName(AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName ?? "iPhone Microphone")

        elapsed = 0
        levels = []
        startedFromKeyboard = fromKeyboard
        phase = .recording
        hint = "Listening"
        lastActivity = Date()
        SharedStorage.setRecordingActive(true)
        if fromKeyboard || isArmed { liveActivity.show(.recording, startedAt: Date()) }
        ensureTimer()
    }

    // Stops the microphone and releases the audio session (when it isn't being kept ready).
    private func shutDownMicrophone() {
        capture.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        stopTimerIfIdle()
    }

    private func ensureTimer() {
        guard timer == nil else { return }
        var tick = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { _ in
            MainActor.assumeIsolated {
                tick += 1
                self.handleTick(tick)
            }
        }
    }

    private func stopTimerIfIdle() {
        guard !isArmed, phase != .recording else { return }
        timer?.invalidate()
        timer = nil
    }

    private func handleTick(_ tick: Int) {
        // Keep the Dynamic Island entry from going stale while the app is alive (about every 30 seconds).
        if tick % 430 == 0 { liveActivity.refresh() }

        switch phase {
        case .recording:
            if SharedStorage.isCancelRequested() {
                SharedStorage.clearCancelRequest()
                cancel()
            } else if SharedStorage.isStopRequested() {
                SharedStorage.clearStopRequest()
                stop()
            } else if capture.isRunning {
                let level = Double(capture.level)

                // The keyboard draws its own waveform from this shared level.
                SharedStorage.setRecordingLevel(Float(level))
                if tick % 7 == 0 {
                    SharedStorage.touchRecordingHeartbeat()
                    if isArmed { SharedStorage.touchArmedHeartbeat() }
                }

                elapsed = capture.recordedSeconds
                appendLevel(level)
            } else {
                // The microphone stopped (for example on a phone call).
                stop()
            }

        case .idle:
            guard isArmed else {
                stopTimerIfIdle()
                return
            }
            guard capture.isRunning else {
                disarm(reason: "The microphone stopped, so it turned off.")
                return
            }

            appendLevel(Double(capture.level))
            if tick % 7 == 0 { SharedStorage.touchArmedHeartbeat() }

            // The keyboard asked for a dictation while we wait in the background.
            if SharedStorage.isRecordingRequested() {
                startCapturing(fromKeyboard: true)
                return
            }

            let idle = Date().timeIntervalSince(lastActivity)
            standbySecondsLeft = max(0, Int(Self.standbyTimeout - idle))
            if idle >= Self.standbyTimeout {
                disarm(reason: "The microphone turned off after \(Int(Self.standbyTimeout / 60)) minutes without use.")
            }

        case .transcribing:
            if isArmed, tick % 7 == 0 { SharedStorage.touchArmedHeartbeat() }
        }
    }

    private func appendLevel(_ level: Double) {
        levels.append(level)
        if levels.count > maxLevelSamples { levels.removeFirst(levels.count - maxLevelSamples) }
    }

    func cancel() {
        guard phase == .recording else { return }
        SharedStorage.setRecordingActive(false)
        SharedStorage.setRecordingLevel(0)
        capture.endRecording()
        if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
        phase = .idle
        levels = []
        startedFromKeyboard = false
        hint = "Dictation cancelled"
        lastActivity = Date()

        if isArmed {
            liveActivity.show(.standby)
        } else {
            liveActivity.end()
            shutDownMicrophone()
        }
    }

    func stop() {
        guard phase == .recording else { return }
        SharedStorage.setRecordingActive(false)
        SharedStorage.setRecordingLevel(0)

        // Keeps the app running while transcribing after the user stopped from another app.
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Transcribe") {
            DispatchQueue.main.async { MainActor.assumeIsolated { self.endBackgroundTask() } }
        }

        let duration = capture.recordedSeconds
        capture.endRecording()
        levels = []
        lastActivity = Date()

        if !isArmed {
            capture.stop()
            // The cue plays after the microphone is off, so it can't be captured, and it obeys the silent switch.
            if !startedFromKeyboard { CuePlayer.shared.play(.end, deactivateAfter: false) }
        }

        guard let url = recordingURL, duration > 0.5, FileManager.default.fileExists(atPath: url.path) else {
            phase = .idle
            hint = "That was too short. Try again."
            startedFromKeyboard = false
            if isArmed { liveActivity.show(.standby) } else { liveActivity.end() }
            finishSession()
            return
        }

        phase = .transcribing
        hint = "Just a moment"
        liveActivity.show(.transcribing)

        transcriptionGeneration += 1
        let generation = transcriptionGeneration
        startTranscribeWatchdog()
        transcriptionTask = Task { await transcribe(url, generation: generation) }
    }

    // MARK: Kill switch

    // Stops the model for this dictation only. WhisperKit checks for cancellation as it works, so it
    // halts within a step instead of running on in the background.
    func cancelTranscription() {
        guard phase == .transcribing else { return }
        transcriptionGeneration += 1
        transcriptionTask?.cancel()
        transcriptionTask = nil
        transcribeWatchdog?.invalidate()
        transcribeWatchdog = nil

        phase = .idle
        hint = "Transcription cancelled"
        startedFromKeyboard = false
        isPolishing = false
        lastActivity = Date()
        SharedStorage.setPolishing(false)
        TextCleaner.skip()
        if isArmed { liveActivity.show(.standby) } else { liveActivity.end() }
        finishSession()
    }

    // Lets the keyboard's kill switch reach us while we transcribe in the background.
    private func startTranscribeWatchdog() {
        transcribeWatchdog?.invalidate()
        transcribeWatchdog = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            MainActor.assumeIsolated {
                if SharedStorage.isCancelRequested() {
                    SharedStorage.clearCancelRequest()
                    self.cancelTranscription()
                } else if SharedStorage.isSkipPolishRequested() {
                    SharedStorage.clearSkipPolishRequest()
                    TextCleaner.skip()
                }
            }
        }
    }

    // MARK: Transcription

    private func transcribe(_ url: URL, generation: Int) async {
        defer {
            isPolishing = false
            SharedStorage.setPolishing(false)
            if generation == transcriptionGeneration {
                transcribeWatchdog?.invalidate()
                transcribeWatchdog = nil
                transcriptionTask = nil
                phase = .idle
                startedFromKeyboard = false
                lastActivity = Date()
                if isArmed { liveActivity.show(.standby) } else { liveActivity.end() }
                finishSession()
            }
        }

        do {
            if model.pipeline == nil {
                hint = "Preparing the model"
                await model.prepare()
            }
            guard generation == transcriptionGeneration else { return }
            guard let pipeline = model.pipeline else {
                hint = "The model isn't ready yet"
                return
            }

            hint = "Just a moment"
            // Optional smart cleanup: warm the on-device model while Whisper works. No-op when off or unavailable.
            if TextCleaner.isEnabled { TextCleaner.prewarm() }
            let transcribeStarted = Date()
            let results = try await pipeline.transcribe(audioPath: url.path)
            model.recordTranscriptionTime(Date().timeIntervalSince(transcribeStarted))
            // Cancelled while the model was still working: drop the result.
            guard generation == transcriptionGeneration, !Task.isCancelled else { return }

            let text = results.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty {
                hint = "Didn't catch any speech"
            } else {
                // Optional smart cleanup. Any problem returns the raw transcript, exactly as before.
                var finalText = text
                if TextCleaner.isEnabled {
                    hint = "Polishing"
                    isPolishing = true
                    SharedStorage.clearSkipPolishRequest()
                    SharedStorage.setPolishing(true)
                    finalText = await TextCleaner.clean(text)
                    isPolishing = false
                    SharedStorage.setPolishing(false)
                    guard generation == transcriptionGeneration, !Task.isCancelled else { return }
                }
                transcript = finalText
                hint = "Sent to the keyboard"
                SharedStorage.writeResult(finalText)
                SharedStorage.clearRecordingRequest()
            }
        } catch {
            guard generation == transcriptionGeneration else { return }
            hint = error is CancellationError ? "Transcription cancelled" : "Transcription failed: \(error.localizedDescription)"
        }
    }

    // MARK: Session

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // Called when a dictation is completely finished. The microphone session is kept while it is "ready".
    private func finishSession() {
        if !isArmed {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            stopTimerIfIdle()
        }
        endBackgroundTask()
    }
}
