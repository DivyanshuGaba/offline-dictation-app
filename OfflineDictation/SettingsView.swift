import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("selectedModel") private var selectedModel = "small"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage(TextCleaner.settingsKey) private var cleanupEnabled = false
    @AppStorage(TextCleaner.timeoutKey) private var cleanupTimeout = 8.0
    @AppStorage(TextCleaner.cloudSettingsKey) private var cloudEnabled = false

    let models = ["tiny", "base", "small", "medium"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)

            Picker("Model", selection: $selectedModel) {
                ForEach(models, id: \.self) { model in
                    Text(model.capitalized).tag(model)
                }
            }
            .pickerStyle(.menu)

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    toggleLaunchAtLogin(newValue)
                }

            Text("Hotkey: double tap Option")
                .foregroundColor(.secondary)
                .font(.caption)

            Text("Changing the model takes effect on your next recording")
                .foregroundColor(.secondary)
                .font(.caption)

            Divider()

            cleanupSection
        }
        .padding()
        .frame(width: 340, height: 560)
    }

    // Optional on-device smart cleanup of the transcript (Apple Intelligence). Off by default.
    @ViewBuilder private var cleanupSection: some View {
        let status = TextCleaner.status

        Toggle("Clean up text with on-device AI", isOn: $cleanupEnabled)
            .disabled(status != .available)

        switch status {
        case .available:
            Text("Fixes punctuation, removes fillers, and keeps only what you meant when you correct yourself mid-sentence (\"Tuesday, no wait, Monday\"). Uses Apple Intelligence on this Mac and takes a few seconds. If it is slow or unavailable, your original text is used.")
                .foregroundColor(.secondary)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

            if cleanupEnabled {
                Picker("Longest wait", selection: $cleanupTimeout) {
                    Text("3 s").tag(3.0)
                    Text("5 s").tag(5.0)
                    Text("8 s").tag(8.0)
                    Text("12 s").tag(12.0)
                }
                .pickerStyle(.menu)

                if let run = TextCleaner.lastRun {
                    Text(run.summary)
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            let cloud = TextCleaner.cloudStatus
            Toggle("Advanced (cloud)", isOn: $cloudEnabled)
                .disabled(!(cleanupEnabled && cloud == .available))
            Text("Uses Apple's Private Cloud Compute for a stronger clean-up. Only your transcribed text is sent to Apple over the internet; your audio never leaves this Mac. If the cloud is offline, slow or over its limit, the on-device model is used instead.")
                .foregroundColor(.secondary)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            if case .unavailable(let reason) = cloud {
                Text(reason)
                    .foregroundColor(.orange)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .unavailable(let reason):
            Text("Not available: \(reason)")
                .foregroundColor(.secondary)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Could not update launch at login: \(error.localizedDescription)")
        }
    }
}

#Preview {
    SettingsView()
}
