import SwiftUI
import WhisperKit

struct ContentView: View {
    @State private var resultText = "Tap the button to transcribe"
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 20) {
            Text(resultText)
                .padding()
            Button(isLoading ? "Transcribing..." : "Transcribe Sample") {
                transcribeSample()
            }
            .disabled(isLoading)
        }
        .padding()
        .frame(width: 400, height: 200)
    }

    func transcribeSample() {
        isLoading = true
        Task {
            guard let path = Bundle.main.path(forResource: "sample", ofType: "wav") else {
                resultText = "Sample file not found"
                isLoading = false
                return
            }
            do {
                print("Starting WhisperKit setup")
                let config = WhisperKitConfig(model: "small")
                let pipe = try await WhisperKit(config)
                print("WhisperKit setup finished")
                let result = try await pipe.transcribe(audioPath: path)
                resultText = result.first?.text ?? "No text returned"
            } catch {
                resultText = "Error: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}

#Preview {
    ContentView()
}
