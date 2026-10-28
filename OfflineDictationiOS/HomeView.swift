import SwiftUI

// MARK: - State passed in from the engine

struct HomeState {
    enum Phase { case idle, recording, transcribing }

    enum ModelStatus: Equatable {
        case notDownloaded
        case downloading
        case preparing
        case ready
        case failed(String)
    }

    var phase: Phase = .idle
    var hint: String = "Tap to dictate"
    var elapsed: TimeInterval = 0
    var levels: [Double] = []
    var transcript: String = ""
    var micDenied = false

    var modelStatus: ModelStatus = .notDownloaded
    var modelName = "Whisper Small"
    var modelIdentifier = "openai_whisper-small"
    var modelParameters = "244M"
    var bytesOnDisk: Int64 = 0
    var expectedBytes: Int64?
    var downloadProgress: Double = 0

    var prepareElapsed: TimeInterval = 0
    var prepareEstimate: TimeInterval = 180
    var prepareProgress: Double = 0

    // Shown while a dictation started from the keyboard is recording, to guide the user back.
    var showSwipeHint = false

    // Optional on-device smart cleanup.
    var cleanupEnabled = false
    var cleanupAvailable = false
    var cleanupNote = ""
    var isPolishing = false

    // Advanced (cloud) cleanup, an option under Smart cleanup.
    var cloudEnabled = false
    var cloudAvailable = false
    var cloudNote = ""

    // All models the user can choose from.
    var models: [ModelRowState] = []
    var modelActionsEnabled = true

    // The microphone is being kept ready in the background between dictations.
    var isArmed = false
}

struct ModelRowState: Identifiable, Equatable {
    enum Status: Equatable {
        case notDownloaded
        case downloading(Double)
        case downloaded
        case inUse(HomeState.ModelStatus)
    }

    let id: String
    let name: String
    let summary: String
    let bestFor: String
    let badges: [String]
    let meta: String
    let downloadSizeText: String
    var status: Status
    var lastTime: String?
    var canDelete: Bool
    var error: String?
}

// MARK: - Theme

enum Theme {
    static let backgroundTop = Color(red: 0.090, green: 0.091, blue: 0.098)
    static let backgroundBottom = Color(red: 0.030, green: 0.030, blue: 0.035)

    static let primary = Color(red: 0.700, green: 0.720, blue: 0.780)
    static let highlight = Color(red: 0.940, green: 0.950, blue: 0.970)
    static let recordingStart = Color(red: 0.840, green: 0.280, blue: 0.300)
    static let recordingEnd = Color(red: 0.940, green: 0.460, blue: 0.380)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.32)
    static let green = Color(red: 0.20, green: 0.83, blue: 0.60)
    static let rose = Color(red: 0.98, green: 0.44, blue: 0.52)

    static let accent = LinearGradient(colors: [primary, highlight], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let recording = LinearGradient(colors: [recordingStart, recordingEnd], startPoint: .topLeading, endPoint: .bottomTrailing)

    // Text and icons that sit on top of the accent gradient (dark for light metallic accents).
    static let onAccent = Color(red: 0.070, green: 0.070, blue: 0.090)
    // Strength of the ambient background glows.
    static let glow = 0.40

    static let cardFill = Color.white.opacity(0.055)
    static let cardStroke = Color.white.opacity(0.09)
    static let secondary = Color.white.opacity(0.62)
    static let tertiary = Color.white.opacity(0.40)
}

// MARK: - Root

struct HomeView: View {
    let state: HomeState
    var onMicTap: () -> Void = {}
    var onCopy: () -> Void = {}
    var onRetryModel: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onDismissHint: () -> Void = {}
    var onCancelTranscription: () -> Void = {}
    var onToggleCleanup: (Bool) -> Void = { _ in }
    var onSkipCleanup: () -> Void = {}
    var onToggleCloud: (Bool) -> Void = { _ in }
    var onSelectModel: (String) -> Void = { _ in }
    var onDownloadModel: (String) -> Void = { _ in }
    var onDeleteModel: (String) -> Void = { _ in }
    var onTurnOffMic: () -> Void = {}

    var body: some View {
        ZStack {
            AmbientBackground(isRecording: state.phase == .recording)

            ScrollView {
                VStack(spacing: 18) {
                    HeaderView(state: state)
                    DictationCard(state: state, onMicTap: onMicTap, onCopy: onCopy, onCancelTranscription: onCancelTranscription, onSkipCleanup: onSkipCleanup, onTurnOffMic: onTurnOffMic)
                    ModelCard(state: state, onRetry: onRetryModel)
                    ModelPickerCard(rows: state.models, actionsEnabled: state.modelActionsEnabled,
                                    onSelect: onSelectModel, onDownload: onDownloadModel, onDelete: onDeleteModel)
                    CleanupCard(enabled: state.cleanupEnabled, available: state.cleanupAvailable, note: state.cleanupNote, onToggle: onToggleCleanup,
                                cloudEnabled: state.cloudEnabled, cloudAvailable: state.cloudAvailable, cloudNote: state.cloudNote, onToggleCloud: onToggleCloud)
                    KeyboardSetupCard(onOpenSettings: onOpenSettings)
                    PrivacyFooter()
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)

            if state.showSwipeHint {
                SwipeBackOverlay(elapsed: state.elapsed, onDismiss: onDismissHint)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: state.showSwipeHint)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Background

struct AmbientBackground: View {
    let isRecording: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.backgroundTop, Theme.backgroundBottom], startPoint: .top, endPoint: .bottom)

            RadialGradient(colors: [(isRecording ? Theme.recordingStart : Theme.primary).opacity(0.30 * Theme.glow), .clear],
                           center: .init(x: 0.85, y: 0.02), startRadius: 0, endRadius: 380)

            RadialGradient(colors: [Theme.highlight.opacity(0.16 * Theme.glow), .clear],
                           center: .init(x: 0.0, y: 0.32), startRadius: 0, endRadius: 320)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: isRecording)
    }
}

// MARK: - Header

struct HeaderView: View {
    let state: HomeState

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent)
                Image(systemName: "waveform")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
            }
            .frame(width: 40, height: 40)
            .shadow(color: Theme.primary.opacity(0.45), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 1) {
                Text("Offline Dictation")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("Private speech to text")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
            }

            Spacer(minLength: 4)

            StatusChip(status: state.modelStatus)
                .fixedSize()
        }
        .padding(.top, 6)
    }
}

struct StatusChip: View {
    let status: HomeState.ModelStatus

    private var label: String {
        switch status {
        case .notDownloaded: "No model"
        case .downloading: "Downloading"
        case .preparing: "Preparing"
        case .ready: "Ready"
        case .failed: "Error"
        }
    }

    private var tint: Color {
        switch status {
        case .ready: Theme.green
        case .downloading, .preparing: Theme.warning
        case .failed: Theme.rose
        case .notDownloaded: Theme.secondary
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
                .shadow(color: tint.opacity(0.8), radius: 4)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: 1))
    }
}

// MARK: - Card container

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Theme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(
                        LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.04)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
            )
    }
}

// MARK: - Dictation card

struct DictationCard: View {
    let state: HomeState
    let onMicTap: () -> Void
    let onCopy: () -> Void
    let onCancelTranscription: () -> Void
    let onSkipCleanup: () -> Void
    let onTurnOffMic: () -> Void

    private var isRecording: Bool { state.phase == .recording }
    private var isBusy: Bool { state.phase == .transcribing }

    private var title: String {
        switch state.phase {
        case .idle: state.micDenied ? "Microphone is off" : (state.isArmed ? "Mic is ready" : "Ready to listen")
        case .recording: "Listening"
        case .transcribing: "Transcribing"
        }
    }

    var body: some View {
        Card {
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                    Text(isRecording ? formatted(state.elapsed) : state.hint)
                        .font(.system(size: 15, weight: .medium).monospacedDigit())
                        .foregroundStyle(isRecording ? Theme.recordingStart : Theme.secondary)
                        .multilineTextAlignment(.center)
                        .contentTransition(.numericText())
                }

                MicButton(phase: state.phase, level: state.levels.last ?? 0, onTap: onMicTap)
                    .padding(.vertical, 6)

                if state.isArmed && state.phase == .idle {
                    // The mic stays on in the background so the keyboard can dictate without opening this app.
                    Button(action: onTurnOffMic) {
                        Label("Turn off mic", systemImage: "mic.slash.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                            .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                if isBusy && state.isPolishing {
                    // The on-device cleanup takes a few seconds; let the user take the original text now.
                    Button(action: onSkipCleanup) {
                        Label("Use original text", systemImage: "forward.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Theme.accent))
                    }
                    .buttonStyle(PressableStyle())
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                if isBusy {
                    // Kill switch for a transcription that is taking too long, for example on long silences.
                    Button(action: onCancelTranscription) {
                        Label("Stop transcribing", systemImage: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                            .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                ScrollingWaveform(levels: state.levels, isActive: isRecording, isBusy: isBusy, isLive: state.isArmed && state.phase == .idle)
                    .frame(height: 44)

                TranscriptBox(text: state.transcript, isBusy: isBusy, onCopy: onCopy)
            }
            .frame(maxWidth: .infinity)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: state.phase)
        .sensoryFeedback(.impact(weight: .medium), trigger: state.phase)
    }

    private func formatted(_ time: TimeInterval) -> String {
        let total = Int(time)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct MicButton: View {
    let phase: HomeState.Phase
    let level: Double
    let onTap: () -> Void

    private var isRecording: Bool { phase == .recording }
    private var isBusy: Bool { phase == .transcribing }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if isRecording {
                    Circle()
                        .stroke(Theme.recordingStart.opacity(0.35), lineWidth: 2)
                        .frame(width: 132, height: 132)
                        .scaleEffect(1.12 + level * 0.30)
                        .animation(.easeOut(duration: 0.12), value: level)
                    Circle()
                        .stroke(Theme.recordingEnd.opacity(0.20), lineWidth: 2)
                        .frame(width: 132, height: 132)
                        .scaleEffect(1.32 + level * 0.45)
                        .animation(.easeOut(duration: 0.18), value: level)
                }

                Circle()
                    .fill(isRecording ? Theme.recording : Theme.accent)
                    .frame(width: 132, height: 132)
                    .overlay(
                        Circle().stroke(
                            LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1.5)
                    )
                    .shadow(color: (isRecording ? Theme.recordingStart : Theme.primary).opacity(0.55), radius: 26, y: 10)

                Group {
                    if isBusy {
                        ProgressView().tint(Theme.onAccent).scaleEffect(1.5)
                    } else {
                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 46, weight: .semibold))
                            .foregroundStyle(isRecording ? Color.white : Theme.onAccent)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }
            .frame(width: 190, height: 190)
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .disabled(isBusy)
        .accessibilityLabel(isRecording ? "Stop dictation" : "Start dictation")
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// Scrolling history of the voice level, newest on the right.
struct ScrollingWaveform: View {
    let levels: [Double]
    let isActive: Bool
    let isBusy: Bool
    // The mic is ready but nothing is being recorded: show it is live, in a calm colour.
    var isLive = false

    private let barCount = 34

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(isActive ? Theme.recording : Theme.accent)
                        .frame(width: 4, height: height(for: index, time: time))
                        .opacity(isActive || isBusy ? 1 : (isLive ? 0.75 : 0.35))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
    }

    private func height(for index: Int, time: Double) -> CGFloat {
        let minimum: CGFloat = 4
        let maximum: CGFloat = 44

        if isBusy {
            let wave = 0.5 + 0.5 * sin(time * 4 - Double(index) * 0.45)
            return minimum + (maximum - minimum) * 0.55 * CGFloat(wave)
        }
        if isActive || isLive {
            let offset = levels.count - barCount + index
            let level = offset >= 0 && offset < levels.count ? levels[offset] : 0
            return minimum + (maximum - minimum) * CGFloat(min(1, level))
        }
        // Resting state: a calm, static silhouette.
        let resting = 0.10 + 0.22 * abs(sin(Double(index) * 0.55))
        return minimum + (maximum - minimum) * CGFloat(resting)
    }
}

struct TranscriptBox: View {
    let text: String
    let isBusy: Bool
    let onCopy: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Transcript", systemImage: "text.alignleft")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
                    .labelStyle(.titleAndIcon)
                Spacer()
                if !text.isEmpty {
                    Button(action: copyTapped) {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(copied ? Theme.green : .white.opacity(0.85))
                            .contentTransition(.symbolEffect(.replace))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(copied ? Theme.green.opacity(0.18) : Color.white.opacity(0.10)))
                            .overlay(Capsule().stroke(copied ? Theme.green.opacity(0.45) : .clear, lineWidth: 1))
                            .scaleEffect(copied ? 1.06 : 1)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.success, trigger: copied) { _, isCopied in isCopied }
                }
            }

            Text(text.isEmpty ? "What you say will appear here, and is sent straight to the keyboard." : text)
                .font(.system(size: 16))
                .foregroundStyle(text.isEmpty ? Theme.tertiary : .white)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(copied ? Theme.green.opacity(0.10) : Color.black.opacity(0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(copied ? Theme.green.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: copied)
    }

    private func copyTapped() {
        onCopy()
        copied = true
        Task {
            try? await Task.sleep(for: .milliseconds(1700))
            copied = false
        }
    }
}

// MARK: - Model card

struct ModelCard: View {
    let state: HomeState
    let onRetry: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    IconTile(symbol: "cpu", tint: Theme.highlight)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Speech model")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.tertiary)
                        Text(state.modelName)
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }

                Text(state.modelIdentifier)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.3)))

                statusBody

                HStack(spacing: 10) {
                    StatTile(value: sizeText, label: "On this iPhone")
                    StatTile(value: state.modelParameters, label: "Parameters")
                    StatTile(value: "99", label: "Languages")
                }
            }
        }
    }

    private var sizeText: String {
        state.bytesOnDisk > 0 ? ByteFormat.string(state.bytesOnDisk) : "0 MB"
    }

    @ViewBuilder private var statusBody: some View {
        switch state.modelStatus {
        case .downloading:
            VStack(alignment: .leading, spacing: 10) {
                ProgressBar(fraction: state.downloadProgress)
                HStack {
                    Text(downloadDetail)
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Text("\(Int((state.downloadProgress * 100).rounded()))%")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.highlight)
                }
                Text("Downloaded once, then it works fully offline.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiary)
            }
        case .preparing:
            VStack(alignment: .leading, spacing: 10) {
                ProgressBar(fraction: state.prepareProgress)
                HStack {
                    Text("\(clock(state.prepareElapsed)) · usually about \(max(1, Int((state.prepareEstimate / 60).rounded()))) min")
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Text("≈ \(Int((state.prepareProgress * 100).rounded()))%")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.highlight)
                }
                Text("Optimising for your iPhone's Neural Engine. This runs once after every install or update, then dictation starts instantly. The percentage is an estimate.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.rose)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onRetry) {
                    Text("Try again")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(PressableStyle())
            }
        case .notDownloaded:
            VStack(alignment: .leading, spacing: 10) {
                Text("The model isn't on this iPhone yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                Button(action: onRetry) {
                    Label("Download model", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(PressableStyle())
            }
        case .ready:
            Label("Loaded and running on-device. No internet needed.", systemImage: "checkmark.seal.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.green)
        }
    }

    private func clock(_ time: TimeInterval) -> String {
        let total = Int(time)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var downloadDetail: String {
        let done = ByteFormat.string(state.bytesOnDisk)
        if let expected = state.expectedBytes, expected > 0 {
            return "\(done) of ~\(ByteFormat.string(expected))"
        }
        return done
    }
}

struct IconTile: View {
    let symbol: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous).fill(tint.opacity(0.16))
            RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(tint.opacity(0.35), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 44, height: 44)
    }
}

struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.28)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
}

struct ProgressBar: View {
    // nil shows an indeterminate shimmer.
    let fraction: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))

                if let fraction {
                    Capsule().fill(Theme.accent)
                        .frame(width: max(8, proxy.size.width * min(1, max(0, fraction))))
                        .animation(.easeOut(duration: 0.3), value: fraction)
                } else {
                    TimelineView(.animation) { timeline in
                        let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                        Capsule().fill(Theme.accent)
                            .frame(width: proxy.size.width * 0.35)
                            .offset(x: (proxy.size.width * 1.35) * CGFloat(phase) - proxy.size.width * 0.35)
                    }
                    .clipShape(Capsule())
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
    }
}

enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Keyboard setup

struct KeyboardSetupCard: View {
    let onOpenSettings: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    IconTile(symbol: "keyboard", tint: Theme.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dictate anywhere")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Add the keyboard in three steps")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    StepRow(number: 1, text: "Open Settings, then General, Keyboard, Keyboards.")
                    StepRow(number: 2, text: "Tap Add New Keyboard and choose DictationKeyboard.")
                    StepRow(number: 3, text: "Open DictationKeyboard and turn on Allow Full Access.")
                }

                Button(action: onOpenSettings) {
                    HStack(spacing: 8) {
                        Text("Open Settings")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.accent))
                    .shadow(color: Theme.primary.opacity(0.35), radius: 14, y: 6)
                }
                .buttonStyle(PressableStyle())

                Text("Full Access only lets the keyboard receive text from this app. Nothing is sent over the internet.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.10)))
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }
}

struct PrivacyFooter: View {
    var body: some View {
        Label("Runs entirely on this iPhone. Your voice never leaves it.", systemImage: "lock.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.tertiary)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }
}


// MARK: - Swipe back guidance

// Shown when the keyboard's mic opened the app: recording has already started, so show how to get back.
struct SwipeBackOverlay: View {
    let elapsed: TimeInterval
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            ZStack {
                LinearGradient(colors: [Theme.backgroundTop, Theme.backgroundBottom], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Theme.recordingStart.opacity(0.22), .clear],
                               center: .init(x: 0.5, y: 0.30), startRadius: 0, endRadius: 360)
            }
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()

                HStack(spacing: 8) {
                    Circle().fill(Theme.recordingStart).frame(width: 8, height: 8)
                        .shadow(color: Theme.recordingStart.opacity(0.9), radius: 5)
                    Text("Recording \(clock(elapsed))")
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.09)))
                .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: 1))

                VStack(spacing: 8) {
                    Text("Swipe back to keep typing")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("Slide your finger right along the bottom edge of the screen to return to your app. Recording carries on in the background, and the mic stays ready, so next time you can just tap the mic on the keyboard.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 36)
                }

                Spacer()

                Button(action: onDismiss) {
                    Text("Stay in this app")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)

                SwipeGestureAnimation()
                    .frame(height: 90)
                    .padding(.horizontal, 24)
            }
            .padding(.bottom, 8)
        }
    }

    private func clock(_ time: TimeInterval) -> String {
        let total = Int(time)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// A fingertip glides right along a home-indicator bar, leaving a fading trail of chevrons.
struct SwipeGestureAnimation: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let cycle = 2.4
            let phase = time.truncatingRemainder(dividingBy: cycle) / cycle
            // Glide during the first 70% of the loop, then fade and reset.
            let travel = min(1, phase / 0.7)
            let eased = travel * travel * (3 - 2 * travel)
            let opacity = phase < 0.08 ? phase / 0.08 : (phase > 0.78 ? max(0, 1 - (phase - 0.78) / 0.16) : 1)

            GeometryReader { proxy in
                let barWidth = min(proxy.size.width, 300)
                let originX = (proxy.size.width - barWidth) / 2
                let fingerX = originX + 22 + (barWidth - 44) * eased

                ZStack(alignment: .topLeading) {
                    // The home indicator bar.
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: barWidth, height: 6)
                        .position(x: proxy.size.width / 2, y: proxy.size.height - 14)

                    // Glow trail behind the finger.
                    Capsule()
                        .fill(LinearGradient(colors: [.clear, Theme.primary.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, (barWidth - 44) * eased + 22), height: 6)
                        .position(x: originX + max(0, (barWidth - 44) * eased + 22) / 2, y: proxy.size.height - 14)
                        .opacity(opacity)

                    // Chevrons hint at the direction.
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { index in
                            Image(systemName: "chevron.right")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.primary.opacity(0.35 + 0.65 * chevronGlow(index: index, time: time)))
                        }
                    }
                    .position(x: proxy.size.width / 2, y: 22)

                    // The fingertip.
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
                        .shadow(color: Theme.primary.opacity(0.6), radius: 10)
                        .position(x: fingerX, y: proxy.size.height - 14)
                        .opacity(opacity)
                }
            }
        }
    }

    private func chevronGlow(index: Int, time: Double) -> Double {
        0.5 + 0.5 * sin(time * 5 - Double(index) * 0.9)
    }
}


// MARK: - Smart cleanup

struct CleanupCard: View {
    let enabled: Bool
    let available: Bool
    let note: String
    let onToggle: (Bool) -> Void
    let cloudEnabled: Bool
    let cloudAvailable: Bool
    let cloudNote: String
    let onToggleCloud: (Bool) -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    IconTile(symbol: "sparkles", tint: Theme.highlight)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart cleanup")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Powered by Apple Intelligence")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 8)
                    Toggle("Smart cleanup", isOn: Binding(get: { enabled && available }, set: onToggle))
                        .labelsHidden()
                        .tint(Theme.primary)
                        .disabled(!available)
                }

                Text("After Whisper writes down what you said, Smart cleanup rewrites it into what you meant to say, before it reaches your text field.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 9) {
                    CleanupPoint(text: "Fixes punctuation and capital letters")
                    CleanupPoint(text: "Removes fillers such as \"um\" and \"uh\"")
                    CleanupPoint(text: "Keeps only your final version when you correct yourself, so \"Tuesday, no wait, Monday\" becomes \"Monday\"")
                }

                Text("It runs on this iPhone, so your words never leave it. It takes a few seconds, and you can tap Use original text to skip it. If it is slow or unavailable, your original text is used.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if !note.isEmpty {
                    Divider().overlay(Color.white.opacity(0.08))
                    Text(note)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(Color.white.opacity(0.08))

                // Advanced: a separate, optional step that sends text to Apple's cloud.
                HStack(spacing: 12) {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.highlight)
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Advanced (cloud)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("A stronger clean-up in Apple's cloud")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 8)
                    Toggle("Advanced cloud cleanup", isOn: Binding(get: { cloudEnabled && enabled && cloudAvailable }, set: onToggleCloud))
                        .labelsHidden()
                        .tint(Theme.primary)
                        .disabled(!(enabled && available && cloudAvailable))
                }

                Text("Uses Apple's cloud computing (Private Cloud Compute) for a stronger clean-up. Only your transcribed text is sent to Apple over the internet. Your audio is never sent: Whisper turns it into text on this iPhone. If the cloud is offline, slow or over its limit, Smart cleanup quietly uses the on-device model instead. Turn Smart cleanup off and nothing is sent.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if !cloudAvailable, !cloudNote.isEmpty {
                    Text(cloudNote)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct CleanupPoint: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.highlight.opacity(0.9))
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}


// MARK: - Model picker

struct ModelPickerCard: View {
    let rows: [ModelRowState]
    let actionsEnabled: Bool
    let onSelect: (String) -> Void
    let onDownload: (String) -> Void
    let onDelete: (String) -> Void

    // Collapsed by default, so the long list only takes space when the user opens it.
    @State private var isExpanded: Bool
    // Natural height of the list, measured so opening and closing can animate one clean frame.
    @State private var listHeight: CGFloat = 0

    init(rows: [ModelRowState], actionsEnabled: Bool,
         onSelect: @escaping (String) -> Void, onDownload: @escaping (String) -> Void, onDelete: @escaping (String) -> Void,
         startsExpanded: Bool = false) {
        self.rows = rows
        self.actionsEnabled = actionsEnabled
        self.onSelect = onSelect
        self.onDownload = onDownload
        self.onDelete = onDelete
        _isExpanded = State(initialValue: startsExpanded)
    }

    // What the collapsed header says: the model in use, or a download in progress.
    private var summary: String {
        for row in rows {
            if case .downloading(let fraction) = row.status {
                return "Downloading \(row.name) · \(Int((fraction * 100).rounded()))%"
            }
        }
        if let current = rows.first(where: { if case .inUse = $0.status { return true } else { return false } }) {
            return "Using \(current.name) · \(rows.count) models"
        }
        return "\(rows.count) models"
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.smooth(duration: 0.35)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        IconTile(symbol: "square.stack.3d.up.fill", tint: Theme.highlight)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Choose a model")
                                .font(.system(size: 21, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text(isExpanded ? "Bigger models are more accurate, but slower" : summary)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.secondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose a model")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint("Shows all speech models you can download and use")

                // The list is always laid out at its natural height, then revealed by animating a clipped frame.
                // Inserting and removing it instead made the card's background and the rows move out of step.
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        ModelRowView(row: row, actionsEnabled: actionsEnabled,
                                     onSelect: onSelect, onDownload: onDownload, onDelete: onDelete)
                    }

                    if !actionsEnabled {
                        Text("Models can be changed when nothing is recording or loading.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.tertiary)
                    }
                }
                .padding(.top, 16)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ListHeightKey.self, value: proxy.size.height)
                })
                .onPreferenceChange(ListHeightKey.self) { listHeight = $0 }
                .frame(height: isExpanded ? listHeight : 0, alignment: .top)
                .clipped()
                .opacity(isExpanded ? 1 : 0)
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)
            }
        }
    }
}

private struct ListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct ModelRowView: View {
    let row: ModelRowState
    let actionsEnabled: Bool
    let onSelect: (String) -> Void
    let onDownload: (String) -> Void
    let onDelete: (String) -> Void

    private var isInUse: Bool {
        if case .inUse = row.status { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(row.name)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                ForEach(row.badges, id: \.self) { badge in
                    ModelBadge(text: badge)
                }
                Spacer(minLength: 0)
            }

            Text(row.summary)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            Text("Best for: " + row.bestFor)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if case .downloading(let fraction) = row.status {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressBar(fraction: fraction)
                    Text("Downloading \(Int((fraction * 100).rounded()))%")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.highlight)
                }
            }

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.meta)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let lastTime = row.lastTime {
                        Text(lastTime)
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(Theme.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                action
            }

            if let error = row.error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.rose)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isInUse ? Theme.primary.opacity(0.10) : Color.black.opacity(0.26))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isInUse ? Theme.primary.opacity(0.55) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder private var action: some View {
        switch row.status {
        case .notDownloaded:
            Button { onDownload(row.id) } label: {
                Label("Download \(row.downloadSizeText)", systemImage: "arrow.down.circle.fill")
                    .lineLimit(1)
                    .fixedSize()
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(PressableStyle())
            .disabled(!actionsEnabled)
            .opacity(actionsEnabled ? 1 : 0.4)
        case .downloading:
            EmptyView()
        case .downloaded:
            HStack(spacing: 8) {
                if row.canDelete {
                    Button { onDelete(row.id) } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.rose)
                            .frame(width: 36, height: 34)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Delete \(row.name)")
                }
                Button { onSelect(row.id) } label: {
                    Text("Use")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(PressableStyle())
                .disabled(!actionsEnabled)
                .opacity(actionsEnabled ? 1 : 0.4)
            }
        case .inUse(let status):
            InUseChip(status: status)
        }
    }
}

struct ModelBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Theme.highlight)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.highlight.opacity(0.14)))
            .overlay(Capsule().stroke(Theme.highlight.opacity(0.30), lineWidth: 1))
    }
}

struct InUseChip: View {
    let status: HomeState.ModelStatus

    private var label: String {
        switch status {
        case .ready: "In use"
        case .preparing: "Preparing"
        case .downloading: "Downloading"
        case .failed: "Error"
        case .notDownloaded: "Not loaded"
        }
    }

    private var tint: Color {
        switch status {
        case .ready: Theme.green
        case .preparing, .downloading: Theme.warning
        case .failed: Theme.rose
        case .notDownloaded: Theme.secondary
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status == .ready ? "checkmark.circle.fill" : "circle.dotted")
                .font(.system(size: 13, weight: .semibold))
            Text(label)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(tint.opacity(0.14)))
        .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 1))
    }
}
