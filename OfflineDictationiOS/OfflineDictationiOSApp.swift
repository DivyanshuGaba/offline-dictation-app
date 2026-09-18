import SwiftUI

@main
struct OfflineDictationiOSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    if url.scheme == "offlinedictation" && url.host == "record" {
                        NotificationCenter.default.post(name: .startDictationFromKeyboard, object: nil)
                    }
                }
        }
    }
}

extension Notification.Name {
    static let startDictationFromKeyboard = Notification.Name("startDictationFromKeyboard")
}
