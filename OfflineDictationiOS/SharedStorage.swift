import Foundation

struct SharedStorage {
    static let groupID = "group.com.divyanshu.OfflineDictation"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: groupID)
    }

    static func writeResult(_ text: String) {
        defaults?.set(text, forKey: "lastTranscription")
        defaults?.set(Date().timeIntervalSince1970, forKey: "lastTranscriptionTime")
    }

    static func readResult() -> String? {
        defaults?.string(forKey: "lastTranscription")
    }

    static func resultAge() -> TimeInterval? {
        guard let time = defaults?.double(forKey: "lastTranscriptionTime"), time > 0 else { return nil }
        return Date().timeIntervalSince1970 - time
    }

    static func clearResult() {
        defaults?.removeObject(forKey: "lastTranscription")
    }

    static func requestRecording() {
        defaults?.set(true, forKey: "recordingRequested")
    }

    static func isRecordingRequested() -> Bool {
        defaults?.bool(forKey: "recordingRequested") ?? false
    }

    static func clearRecordingRequest() {
        defaults?.set(false, forKey: "recordingRequested")
    }
}
