import SwiftUI
import WhisperKit
import AVFoundation

struct ContentView: View {
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
            startRecording()
        }
        .onAppear {
            requestMicPermission()
        }
    }

    func requestMicPermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if !granted {
                    statusText = "Microphone access denied. Enable it in iOS Settings."
                }
            }
        }
    }

    func startRecording() {
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
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.record()
            isRecording = true
            statusText = "Recording..."
        } catch {
            statusText = "Could not start recording"
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        isProcessing = true
        statusText = "Transcribing..."

        guard let url = recordingURL else {
            statusText = "No recording found"
            isProcessing = false
            return
        }

        Task {
            do {
                if whisperPipe == nil {
                    let config = WhisperKitConfig(model: "small")
                    whisperPipe = try await WhisperKit(config)
                }
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
                statusText = "Transcription failed"
            }
            isProcessing = false
        }
    }
}

#Preview {
    ContentView()
}
