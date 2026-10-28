import Foundation
import WhisperKit

// A Whisper model the user can choose. `id` is the WhisperKit model folder name.
struct WhisperModelInfo: Identifiable, Equatable {
    enum Badge: String {
        case fastest = "Fastest"
        case balanced = "Balanced"
        case bestQuality = "Best quality"
        case mostAccurate = "Most accurate"
    }

    let id: String
    let name: String
    let sizeMB: Int
    let parameters: String
    let summary: String
    let bestFor: String
    let englishOnly: Bool
    let badge: Badge?
}

enum ModelCatalog {
    // Download sizes are the real folder sizes in WhisperKit's model repository.
    static let all: [WhisperModelInfo] = [
        WhisperModelInfo(
            id: "openai_whisper-tiny", name: "Tiny", sizeMB: 77, parameters: "39M",
            summary: "The smallest and fastest. Fine for short, clear phrases; it slips more on accents, names and noise.",
            bestFor: "Quick notes in a quiet room", englishOnly: false, badge: .fastest),
        WhisperModelInfo(
            id: "openai_whisper-base", name: "Base", sizeMB: 147, parameters: "74M",
            summary: "Still fast, with clearly better accuracy than Tiny. WhisperKit's default choice for phones like yours.",
            bestFor: "Everyday messages when speed matters", englishOnly: false, badge: nil),
        WhisperModelInfo(
            id: "openai_whisper-base.en", name: "Base (English)", sizeMB: 147, parameters: "74M",
            summary: "Base, trained for English only, which makes it a little more accurate for English speech.",
            bestFor: "English-only dictation, fast", englishOnly: true, badge: nil),
        WhisperModelInfo(
            id: "openai_whisper-small", name: "Small", sizeMB: 486, parameters: "244M",
            summary: "The balanced choice: good accuracy on everyday speech and accents, and still quick.",
            bestFor: "General use in 99 languages", englishOnly: false, badge: .balanced),
        WhisperModelInfo(
            id: "openai_whisper-small.en", name: "Small (English)", sizeMB: 487, parameters: "244M",
            summary: "Small, for English only, with slightly better English accuracy.",
            bestFor: "English dictation with good accuracy", englishOnly: true, badge: nil),
        WhisperModelInfo(
            id: "distil-whisper_distil-large-v3_594MB", name: "Distil-Large-v3", sizeMB: 595, parameters: "756M",
            summary: "A slimmed-down Large model for English. Near-Large accuracy at a much lower cost in time.",
            bestFor: "Long English dictation", englishOnly: true, badge: nil),
        WhisperModelInfo(
            id: "openai_whisper-large-v3-v20240930_turbo_632MB", name: "Large-v3 Turbo", sizeMB: 646, parameters: "809M",
            summary: "Close to Large accuracy in 99 languages, but much faster and lighter. The best all-round quality that fits your phone.",
            bestFor: "The best results without the wait of full Large", englishOnly: false, badge: .bestQuality),
        WhisperModelInfo(
            id: "openai_whisper-large-v3_947MB", name: "Large-v3", sizeMB: 948, parameters: "1.5B",
            summary: "The most accurate: strongest with accents, noise and many languages. It is also the slowest and heaviest on battery and memory.",
            bestFor: "Hard audio where accuracy matters most", englishOnly: false, badge: .mostAccurate),
    ]

    static func info(_ id: String) -> WhisperModelInfo? {
        all.first { $0.id == id }
    }

    // WhisperKit's built-in list of what this device can run. Works offline.
    static var deviceDefaultID: String { WhisperKit.recommendedModels().default }

    static func visible(alwaysInclude keep: [String]) -> [WhisperModelInfo] {
        let supported = Set(WhisperKit.recommendedModels().supported)
        return all.filter { supported.contains($0.id) || keep.contains($0.id) }
    }
}
