import SwiftUI
import WhisperKit
import AVFoundation

struct ContentView: View {
    @State private var resultText = "Tap Record, speak, then tap Stop"
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var whisperPipe: WhisperKit?
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @AppStorage("selectedModel") private var selectedModel = "small"
    @State private var loadedModel: String?

    var body: some View {
        VStack(spacing: 20) {
            Text(resultText)
                .padding()
                .multilineTextAlignment(.center)

            Button(isRecording ? "Stop" : "Record") {
                isRecording ? stopRecording() : startRecording()
            }
            .disabled(isTranscribing)

            Button("Settings") {
                AppDelegate.shared?.openSettings()
            }
        }
        .padding()
        .frame(width: 400, height: 220)
        .onReceive(NotificationCenter.default.publisher(for: .toggleRecording)) { _ in
            isRecording ? stopRecording() : startRecording()
        }
    }

    func startRecording() {
        guard AVCaptureDevice.default(for: .audio) != nil else {
            resultText = "No microphone found. Connect one and try again."
            return
        }

        checkMicPermission { granted in
            if granted {
                beginRecording()
            } else {
                resultText = "Microphone access denied. Enable it in System Settings, Privacy and Security, Microphone."
            }
        }
    }

    func checkMicPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    func beginRecording() {
        AppDelegate.shared?.updateMenuBarIcon(recording: true)
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
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.record()
            isRecording = true
            resultText = "Recording..."
        } catch {
            resultText = "Could not start recording. Try again in a moment."
            AppDelegate.shared?.updateMenuBarIcon(recording: false)
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        AppDelegate.shared?.updateMenuBarIcon(recording: false)

        guard let url = recordingURL else {
            resultText = "Something went wrong, no recording was saved."
            return
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes?[.size] as? Int ?? 0
        if fileSize < 1000 {
            resultText = "Recording was too short or silent. Try speaking closer to the mic."
            return
        }

        isTranscribing = true
        resultText = "Transcribing..."
        transcribeRecording(url: url)
    }

    func transcribeRecording(url: URL) {
        Task {
            do {
                if whisperPipe == nil || loadedModel != selectedModel {
                    let config = WhisperKitConfig(model: selectedModel)
                    whisperPipe = try await WhisperKit(config)
                    loadedModel = selectedModel
                }
                let result = try await whisperPipe!.transcribe(audioPath: url.path)
                let text = result.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if text.isEmpty {
                    resultText = "Didn't catch any speech. Try again."
                } else {
                    resultText = text
                    TextInjector.paste(text)
                }
            } catch {
                resultText = "Transcription failed. Check your internet connection if this is the first run, since the model needs to download once."
            }
            isTranscribing = false
        }
    }
}

#Preview {
    ContentView()
}
