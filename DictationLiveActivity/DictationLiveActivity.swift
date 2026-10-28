import ActivityKit
import SwiftUI
import WidgetKit

private enum Tone {
    static let silver = Color(red: 0.86, green: 0.87, blue: 0.91)
    static let recording = Color(red: 0.90, green: 0.36, blue: 0.34)
    static let ready = Color(red: 0.20, green: 0.83, blue: 0.60)
}

// What the activity looks like. "off" is shown when the app stopped refreshing it, meaning it was closed.
private enum Look {
    case standby, recording, transcribing, off

    init(_ state: DictationActivityAttributes.ContentState, isStale: Bool) {
        if isStale {
            self = .off
            return
        }
        switch state.phase {
        case .standby: self = .standby
        case .recording: self = .recording
        case .transcribing: self = .transcribing
        }
    }

    var symbol: String {
        switch self {
        case .standby, .recording: "mic.fill"
        case .transcribing: "waveform"
        case .off: "mic.slash.fill"
        }
    }

    var tint: Color {
        switch self {
        case .standby: Tone.ready
        case .recording: Tone.recording
        case .transcribing, .off: Tone.silver
        }
    }

    var title: String {
        switch self {
        case .standby: "Mic ready"
        case .recording: "Listening"
        case .transcribing: "Transcribing"
        case .off: "Mic off"
        }
    }

    var detail: String {
        switch self {
        case .standby: "Tap the mic on your keyboard to dictate"
        case .recording: "Tap the mic in the keyboard to finish"
        case .transcribing: "Turning your speech into text"
        case .off: "The app was closed. Open it to turn the mic on again."
        }
    }
}

struct DictationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictationActivityAttributes.self) { context in
            LockScreenView(state: context.state, look: Look(context.state, isStale: context.isStale))
                .activityBackgroundTint(Color(red: 0.07, green: 0.07, blue: 0.08))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let look = Look(context.state, isStale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StatusBadge(look: look)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Marker(state: context.state, look: look, size: 26)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(look.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: look.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(look.tint)
                    .padding(.leading, 4)
            } compactTrailing: {
                Marker(state: context.state, look: look, size: 14)
                    .frame(width: 46, alignment: .trailing)
            } minimal: {
                Image(systemName: look.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(look.tint)
            }
            .keylineTint(look.tint)
        }
    }
}

// A stopwatch while recording; a quiet marker the rest of the time.
private struct Marker: View {
    let state: DictationActivityAttributes.ContentState
    let look: Look
    let size: CGFloat

    var body: some View {
        switch look {
        case .recording:
            Text(state.startedAt, style: .timer)
                .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        case .transcribing:
            Image(systemName: "ellipsis")
                .font(.system(size: size * 0.9, weight: .bold))
                .foregroundStyle(Tone.silver)
        case .standby:
            Circle()
                .fill(Tone.ready)
                .frame(width: size * 0.45, height: size * 0.45)
                .shadow(color: Tone.ready.opacity(0.8), radius: 4)
        case .off:
            Image(systemName: "xmark")
                .font(.system(size: size * 0.7, weight: .bold))
                .foregroundStyle(Tone.silver.opacity(0.7))
        }
    }
}

private struct StatusBadge: View {
    let look: Look

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: look.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(look.tint)
            Text(look.title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

private struct LockScreenView: View {
    let state: DictationActivityAttributes.ContentState
    let look: Look

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(look.tint.opacity(0.20))
                Image(systemName: look.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(look.tint)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(look.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Offline Dictation")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            Marker(state: state, look: look, size: 28)
        }
        .padding(16)
    }
}
