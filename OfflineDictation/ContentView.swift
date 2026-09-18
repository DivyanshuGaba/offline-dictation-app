import SwiftUI
import WhisperKit
import AVFoundation

struct ContentView: View {
    @State private var resultText = "Tap Record, speak, then tap Stop"
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var isBenchmarking = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var whisperPipe: WhisperKit?

    var body: some View {
        VStack(spacing: 20) {
            Text(resultText)
                .padding()
            Button(isRecording ? "Stop" : "Record") {
                isRecording ? stopRecording() : startRecording()
            }
            .disabled(isTranscribing || isBenchmarking)

            Button("Run Benchmark") {
                runBenchmark()
            }
            .disabled(isRecording || isTranscribing || isBenchmarking)
        }
        .padding()
        .frame(width: 400, height: 220)
        .onReceive(NotificationCenter.default.publisher(for: .toggleRecording)) { _ in
            isRecording ? stopRecording() : startRecording()
        }
    }

    func startRecording() {
        checkMicPermission { granted in
            if granted {
                beginRecording()
            } else {
                resultText = "Microphone access denied. Enable it in System Settings."
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
        (NSApp.delegate as? AppDelegate)?.updateMenuBarIcon(recording: true)
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
            resultText = "Could not start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        (NSApp.delegate as? AppDelegate)?.updateMenuBarIcon(recording: false)
        isTranscribing = true
        resultText = "Transcribing..."
        transcribeRecording()
    }

    func transcribeRecording() {
        guard let url = recordingURL else {
            resultText = "No recording found"
            isTranscribing = false
            return
        }
        Task {
            do {
                if whisperPipe == nil {
                    let config = WhisperKitConfig(model: "small")
                    whisperPipe = try await WhisperKit(config)
                }
                let result = try await whisperPipe!.transcribe(audioPath: url.path)
                let text = result.first?.text ?? ""
                resultText = text.isEmpty ? "No text returned" : text
                if !text.isEmpty {
                    TextInjector.paste(text)
                }
            } catch {
                resultText = "Error: \(error.localizedDescription)"
            }
            isTranscribing = false
        }
    }

    func runBenchmark() {
        guard let path = Bundle.main.path(forResource: "sample", ofType: "wav") else {
            resultText = "Sample file not found"
            return
        }
        isBenchmarking = true
        resultText = "Running benchmark, check the console"
        Task {
            let models = ["tiny", "base", "small"]
            for modelName in models {
                let start = Date()
                do {
                    let config = WhisperKitConfig(model: modelName)
                    let pipe = try await WhisperKit(config)
                    let result = try await pipe.transcribe(audioPath: path)
                    let elapsed = Date().timeIntervalSince(start)
                    let text = result.first?.text ?? "No text"
                    print("Model \(modelName) took \(elapsed) seconds, result is \(text)")
                } catch {
                    print("Model \(modelName) failed with error \(error.localizedDescription)")
                }
            }
            resultText = "Benchmark finished, check the console"
            isBenchmarking = false
        }
    }
}

#Preview {
    ContentView()
}

