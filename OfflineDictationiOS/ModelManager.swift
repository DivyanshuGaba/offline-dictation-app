import Foundation
import CoreML
import Observation
import WhisperKit

// Owns the Whisper model: whether it's on disk, how big it is, downloading it, and loading it.
@MainActor @Observable
final class ModelManager {
    enum Status: Equatable {
        case notDownloaded
        case downloading
        case preparing
        case ready
        case failed(String)
    }

    static let selectionKey = "selectedWhisperModel"
    static let defaultModelID = "openai_whisper-small"
    private static let lastSecondsKey = "whisperLastTranscribeSeconds"

    // The model used for dictation. Changing it loads the new model; the old one stays on disk.
    private(set) var selectedID: String

    var displayName: String { "Whisper " + (ModelCatalog.info(selectedID)?.name ?? selectedID) }
    var folderName: String { selectedID }
    var parameters: String { ModelCatalog.info(selectedID)?.parameters ?? "" }

    private(set) var status: Status = .notDownloaded
    private(set) var downloadProgress: Double = 0
    // Which model is downloading right now (only one at a time).
    private(set) var downloadingID: String?
    private(set) var downloadErrors: [String: String] = [:]
    private(set) var downloadedIDs: Set<String> = []
    private(set) var sizesOnDisk: [String: Int64] = [:]
    private(set) var lastTranscribeSeconds: [String: Double] = [:]
    private(set) var bytesOnDisk: Int64 = 0
    private(set) var expectedBytes: Int64?
    private(set) var pipeline: WhisperKit?

    // Core ML gives no progress for the on-device optimisation step, so this is an estimate
    // based on how long the last real optimisation took.
    private(set) var prepareElapsed: TimeInterval = 0
    private(set) var prepareEstimate: TimeInterval = 180
    private(set) var prepareProgress: Double = 0

    @ObservationIgnored private var prepareTask: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var prepareStartedAt: Date?

    // Each model takes its own time to optimise, so the estimate is remembered per model.
    private var prepareSecondsKey: String { "modelPrepareSeconds.\(selectedID)" }

    // MARK: Locations (WhisperKit's default download base is Documents/huggingface)

    private var base: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("huggingface", isDirectory: true)
    }

    private var modelsRoot: URL {
        base.appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
    }

    private func folder(for id: String) -> URL { modelsRoot.appendingPathComponent(id, isDirectory: true) }
    private func cacheFolder(for id: String) -> URL {
        modelsRoot.appendingPathComponent(".cache/huggingface/download/\(id)", isDirectory: true)
    }
    private var modelFolder: URL { folder(for: selectedID) }

    // A model counts as downloaded only if its parts are all there and no download was left half finished.
    private func isDownloaded(_ id: String) -> Bool {
        let fileManager = FileManager.default
        let root = folder(for: id)
        guard fileManager.fileExists(atPath: root.appendingPathComponent("config.json").path) else { return false }

        for component in ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"] {
            let directory = root.appendingPathComponent(component, isDirectory: true)
            guard fileManager.fileExists(atPath: directory.appendingPathComponent("coremldata.bin").path) else { return false }
            let weights = directory.appendingPathComponent("weights", isDirectory: true)
            if fileManager.fileExists(atPath: weights.path),
               !fileManager.fileExists(atPath: weights.appendingPathComponent("weight.bin").path) { return false }
        }

        if let files = fileManager.enumerator(at: cacheFolder(for: id), includingPropertiesForKeys: nil) {
            for case let url as URL in files where url.lastPathComponent.hasSuffix(".incomplete") { return false }
        }
        return true
    }

    // MARK: Lifecycle

    init() {
        selectedID = UserDefaults.standard.string(forKey: Self.selectionKey) ?? Self.defaultModelID
        lastTranscribeSeconds = (UserDefaults.standard.dictionary(forKey: Self.lastSecondsKey) as? [String: Double]) ?? [:]
        refreshInventory()
        refreshFromDisk()
    }

    func refreshFromDisk() {
        guard status != .downloading, status != .preparing, status != .ready else { return }
        status = isDownloaded(selectedID) ? .preparing : .notDownloaded
        updateSize()
    }

    // Which models are on disk and how much space each takes.
    func refreshInventory() {
        let found = Set(ModelCatalog.all.map(\.id).filter { isDownloaded($0) })
        downloadedIDs = found

        let root = modelsRoot
        Task.detached(priority: .utility) {
            var sizes: [String: Int64] = [:]
            for id in found { sizes[id] = Self.directorySize(root.appendingPathComponent(id, isDirectory: true)) }
            await MainActor.run { [sizes] in
                self.sizesOnDisk = sizes
            }
        }
    }

    // MARK: Choosing, downloading and deleting models

    // Switches dictation to a model that is already downloaded.
    func select(_ id: String) {
        guard id != selectedID, downloadedIDs.contains(id), downloadingID == nil, status != .preparing else { return }
        selectedID = id
        UserDefaults.standard.set(id, forKey: Self.selectionKey)
        pipeline = nil
        prepareElapsed = 0
        prepareProgress = 0
        status = .preparing
        updateSize()
        Task { await prepare() }
    }

    // Downloads a model without switching to it.
    func download(_ id: String) async {
        guard downloadingID == nil, !downloadedIDs.contains(id) else { return }
        do {
            try await downloadFiles(id)
        } catch {
            downloadErrors[id] = error.localizedDescription
        }
    }

    private func downloadFiles(_ id: String) async throws {
        downloadingID = id
        downloadProgress = 0
        downloadErrors[id] = nil
        defer { downloadingID = nil }

        _ = try await WhisperKit.download(variant: id) { [weak self] progress in
            let fraction = progress.fractionCompleted
            Task { @MainActor in self?.downloadProgress = fraction }
        }
        refreshInventory()
    }

    // Removes a downloaded model from this device. The model in use can't be deleted.
    func delete(_ id: String) {
        guard id != selectedID, downloadingID != id else { return }
        try? FileManager.default.removeItem(at: folder(for: id))
        try? FileManager.default.removeItem(at: cacheFolder(for: id))
        downloadErrors[id] = nil
        refreshInventory()
    }

    // Remembers how long the last transcription took with the model in use.
    func recordTranscriptionTime(_ seconds: TimeInterval) {
        lastTranscribeSeconds[selectedID] = seconds
        UserDefaults.standard.set(lastTranscribeSeconds, forKey: Self.lastSecondsKey)
    }

    // Downloads the model if needed, then loads it. Safe to call repeatedly; callers share one run.
    func prepare() async {
        if let task = prepareTask {
            await task.value
            return
        }
        guard pipeline == nil else { return }

        let task = Task { await self.runPrepare() }
        prepareTask = task
        await task.value
        prepareTask = nil
    }

    private func runPrepare() async {
        startTicker()
        defer { stopTicker() }

        do {
            if !isDownloaded(selectedID) {
                status = .downloading
                expectedBytes = nil
                try await downloadFiles(selectedID)
            }

            let saved = UserDefaults.standard.double(forKey: prepareSecondsKey)
            prepareEstimate = saved > 0 ? saved : 180
            prepareElapsed = 0
            prepareProgress = 0
            prepareStartedAt = Date()
            status = .preparing
            updateSize()

            // iOS denies GPU work from the background, so keep the mel step off the GPU.
            let compute = ModelComputeOptions(melCompute: .cpuOnly)
            let config = WhisperKitConfig(model: selectedID, modelFolder: modelFolder.path, computeOptions: compute, download: false)
            pipeline = try await WhisperKit(config)

            // Remember real optimisations (not quick cache hits) to make the next estimate accurate.
            if let started = prepareStartedAt {
                let took = Date().timeIntervalSince(started)
                if took > 20 { UserDefaults.standard.set(min(600, took), forKey: prepareSecondsKey) }
            }
            prepareProgress = 1
            status = .ready
            downloadProgress = 1
            refreshInventory()
            updateSize()
        } catch {
            status = .failed(error.localizedDescription)
            updateSize()
        }
    }

    // MARK: Size

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    private func tick() {
        switch status {
        case .downloading:
            updateSize()
        case .preparing:
            if let started = prepareStartedAt {
                prepareElapsed = Date().timeIntervalSince(started)
                // Never claim completion before it's actually done.
                prepareProgress = min(0.95, prepareElapsed / max(prepareEstimate, 1))
            }
        default:
            break
        }
    }

    private func updateSize() {
        let files = modelFolder
        let partial = cacheFolder(for: selectedID)
        let downloading = status == .downloading

        Task.detached(priority: .utility) {
            let total = Self.directorySize(files) + Self.directorySize(partial)
            await MainActor.run { [total] in
                self.applySize(total, downloading: downloading)
            }
        }
    }

    private func applySize(_ bytes: Int64, downloading: Bool) {
        bytesOnDisk = bytes
        // Project the final size from how far along the download is.
        if downloading, downloadProgress > 0.05 {
            expectedBytes = Int64(Double(bytes) / downloadProgress)
        }
    }

    nonisolated private static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
