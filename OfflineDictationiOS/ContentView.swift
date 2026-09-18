import SwiftUI
import WhisperKit
import AVFoundation

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var statusText = "Ready"
    @State private var isRecording = false
    @State private var isProcessing = false
    @State private var whisperPipe: WhisperKit?
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?

    var body: some View {
        VStack(spacing: 20) {
            Text(statusText)
                .padding()
                .multilineTextAlignment(.center)

            Button(isRecording ? "Stop" : "Record") {
                isRecording ? stopRecording() : startRecording()
            }
            .disabled(isProcessing)
            .padding()
            .background(isRecording ? Color.red : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .padding()
        .onReceive(NotificationCenter.default.publisher(for: .startDictationFromKeyboard)) { _ in
            startRecordingIfRequested()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { startRecordingIfRequested() }
        }
        .task {
            await loadModelIfNeeded()
            startRecordingIfRequested()
        }
    }

    func startRecordingIfRequested() {
        guard SharedStorage.isRecordingRequested(), !isRecording, !isProcessing else { return }
        startRecording()
    }

    func loadModelIfNeeded() async {
        guard whisperPipe == nil else { return }
        if !isRecording && !isProcessing { statusText = "Loading model..." }
        do {
            whisperPipe = try await WhisperKit(WhisperKitConfig(model: "small"))
            if !isRecording && !isProcessing { statusText = "Ready" }
        } catch {
            statusText = "Model failed to load: \(error.localizedDescription)"
        }
    }

    func startRecording() {
        guard !isRecording else { return }

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            beginRecording()
        case .undetermined:
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted { beginRecording() } else { statusText = "Microphone access denied. Enable it in iOS Settings." }
                }
            }
        default:
            statusText = "Microphone access denied. Enable it in iOS Settings."
        }
    }

    func beginRecording() {
        guard !isRecording else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
        } catch {
            statusText = "Could not access microphone session"
            return
        }

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("liveRecording.wav")
        recordingURL = fileURL

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false
        ]

        do {
            try? FileManager.default.removeItem(at: fileURL)
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            guard audioRecorder?.record() == true else {
                statusText = "Could not start recording"
                return
            }
            SharedStorage.clearRecordingRequest()
            isRecording = true
            statusText = "Recording... tap Stop when done"
        } catch {
            statusText = "Could not start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        let duration = audioRecorder?.currentTime ?? 0
        audioRecorder?.stop()
        isRecording = false

        guard let url = recordingURL, duration > 0.5,
              FileManager.default.fileExists(atPath: url.path) else {
            statusText = "Recording too short. Tap Record and try again."
            return
        }

        isProcessing = true
        statusText = "Transcribing..."

        Task {
            do {
                if whisperPipe == nil {
                    statusText = "Loading model (first time takes a few minutes)..."
                    await loadModelIfNeeded()
                    statusText = "Transcribing..."
                }
                guard whisperPipe != nil else { isProcessing = false; return }
                let result = try await whisperPipe!.transcribe(audioPath: url.path)
                let text = result.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if text.isEmpty {
                    statusText = "Didn't catch any speech"
                } else {
                    statusText = "Done: \(text)"
                    SharedStorage.writeResult(text)
                    SharedStorage.clearRecordingRequest()
                }
            } catch {
                statusText = "Transcription failed: \(error.localizedDescription)"
            }
            isProcessing = false
        }
    }
}

#Preview {
    ContentView()
}
