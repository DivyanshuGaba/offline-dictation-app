import ActivityKit
import Foundation

// Shared by the app (which starts the Live Activity) and the DictationLiveActivity extension (which draws it).
struct DictationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case standby        // microphone ready in the background, not recording
            case recording
            case transcribing
        }

        var startedAt: Date
        var phase: Phase
    }
}
