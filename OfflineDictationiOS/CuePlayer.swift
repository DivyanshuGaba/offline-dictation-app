import AVFoundation

// Plays the start and end cues. Uses the ambient audio category, which is muted by the ringer
// switch and otherwise follows the media volume. Shared by the app and the keyboard.
@MainActor
final class CuePlayer {
    enum Cue { case start, end }

    static let shared = CuePlayer()

    private var players: [Cue: AVAudioPlayer] = [:]

    // deactivateAfter: true for the keyboard, which owns no other audio. The app passes false because it
    // reuses the session for recording.
    func play(_ cue: Cue, deactivateAfter: Bool) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        guard let player = players[cue] ?? makePlayer(for: cue) else { return }
        players[cue] = player
        player.currentTime = 0
        player.play()

        if deactivateAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + player.duration + 0.25) {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }

    private func makePlayer(for cue: Cue) -> AVAudioPlayer? {
        let kind: CueTones.Kind
        switch cue {
        case .start: kind = .start
        case .end: kind = .end
        }
        guard let player = try? AVAudioPlayer(data: CueTones.wav(for: kind)) else { return nil }
        player.volume = 1
        player.prepareToPlay()
        return player
    }
}
