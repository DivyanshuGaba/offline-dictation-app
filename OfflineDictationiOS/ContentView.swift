import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var engine = DictationEngine()
    @State private var hintDismissed = false
    @AppStorage(TextCleaner.settingsKey) private var cleanupEnabled = false
    // Checked when the screen appears and when returning to the app, not on every redraw.
    @State private var cleanupStatus: TextCleaner.Status = .unavailable("")
    @State private var cloudStatus: TextCleaner.Status = .unavailable("")
    @AppStorage(TextCleaner.cloudSettingsKey) private var cloudEnabled = false
    @State private var showCloudConfirm = false
    @State private var modelToDelete: WhisperModelInfo?

    var body: some View {
        HomeView(
            state: homeState,
            onMicTap: { engine.toggle() },
            onCopy: { UIPasteboard.general.string = engine.transcript },
            onRetryModel: { Task { await engine.model.prepare() } },
            onOpenSettings: {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            },
            onDismissHint: { hintDismissed = true },
            onCancelTranscription: { engine.cancelTranscription() },
            onToggleCleanup: { cleanupEnabled = $0 },
            onSkipCleanup: { TextCleaner.skip() },
            onToggleCloud: { on in
                // Turning it on needs a clear yes, because text leaves the device.
                if on { showCloudConfirm = true } else { cloudEnabled = false }
            },
            onSelectModel: { engine.model.select($0) },
            onDownloadModel: { id in Task { await engine.model.download(id) } },
            onDeleteModel: { modelToDelete = ModelCatalog.info($0) },
            onTurnOffMic: { engine.turnOffMic() }
        )
        .alert("Use Apple's cloud?", isPresented: $showCloudConfirm) {
            Button("Turn on") { cloudEnabled = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your transcribed text, not your audio, will be sent to Apple's Private Cloud Compute over the internet to be cleaned up. If it can't be reached, Smart cleanup uses the on-device model instead.")
        }
        .alert("Delete \(modelToDelete?.name ?? "model")?", isPresented: Binding(get: { modelToDelete != nil }, set: { if !$0 { modelToDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let model = modelToDelete { engine.model.delete(model.id) }
                modelToDelete = nil
            }
            Button("Cancel", role: .cancel) { modelToDelete = nil }
        } message: {
            Text("This removes the model from your iPhone and frees \(modelToDelete.map { "about \($0.sizeMB) MB" } ?? "space"). You can download it again any time.")
        }
        .onChange(of: engine.phase) { _, phase in
            if phase == .recording { hintDismissed = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .startDictationFromKeyboard)) { _ in
            engine.startIfRequested()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                cleanupStatus = TextCleaner.status
                cloudStatus = TextCleaner.cloudStatus
                engine.startIfRequested()
            }
        }
        .onAppear {
            cleanupStatus = TextCleaner.status
            cloudStatus = TextCleaner.cloudStatus
        }
        .task {
            // Clear anything a previous, killed run left behind, then start a requested recording straight
            // away; the model loads alongside it.
            engine.tidyOnLaunch()
            engine.startIfRequested()
            await engine.model.prepare()
        }
    }

    private var homeState: HomeState {
        var state = HomeState()

        switch engine.phase {
        case .idle: state.phase = .idle
        case .recording: state.phase = .recording
        case .transcribing: state.phase = .transcribing
        }
        state.hint = idleHint
        state.elapsed = engine.elapsed
        state.levels = engine.levels
        state.transcript = engine.transcript
        state.micDenied = engine.micDenied
        state.showSwipeHint = engine.phase == .recording && engine.startedFromKeyboard && !hintDismissed
        state.isArmed = engine.isArmed

        switch cleanupStatus {
        case .available:
            state.cleanupAvailable = true
            let wait = String(format: "%g", TextCleaner.timeout)
            state.cleanupNote = TextCleaner.lastRun?.summary ?? "Waits up to \(wait) s, then uses your original text. No runs yet."
        case .unavailable(let reason):
            state.cleanupAvailable = false
            state.cleanupNote = "Not available: " + reason
        }
        state.cleanupEnabled = cleanupEnabled
        state.isPolishing = engine.isPolishing

        switch cloudStatus {
        case .available: state.cloudAvailable = true
        case .unavailable(let reason):
            state.cloudAvailable = false
            state.cloudNote = reason
        }
        state.cloudEnabled = cloudEnabled

        let model = engine.model
        switch model.status {
        case .notDownloaded: state.modelStatus = .notDownloaded
        case .downloading: state.modelStatus = .downloading
        case .preparing: state.modelStatus = .preparing
        case .ready: state.modelStatus = .ready
        case .failed(let message): state.modelStatus = .failed(message)
        }
        state.modelName = model.displayName
        state.modelIdentifier = model.folderName
        state.modelParameters = model.parameters
        state.bytesOnDisk = model.bytesOnDisk
        state.expectedBytes = model.expectedBytes
        state.downloadProgress = model.downloadProgress
        state.prepareElapsed = model.prepareElapsed
        state.prepareEstimate = model.prepareEstimate
        state.prepareProgress = model.prepareProgress

        state.models = modelRows
        state.modelActionsEnabled = engine.phase == .idle && model.status != .preparing && model.downloadingID == nil
        return state
    }

    // One row per model the device can run, with its live state.
    private var modelRows: [ModelRowState] {
        let manager = engine.model
        let deviceDefault = ModelCatalog.deviceDefaultID

        return ModelCatalog.visible(alwaysInclude: [manager.selectedID]).map { info in
            let downloaded = manager.downloadedIDs.contains(info.id)
            let isSelected = info.id == manager.selectedID

            let status: ModelRowState.Status
            if manager.downloadingID == info.id {
                status = .downloading(manager.downloadProgress)
            } else if isSelected && (downloaded || manager.status != .notDownloaded) {
                switch manager.status {
                case .ready: status = .inUse(.ready)
                case .failed(let message): status = .inUse(.failed(message))
                case .downloading: status = .inUse(.downloading)
                default: status = .inUse(.preparing)
                }
            } else if downloaded {
                status = .downloaded
            } else {
                status = .notDownloaded
            }

            var badges: [String] = []
            if let badge = info.badge { badges.append(badge.rawValue) }
            if info.id == deviceDefault { badges.append("Device default") }

            var meta = "\(info.sizeMB) MB · \(info.parameters) parameters"
            if downloaded, let onDisk = manager.sizesOnDisk[info.id], onDisk > 0 {
                meta = "\(ByteFormat.string(onDisk)) on this iPhone · \(info.parameters) parameters"
            }
            if info.englishOnly { meta += " · English only" }

            return ModelRowState(
                id: info.id,
                name: info.name,
                summary: info.summary,
                bestFor: info.bestFor,
                badges: badges,
                meta: meta,
                downloadSizeText: "\(info.sizeMB) MB",
                status: status,
                lastTime: manager.lastTranscribeSeconds[info.id].map { String(format: "Last dictation took %.1f s", $0) },
                canDelete: downloaded && !isSelected && manager.downloadingID == nil,
                error: manager.downloadErrors[info.id]
            )
        }
    }

    // While the model is still getting ready, say so under the mic instead of the generic hint.
    private var idleHint: String {
        guard engine.phase == .idle, !engine.micDenied else { return engine.hint }
        if engine.isArmed {
            let minutes = max(1, Int((Double(engine.standbySecondsLeft) / 60).rounded(.up)))
            return "Tap the mic on your keyboard to dictate. It turns off after \(minutes) min without use."
        }
        switch engine.model.status {
        case .downloading: return "Downloading the speech model"
        case .preparing: return "Getting the model ready. You can still record."
        default: return engine.hint
        }
    }
}

#Preview {
    ContentView()
}
