import SwiftUI
import WhisperKit
import AVFoundation

struct ContentView: View {
    @State private var resultText = "Tap Record, speak, then tap Stop"
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?

    var body: some View {
        VStack(spacing: 20) {
            Text(resultText)
                .padding()
            Button(isRecording ? "Stop" : "Record") {
                isRecording ? stopRecording() : startRecording()
            }
            .disabled(isTranscribing)
        }
        .padding()
        .frame(width: 400, height: 200)
    }

    func startRecording() {
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
                let config = WhisperKitConfig(model: "small")
                let pipe = try await WhisperKit(config)
                let result = try await pipe.transcribe(audioPath: url.path)
                resultText = result.first?.text ?? "No text returned"
            } catch {
                resultText = "Error: \(error.localizedDescription)"
            }
            isTranscribing = false
        }
    }
}

#Preview {
    ContentView()
}
