import UIKit
import AVFoundation

// MARK: - Model

private enum KeyboardLayer { case letters, numbers, symbols }
private enum ShiftState { case off, on, caps }
private enum DictationState { case idle, opening, recording, transcribing }

private enum KeyKind {
    case character(String)
    case shift
    case delete
    case layerSwitch(KeyboardLayer)
    case globe
    case space
    case returnKey
}

private enum Palette {
    static let background = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.13, alpha: 1) : UIColor(red: 0.82, green: 0.84, blue: 0.86, alpha: 1) }
    static let key = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.29, alpha: 1) : .white }
    static let keyLit = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.43, alpha: 1) : UIColor(white: 0.72, alpha: 1) }
    // Titanium, matching the app.
    static let silverTop = UIColor(red: 0.70, green: 0.72, blue: 0.78, alpha: 1)
    static let silverBottom = UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1)
    static let onSilver = UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
    static let recording = UIColor(red: 0.88, green: 0.37, blue: 0.34, alpha: 1)
    static let ready = UIColor(red: 0.20, green: 0.83, blue: 0.60, alpha: 1)
    static let circleMuted = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.34, alpha: 1) : UIColor(white: 0.72, alpha: 1) }
}

// MARK: - Views

private final class KeyButton: UIButton {
    let kind: KeyKind
    var isLit = false { didSet { updateBackground() } }

    init(kind: KeyKind) {
        self.kind = kind
        super.init(frame: .zero)
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        setTitleColor(.label, for: .normal)
        tintColor = .label
        updateBackground()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isHighlighted: Bool { didSet { updateBackground() } }

    func updateBackground() {
        backgroundColor = (isHighlighted || isLit) ? Palette.keyLit : Palette.key
    }
}

private final class KeyAreaView: UIView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

private final class CircleButton: UIButton {
    private let gradientLayer = CAGradientLayer()

    var gradientColors: [UIColor]? {
        didSet { updateGradient() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if gradientLayer.superlayer == nil {
            gradientLayer.startPoint = CGPoint(x: 0, y: 0)
            gradientLayer.endPoint = CGPoint(x: 1, y: 1)
            layer.insertSublayer(gradientLayer, at: 0)
        }
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = bounds.height / 2
        layer.cornerRadius = bounds.height / 2
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateGradient()
    }

    private func updateGradient() {
        if let colors = gradientColors {
            gradientLayer.colors = colors.map { $0.resolvedColor(with: traitCollection).cgColor }
            gradientLayer.isHidden = false
        } else {
            gradientLayer.isHidden = true
        }
    }
}

// A scrolling history of the voice level, newest on the right. Same look as the app.
private final class WaveformView: UIView {
    enum Mode { case flat, listening, processing }

    var mode: Mode = .flat {
        didSet {
            guard mode != oldValue else { return }
            if mode == .listening { levels = [] }
            updateColors()
        }
    }

    private let barCount = 34
    private let barWidth: CGFloat = 4
    private let gap: CGFloat = 4
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 40
    private var bars: [UIView] = []
    private var levels: [CGFloat] = []
    private var heights: [CGFloat]

    override init(frame: CGRect) {
        heights = Array(repeating: 4, count: 34)
        super.init(frame: frame)
        for _ in 0..<barCount {
            let bar = UIView()
            bar.layer.cornerRadius = barWidth / 2
            addSubview(bar)
            bars.append(bar)
        }
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap, height: maxHeight + 4)
    }

    func push(level: CGFloat) {
        levels.append(level)
        if levels.count > barCount { levels.removeFirst(levels.count - barCount) }
    }

    func step(time: CFTimeInterval) {
        for index in 0..<barCount {
            let fraction: CGFloat
            switch mode {
            case .listening:
                let offset = levels.count - barCount + index
                fraction = offset >= 0 ? min(1, levels[offset]) : 0
            case .processing:
                fraction = 0.55 * CGFloat(0.5 + 0.5 * sin(time * 4 - Double(index) * 0.45))
            case .flat:
                fraction = CGFloat(0.10 + 0.22 * abs(sin(Double(index) * 0.55)))
            }
            let target = minHeight + (maxHeight - minHeight) * fraction
            heights[index] += (target - heights[index]) * 0.5
        }
        setNeedsLayout()
    }

    private func updateColors() {
        let color: UIColor
        switch mode {
        case .listening: color = Palette.recording
        case .processing: color = Palette.silverTop
        case .flat: color = Palette.silverTop.withAlphaComponent(0.4)
        }
        bars.forEach { $0.backgroundColor = color }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (index, bar) in bars.enumerated() {
            let height = heights[index]
            bar.frame = CGRect(x: CGFloat(index) * (barWidth + gap), y: (bounds.height - height) / 2, width: barWidth, height: height)
        }
    }
}

// MARK: - Controller

class KeyboardViewController: UIInputViewController {
    private let keyArea = KeyAreaView()
    private let statusLabel = UILabel()
    private let micButton = CircleButton(type: .custom)
    private let popup = UILabel()

    private let dictationPanel = UIView()
    private let cancelButton = CircleButton(type: .custom)
    private let doneButton = CircleButton(type: .custom)
    private let waveform = WaveformView()
    private let listeningLabel = UILabel()
    private let panelDeleteButton = KeyButton(kind: .delete)
    private var lastLevelPush: CFTimeInterval = 0
    private var displayLink: CADisplayLink?

    private var heightConstraint: NSLayoutConstraint!
    private var keyAreaTop: NSLayoutConstraint!
    private var micTop: NSLayoutConstraint!
    private var cancelTop: NSLayoutConstraint!
    private var doneTop: NSLayoutConstraint!
    private var waveformCenterY: NSLayoutConstraint!

    private var currentLayer: KeyboardLayer = .letters
    private var shiftState: ShiftState = .off
    private var lastShiftTap: Date?
    private var keyRows: [[KeyButton]] = []
    private var showsGlobeKey = false

    private var backspaceTimer: Timer?
    private var backspaceStartTime: Date?
    private var lastSpaceTap: Date?

    private var pollTimer: Timer?
    private var dictationState: DictationState = .idle
    private var awaitingSince: Date?
    private var panelShown = false

    private var isCompact: Bool { traitCollection.verticalSizeClass == .compact }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        hasDictationKey = true
        view.backgroundColor = Palette.background

        setupKeyArea()
        setupTopControls()
        setupPopup()
        setupDictationPanel()

        heightConstraint = view.heightAnchor.constraint(equalToConstant: 273)
        heightConstraint.priority = UILayoutPriority(999)
        heightConstraint.isActive = true

        showsGlobeKey = needsInputModeSwitchKey
        buildKeys()
        updateAutoShift()
        applyMetrics()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if showsGlobeKey != needsInputModeSwitchKey {
            showsGlobeKey = needsInputModeSwitchKey
            buildKeys()
        }
        updateAutoShift()
        updateReturnKeyTitle()
        checkForResult()
        refreshDictationUI()
        startPolling()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pollTimer?.invalidate()
        stopDisplayLink()
        backspaceTouchUp()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        applyMetrics()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateAutoShift()
        updateReturnKeyTitle()
    }

    private func applyMetrics() {
        let compact = isCompact
        heightConstraint.constant = compact ? 206 : 273
        keyAreaTop.constant = compact ? 50 : 56
        let buttonTop: CGFloat = compact ? 3 : 6
        micTop.constant = buttonTop
        cancelTop.constant = buttonTop
        doneTop.constant = buttonTop
        waveformCenterY.constant = compact ? 84 : 106
    }

    // MARK: Setup

    private func setupKeyArea() {
        keyArea.translatesAutoresizingMaskIntoConstraints = false
        keyArea.onLayout = { [weak self] in self?.layoutKeys() }
        view.addSubview(keyArea)

        keyAreaTop = keyArea.topAnchor.constraint(equalTo: view.topAnchor, constant: 87)
        NSLayoutConstraint.activate([
            keyAreaTop,
            keyArea.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyArea.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyArea.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupTopControls() {
        statusLabel.font = UIFont.systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabel
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        styleCircle(micButton, symbol: "mic.fill", silver: true)
        micButton.accessibilityLabel = "Start dictation"
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
        view.addSubview(micButton)

        micTop = micButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 6)
        NSLayoutConstraint.activate([
            micTop,
            micButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            micButton.widthAnchor.constraint(equalToConstant: 44),
            micButton.heightAnchor.constraint(equalToConstant: 44),

            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.centerYAnchor.constraint(equalTo: micButton.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: micButton.leadingAnchor, constant: -8)
        ])
    }

    private func styleCircle(_ button: CircleButton, symbol: String, silver: Bool) {
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        button.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        if silver {
            button.tintColor = Palette.onSilver
            button.gradientColors = [Palette.silverTop, Palette.silverBottom]
            button.backgroundColor = .clear
        } else {
            button.tintColor = .white
            button.gradientColors = nil
            button.backgroundColor = Palette.circleMuted
        }
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupPopup() {
        popup.font = UIFont.systemFont(ofSize: 32)
        popup.textAlignment = .center
        popup.textColor = .label
        popup.backgroundColor = Palette.keyLit
        popup.layer.cornerRadius = 10
        popup.layer.cornerCurve = .continuous
        popup.clipsToBounds = true
        popup.isHidden = true
        view.addSubview(popup)
    }

    private func setupDictationPanel() {
        dictationPanel.backgroundColor = Palette.background
        dictationPanel.translatesAutoresizingMaskIntoConstraints = false
        dictationPanel.isHidden = true
        dictationPanel.alpha = 0
        view.addSubview(dictationPanel)

        styleCircle(cancelButton, symbol: "xmark", silver: false)
        cancelButton.accessibilityLabel = "Cancel dictation"
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        styleCircle(doneButton, symbol: "checkmark", silver: true)
        doneButton.accessibilityLabel = "Finish dictation"
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        waveform.translatesAutoresizingMaskIntoConstraints = false

        listeningLabel.textAlignment = .center
        listeningLabel.numberOfLines = 2
        listeningLabel.translatesAutoresizingMaskIntoConstraints = false

        panelDeleteButton.setImage(UIImage(systemName: "delete.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)), for: .normal)
        panelDeleteButton.accessibilityLabel = "Delete"
        panelDeleteButton.translatesAutoresizingMaskIntoConstraints = false
        panelDeleteButton.addTarget(self, action: #selector(backspaceTouchDown), for: .touchDown)
        panelDeleteButton.addTarget(self, action: #selector(backspaceTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        dictationPanel.addSubview(cancelButton)
        dictationPanel.addSubview(doneButton)
        dictationPanel.addSubview(waveform)
        dictationPanel.addSubview(listeningLabel)
        dictationPanel.addSubview(panelDeleteButton)

        cancelTop = cancelButton.topAnchor.constraint(equalTo: dictationPanel.topAnchor, constant: 6)
        doneTop = doneButton.topAnchor.constraint(equalTo: dictationPanel.topAnchor, constant: 6)
        waveformCenterY = waveform.centerYAnchor.constraint(equalTo: dictationPanel.topAnchor, constant: 106)

        NSLayoutConstraint.activate([
            dictationPanel.topAnchor.constraint(equalTo: view.topAnchor),
            dictationPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dictationPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dictationPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            cancelTop,
            cancelButton.leadingAnchor.constraint(equalTo: dictationPanel.leadingAnchor, constant: 12),
            cancelButton.widthAnchor.constraint(equalToConstant: 44),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),

            doneTop,
            doneButton.trailingAnchor.constraint(equalTo: dictationPanel.trailingAnchor, constant: -12),
            doneButton.widthAnchor.constraint(equalToConstant: 44),
            doneButton.heightAnchor.constraint(equalToConstant: 44),

            waveformCenterY,
            waveform.centerXAnchor.constraint(equalTo: dictationPanel.centerXAnchor),

            listeningLabel.topAnchor.constraint(equalTo: waveform.bottomAnchor, constant: 26),
            listeningLabel.centerXAnchor.constraint(equalTo: dictationPanel.centerXAnchor),
            listeningLabel.leadingAnchor.constraint(greaterThanOrEqualTo: dictationPanel.leadingAnchor, constant: 70),
            listeningLabel.trailingAnchor.constraint(lessThanOrEqualTo: dictationPanel.trailingAnchor, constant: -70),

            panelDeleteButton.trailingAnchor.constraint(equalTo: dictationPanel.trailingAnchor, constant: -6),
            panelDeleteButton.bottomAnchor.constraint(equalTo: dictationPanel.bottomAnchor, constant: -6),
            panelDeleteButton.widthAnchor.constraint(equalToConstant: 62),
            panelDeleteButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    // MARK: Keys

    private func keyKinds(for layer: KeyboardLayer) -> [[KeyKind]] {
        func chars(_ text: String) -> [KeyKind] { text.map { .character(String($0)) } }
        func chars(_ list: [String]) -> [KeyKind] { list.map { .character($0) } }

        var bottom: [KeyKind] = [.layerSwitch(layer == .letters ? .numbers : .letters)]
        bottom.append(.space)
        if showsGlobeKey { bottom.insert(.globe, at: 1) }
        bottom.append(.returnKey)

        switch layer {
        case .letters:
            return [chars("qwertyuiop"), chars("asdfghjkl"), [.shift] + chars("zxcvbnm") + [.delete], bottom]
        case .numbers:
            return [chars("1234567890"),
                    chars(["-", "/", ":", ";", "(", ")", "£", "&", "@", "\""]),
                    [.layerSwitch(.symbols)] + chars([".", ",", "?", "!", "'"]) + [.delete],
                    bottom]
        case .symbols:
            return [chars(["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]),
                    chars(["_", "\\", "|", "~", "<", ">", "€", "$", "¥", "•"]),
                    [.layerSwitch(.numbers)] + chars([".", ",", "?", "!", "'"]) + [.delete],
                    bottom]
        }
    }

    private func buildKeys() {
        keyRows.flatMap { $0 }.forEach { $0.removeFromSuperview() }
        keyRows = keyKinds(for: currentLayer).map { row in row.map { makeKey($0) } }
        keyRows.flatMap { $0 }.forEach { keyArea.addSubview($0) }
        updateLetterCase()
        updateReturnKeyTitle()
        keyArea.setNeedsLayout()
    }

    private func makeKey(_ kind: KeyKind) -> KeyButton {
        let key = KeyButton(kind: kind)
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)

        switch kind {
        case .character(let text):
            key.setTitle(text, for: .normal)
            key.titleLabel?.font = UIFont.systemFont(ofSize: 25)
            key.addTarget(self, action: #selector(keyTouchDown(_:)), for: .touchDown)
            key.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
            key.addTarget(self, action: #selector(keyTouchEnded(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        case .shift:
            key.setImage(UIImage(systemName: "shift", withConfiguration: symbolConfig), for: .normal)
            key.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
        case .delete:
            key.setImage(UIImage(systemName: "delete.left", withConfiguration: symbolConfig), for: .normal)
            key.addTarget(self, action: #selector(backspaceTouchDown), for: .touchDown)
            key.addTarget(self, action: #selector(backspaceTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        case .layerSwitch(let target):
            switch target {
            case .letters: key.setTitle("ABC", for: .normal)
            case .numbers: key.setTitle("123", for: .normal)
            case .symbols: key.setTitle("#+=", for: .normal)
            }
            key.titleLabel?.font = UIFont.systemFont(ofSize: 17)
            key.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
        case .globe:
            key.setImage(UIImage(systemName: "globe", withConfiguration: symbolConfig), for: .normal)
            key.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        case .space:
            key.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
        case .returnKey:
            key.titleLabel?.font = UIFont.systemFont(ofSize: 17)
            key.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
        }
        return key
    }

    private func layoutKeys() {
        guard keyRows.count == 4, keyArea.bounds.width > 0 else { return }

        let width = keyArea.bounds.width
        let side: CGFloat = 6
        let gap: CGFloat = 6
        let verticalGap: CGFloat = isCompact ? 8 : 11.67
        let bottomPadding: CGFloat = 6
        let keyHeight = min(44, (keyArea.bounds.height - bottomPadding - 3 * verticalGap) / 4)
        let keyWidth = (width - 2 * side - 9 * gap) / 10
        let specialWidth = keyWidth * 1.375

        func rowY(_ index: Int) -> CGFloat { CGFloat(index) * (keyHeight + verticalGap) }

        func place(_ keys: [KeyButton], startX: CGFloat, keyWidth: CGFloat, y: CGFloat) {
            var x = startX
            for key in keys {
                key.frame = CGRect(x: x, y: y, width: keyWidth, height: keyHeight)
                x += keyWidth + gap
            }
        }

        place(keyRows[0], startX: side, keyWidth: keyWidth, y: rowY(0))

        if currentLayer == .letters {
            place(keyRows[1], startX: side + keyWidth / 2 + gap / 2, keyWidth: keyWidth, y: rowY(1))
        } else {
            place(keyRows[1], startX: side, keyWidth: keyWidth, y: rowY(1))
        }

        // Row 3: special key, middle keys, delete
        let row3 = keyRows[2]
        let y3 = rowY(2)
        let middle = Array(row3.dropFirst().dropLast())
        let inner = width - 2 * side - 2 * specialWidth
        let middleWidth: CGFloat
        let gapAroundMiddle: CGFloat
        if currentLayer == .letters {
            middleWidth = keyWidth
            gapAroundMiddle = (inner - CGFloat(middle.count) * keyWidth - CGFloat(middle.count - 1) * gap) / 2
        } else {
            gapAroundMiddle = 14
            middleWidth = (inner - 2 * gapAroundMiddle - CGFloat(middle.count - 1) * gap) / CGFloat(middle.count)
        }
        row3.first?.frame = CGRect(x: side, y: y3, width: specialWidth, height: keyHeight)
        place(middle, startX: side + specialWidth + gapAroundMiddle, keyWidth: middleWidth, y: y3)
        row3.last?.frame = CGRect(x: width - side - specialWidth, y: y3, width: specialWidth, height: keyHeight)

        // Row 4: wide layer switch and return, blank space bar between
        let bottom = keyRows[3]
        let wideWidth = keyWidth * 2.8
        let globeWidth = keyWidth * 1.3
        var fixedWidth = 2 * wideWidth
        if showsGlobeKey { fixedWidth += globeWidth }
        let spaceWidth = width - 2 * side - fixedWidth - CGFloat(bottom.count - 1) * gap

        var x = side
        for key in bottom {
            let keyFrameWidth: CGFloat
            switch key.kind {
            case .layerSwitch, .returnKey: keyFrameWidth = wideWidth
            case .globe: keyFrameWidth = globeWidth
            default: keyFrameWidth = spaceWidth
            }
            key.frame = CGRect(x: x, y: rowY(3), width: keyFrameWidth, height: keyHeight)
            x += keyFrameWidth + gap
        }
    }

    // MARK: Typing actions

    @objc private func keyTouchDown(_ sender: KeyButton) {
        guard case .character(let text) = sender.kind else { return }
        popup.text = (currentLayer == .letters && shiftState != .off) ? text.uppercased() : text
        let frame = keyArea.convert(sender.frame, to: view)
        let popupWidth = max(frame.width * 1.5, 44)
        let popupHeight = frame.height * 1.2
        let x = min(max(frame.midX - popupWidth / 2, 2), view.bounds.width - popupWidth - 2)
        popup.frame = CGRect(x: x, y: frame.minY - popupHeight + 4, width: popupWidth, height: popupHeight)
        popup.isHidden = false
    }

    @objc private func keyTouchEnded(_ sender: KeyButton) {
        popup.isHidden = true
    }

    @objc private func keyTapped(_ sender: KeyButton) {
        switch sender.kind {
        case .character(let text):
            let output = (currentLayer == .letters && shiftState != .off) ? text.uppercased() : text
            textDocumentProxy.insertText(output)
            lastSpaceTap = nil
            if shiftState == .on { shiftState = .off }
            updateAutoShift()
            updateLetterCase()
        case .shift:
            handleShiftTap()
        case .layerSwitch(let target):
            currentLayer = target
            buildKeys()
            updateAutoShift()
        case .space:
            handleSpaceTap()
        case .returnKey:
            textDocumentProxy.insertText("\n")
            lastSpaceTap = nil
            updateAutoShift()
        case .delete, .globe:
            break
        }
    }

    private func handleShiftTap() {
        let now = Date()
        if shiftState == .caps {
            shiftState = .off
        } else if let last = lastShiftTap, now.timeIntervalSince(last) < 0.35 {
            shiftState = .caps
        } else {
            shiftState = shiftState == .on ? .off : .on
        }
        lastShiftTap = now
        updateLetterCase()
    }

    private func handleSpaceTap() {
        let now = Date()
        let characters = Array(textDocumentProxy.documentContextBeforeInput ?? "")
        if let last = lastSpaceTap, now.timeIntervalSince(last) < 0.5,
           characters.count >= 2, characters[characters.count - 1] == " ",
           characters[characters.count - 2].isLetter || characters[characters.count - 2].isNumber {
            textDocumentProxy.deleteBackward()
            textDocumentProxy.insertText(". ")
            lastSpaceTap = nil
        } else {
            textDocumentProxy.insertText(" ")
            lastSpaceTap = now
        }
        updateAutoShift()
    }

    // MARK: Delete

    // Like the system keyboard: a tap deletes a character, holding repeats, and holding on
    // switches to deleting a whole word at a time.
    @objc private func backspaceTouchDown() {
        textDocumentProxy.deleteBackward()
        backspaceStartTime = Date()
        backspaceTimer?.invalidate()
        backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            self?.scheduleNextDelete()
        }
    }

    private func scheduleNextDelete() {
        guard let started = backspaceStartTime else { return }
        let wordMode = Date().timeIntervalSince(started) > 1.6
        backspaceTimer?.invalidate()
        backspaceTimer = Timer.scheduledTimer(withTimeInterval: wordMode ? 0.2 : 0.075, repeats: false) { [weak self] _ in
            guard let self, self.backspaceStartTime != nil else { return }
            if wordMode { self.deleteWordBackward() } else { self.textDocumentProxy.deleteBackward() }
            self.scheduleNextDelete()
        }
    }

    private func deleteWordBackward() {
        var characters = Array(textDocumentProxy.documentContextBeforeInput ?? "")
        guard !characters.isEmpty else {
            textDocumentProxy.deleteBackward()
            return
        }
        var count = 0
        while let last = characters.last, last.isWhitespace { characters.removeLast(); count += 1 }
        while let last = characters.last, !last.isWhitespace { characters.removeLast(); count += 1 }
        for _ in 0..<max(1, min(count, 60)) { textDocumentProxy.deleteBackward() }
    }

    @objc private func backspaceTouchUp() {
        backspaceTimer?.invalidate()
        backspaceTimer = nil
        backspaceStartTime = nil
        updateAutoShift()
    }

    // MARK: Shift and return-key appearance

    private func updateLetterCase() {
        let uppercase = currentLayer == .letters && shiftState != .off
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)
        for key in keyRows.flatMap({ $0 }) {
            switch key.kind {
            case .character(let text):
                key.setTitle(uppercase ? text.uppercased() : text, for: .normal)
            case .shift:
                let name = shiftState == .caps ? "capslock.fill" : (shiftState == .on ? "shift.fill" : "shift")
                key.setImage(UIImage(systemName: name, withConfiguration: symbolConfig), for: .normal)
                key.isLit = shiftState != .off
            default:
                break
            }
        }
    }

    private func updateAutoShift() {
        guard currentLayer == .letters, shiftState != .caps else { return }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        var shouldShift = false

        switch textDocumentProxy.autocapitalizationType ?? .sentences {
        case .none:
            shouldShift = false
        case .allCharacters:
            shouldShift = true
        case .words:
            shouldShift = before.isEmpty || before.hasSuffix(" ") || before.hasSuffix("\n")
        case .sentences:
            if before.isEmpty || before.hasSuffix("\n") {
                shouldShift = true
            } else {
                let stripped = before.trimmingCharacters(in: CharacterSet(charactersIn: " "))
                if stripped.count < before.count, let last = stripped.last, ".!?".contains(last) {
                    shouldShift = true
                }
            }
        @unknown default:
            shouldShift = false
        }

        let newState: ShiftState = shouldShift ? .on : .off
        if newState != shiftState {
            shiftState = newState
            updateLetterCase()
        }
    }

    private func updateReturnKeyTitle() {
        let title: String?
        switch textDocumentProxy.returnKeyType ?? .default {
        case .go: title = "go"
        case .search, .google, .yahoo: title = "search"
        case .send: title = "send"
        case .done: title = "done"
        case .next: title = "next"
        case .join: title = "join"
        case .route: title = "route"
        case .continue: title = "continue"
        default: title = nil
        }
        let icon = UIImage(systemName: "return", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .regular))
        for key in keyRows.flatMap({ $0 }) {
            guard case .returnKey = key.kind else { continue }
            key.setTitle(title, for: .normal)
            key.setImage(title == nil ? icon : nil, for: .normal)
        }
    }

    // MARK: Dictation

    @objc private func micTapped() {
        guard hasFullAccess else {
            statusLabel.text = "Enable Allow Full Access in Settings"
            return
        }
        if SharedStorage.isRecordingActive() {
            doneTapped()
            return
        }

        CuePlayer.shared.play(.start, deactivateAfter: true)
        SharedStorage.clearResult()
        SharedStorage.clearCancelRequest()
        SharedStorage.requestRecording()
        dictationState = .opening
        awaitingSince = Date()
        refreshDictationUI()

        // The app is already keeping the microphone ready in the background: no need to open it. It starts
        // within a fraction of a second; if it doesn't, fall back to opening the app.
        if SharedStorage.isArmed() {
            startPolling()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.openAppIfNothingStarted()
            }
            return
        }

        if let url = URL(string: "offlinedictation://record"), openHostApp(url) {
            startPolling()
        } else {
            SharedStorage.clearRecordingRequest()
            dictationState = .idle
            awaitingSince = nil
            refreshDictationUI()
            statusLabel.text = "Could not open the app. Open it manually."
            startPolling()
        }
    }

    private func openAppIfNothingStarted() {
        guard dictationState == .opening, !SharedStorage.isRecordingActive() else { return }
        if let url = URL(string: "offlinedictation://record"), openHostApp(url) { return }
        SharedStorage.clearRecordingRequest()
        dictationState = .idle
        awaitingSince = nil
        refreshDictationUI()
        statusLabel.text = "Could not start. Open the app once."
    }

    // The check button: end the recording and insert what was said.
    @objc private func doneTapped() {
        guard dictationState == .recording || SharedStorage.isRecordingActive() else { return }
        CuePlayer.shared.play(.end, deactivateAfter: true)
        SharedStorage.requestStop()
        dictationState = .transcribing
        awaitingSince = Date()
        refreshDictationUI()
        startPolling()
    }

    // The X button: discards a recording, or stops the model if it is still transcribing.
    @objc private func cancelTapped() {
        // While the text is being polished, ✕ skips the polish and inserts the original instead of cancelling.
        if dictationState == .transcribing, SharedStorage.isPolishing() {
            SharedStorage.requestSkipPolish()
            return
        }
        SharedStorage.clearRecordingRequest()
        SharedStorage.clearResult()
        SharedStorage.requestCancel()
        dictationState = .idle
        awaitingSince = nil
        refreshDictationUI()
    }

    // Keyboard extensions cannot call UIApplication.shared; walk the responder chain instead.
    private func openHostApp(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current is UIApplication, current.responds(to: selector) {
                typealias OpenFunction = @convention(c) (AnyObject, Selector, URL, [UIApplication.OpenExternalURLOptionsKey: Any], (@convention(block) (Bool) -> Void)?) -> Void
                let implementation = current.method(for: selector)
                let open = unsafeBitCast(implementation, to: OpenFunction.self)
                open(current, selector, url, [:], nil)
                return true
            }
            responder = current.next
        }
        return false
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.checkForResult()
            self?.refreshDictationUI()
        }
    }

    private func checkForResult() {
        if let result = SharedStorage.readResult(), !result.isEmpty,
           let age = SharedStorage.resultAge(), age < 300 {
            textDocumentProxy.insertText(result)
            SharedStorage.clearResult()
            dictationState = .idle
            awaitingSince = nil
            lastSpaceTap = nil
            updateAutoShift()
        }
    }

    private func refreshDictationUI() {
        if SharedStorage.isRecordingActive() {
            dictationState = .recording
            awaitingSince = nil
        } else if dictationState == .recording {
            // The host stopped on its own (for example from its own Stop button).
            dictationState = .transcribing
            awaitingSince = Date()
        } else if let since = awaitingSince {
            let limit: TimeInterval = dictationState == .opening ? 20 : 90
            if Date().timeIntervalSince(since) > limit {
                dictationState = .idle
                awaitingSince = nil
                SharedStorage.clearRecordingRequest()
            }
        }

        let fullAccessMessage = "Enable Allow Full Access in Settings"
        let readyMessage = "● Mic ready"
        if dictationState != .idle {
            statusLabel.text = ""
            statusLabel.textColor = .secondaryLabel
        } else if !hasFullAccess {
            statusLabel.text = fullAccessMessage
            statusLabel.textColor = .secondaryLabel
        } else if SharedStorage.isArmed() {
            // The app is keeping the microphone ready, so a tap on the mic starts dictating right away.
            statusLabel.text = readyMessage
            statusLabel.textColor = Palette.ready
        } else {
            if statusLabel.text == fullAccessMessage || statusLabel.text == readyMessage { statusLabel.text = "" }
            statusLabel.textColor = .secondaryLabel
        }

        switch dictationState {
        case .idle:
            setPanelVisible(false)
        case .opening:
            setPanelText(title: "Starting", subtitle: SharedStorage.isArmed() ? "Mic is ready" : "Opening dictation app")
            waveform.mode = .flat
            doneButton.alpha = 0.35
            cancelButton.alpha = 1
            setPanelVisible(true)
        case .recording:
            let started = SharedStorage.recordingStartedAt() ?? Date()
            let seconds = max(0, Int(Date().timeIntervalSince(started)))
            let clock = String(format: "%d:%02d", seconds / 60, seconds % 60)
            setPanelText(title: "Listening", subtitle: clock + " · " + (SharedStorage.inputName() ?? "iPhone Microphone"))
            waveform.mode = .listening
            doneButton.alpha = 1
            cancelButton.alpha = 1
            setPanelVisible(true)
        case .transcribing:
            if SharedStorage.isPolishing() {
                setPanelText(title: "Polishing", subtitle: "Tap ✕ to use the original text")
            } else {
                setPanelText(title: "Transcribing", subtitle: "Just a moment · tap ✕ to stop")
            }
            waveform.mode = .processing
            doneButton.alpha = 0
            cancelButton.alpha = 1
            setPanelVisible(true)
        }
    }

    private func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    private func setPanelText(title: String, subtitle: String) {
        let text = NSMutableAttributedString(
            string: title + "\n",
            attributes: [.font: roundedFont(size: 23, weight: .bold), .foregroundColor: UIColor.label]
        )
        text.append(NSAttributedString(
            string: subtitle,
            attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: UIColor.secondaryLabel]
        ))
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineSpacing = 4
        text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
        if listeningLabel.attributedText?.string != text.string { listeningLabel.attributedText = text }
    }

    private func setPanelVisible(_ visible: Bool) {
        if visible {
            popup.isHidden = true
            startDisplayLink()
        }
        guard visible != panelShown else { return }
        panelShown = visible

        if visible {
            dictationPanel.isHidden = false
            UIView.animate(withDuration: 0.2) { self.dictationPanel.alpha = 1 }
        } else {
            stopDisplayLink()
            UIView.animate(withDuration: 0.2, animations: { self.dictationPanel.alpha = 0 }) { _ in
                if !self.panelShown { self.dictationPanel.isHidden = true }
            }
        }
    }

    // MARK: Waveform animation

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(animationTick))
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func animationTick() {
        let now = CACurrentMediaTime()
        if waveform.mode == .listening, now - lastLevelPush >= 0.07 {
            lastLevelPush = now
            waveform.push(level: CGFloat(SharedStorage.recordingLevel()))
        }
        waveform.step(time: now)
    }
}
