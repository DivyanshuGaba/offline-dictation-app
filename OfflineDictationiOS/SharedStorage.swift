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

    static func clearResult() {
        defaults?.removeObject(forKey: "lastTranscription")
    }

    static func resultAge() -> TimeInterval? {
        guard let time = defaults?.double(forKey: "lastTranscriptionTime"), time > 0 else { return nil }
        return Date().timeIntervalSince1970 - time
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

    static func requestStop() {
        defaults?.set(true, forKey: "stopRequested")
    }

    static func isStopRequested() -> Bool {
        defaults?.bool(forKey: "stopRequested") ?? false
    }

    static func clearStopRequest() {
        defaults?.set(false, forKey: "stopRequested")
    }

    static func setRecordingActive(_ active: Bool) {
        defaults?.set(active, forKey: "recordingActive")
        if active {
            defaults?.set(Date().timeIntervalSince1970, forKey: "recordingStartedAt")
            touchRecordingHeartbeat()
        }
    }

    static func touchRecordingHeartbeat() {
        defaults?.set(Date().timeIntervalSince1970, forKey: "recordingHeartbeat")
    }

    // The host refreshes the heartbeat while it records; a stale one means the app was killed.
    static func isRecordingActive() -> Bool {
        guard defaults?.bool(forKey: "recordingActive") == true,
              let beat = defaults?.double(forKey: "recordingHeartbeat"), beat > 0 else { return false }
        return Date().timeIntervalSince1970 - beat < 3
    }

    static func requestCancel() {
        defaults?.set(true, forKey: "cancelRequested")
    }

    static func isCancelRequested() -> Bool {
        defaults?.bool(forKey: "cancelRequested") ?? false
    }

    static func clearCancelRequest() {
        defaults?.set(false, forKey: "cancelRequested")
    }

    static func setRecordingLevel(_ level: Float) {
        defaults?.set(level, forKey: "recordingLevel")
    }

    static func recordingLevel() -> Float {
        defaults?.float(forKey: "recordingLevel") ?? 0
    }

    static func setInputName(_ name: String) {
        defaults?.set(name, forKey: "inputName")
    }

    static func inputName() -> String? {
        defaults?.string(forKey: "inputName")
    }

    static func recordingStartedAt() -> Date? {
        guard let time = defaults?.double(forKey: "recordingStartedAt"), time > 0 else { return nil }
        return Date(timeIntervalSince1970: time)
    }

    // Set while the app is cleaning up a transcript, so the keyboard can offer to skip it.
    static func setPolishing(_ polishing: Bool) {
        defaults?.set(polishing, forKey: "polishing")
        if polishing { defaults?.set(Date().timeIntervalSince1970, forKey: "polishingSince") }
    }

    static func isPolishing() -> Bool {
        guard defaults?.bool(forKey: "polishing") == true,
              let since = defaults?.double(forKey: "polishingSince"), since > 0 else { return false }
        return Date().timeIntervalSince1970 - since < 30
    }

    static func requestSkipPolish() {
        defaults?.set(true, forKey: "skipPolishRequested")
    }

    static func isSkipPolishRequested() -> Bool {
        defaults?.bool(forKey: "skipPolishRequested") ?? false
    }

    static func clearSkipPolishRequest() {
        defaults?.set(false, forKey: "skipPolishRequested")
    }

    // The app is keeping the microphone ready in the background, so the keyboard can start a dictation
    // without opening the app. The heartbeat makes a crashed or killed app stop counting as ready.
    static func setArmed(_ armed: Bool) {
        defaults?.set(armed, forKey: "micArmed")
        if armed { touchArmedHeartbeat() }
    }

    static func touchArmedHeartbeat() {
        defaults?.set(Date().timeIntervalSince1970, forKey: "micArmedHeartbeat")
    }

    static func isArmed() -> Bool {
        guard defaults?.bool(forKey: "micArmed") == true,
              let beat = defaults?.double(forKey: "micArmedHeartbeat"), beat > 0 else { return false }
        return Date().timeIntervalSince1970 - beat < 3
    }
}
