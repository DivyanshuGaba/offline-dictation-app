import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("selectedModel") private var selectedModel = "small"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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
        }
        .padding()
        .frame(width: 320, height: 220)
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
