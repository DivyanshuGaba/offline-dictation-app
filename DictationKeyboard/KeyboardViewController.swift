import UIKit

class KeyboardViewController: UIInputViewController {
    private var micButton: UIButton!
    private var statusLabel: UILabel!
    private var pollTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        view.backgroundColor = UIColor.systemGray5

        statusLabel = UILabel()
        statusLabel.text = "Tap the mic to dictate"
        statusLabel.textAlignment = .center
        statusLabel.font = UIFont.systemFont(ofSize: 14)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        micButton = UIButton(type: .system)
        micButton.setTitle("Start Dictation", for: .normal)
        micButton.backgroundColor = UIColor.systemBlue
        micButton.setTitleColor(.white, for: .normal)
        micButton.layer.cornerRadius = 10
        micButton.translatesAutoresizingMaskIntoConstraints = false
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)

        let nextKeyboardButton = UIButton(type: .system)
        nextKeyboardButton.setTitle("Next Keyboard", for: .normal)
        nextKeyboardButton.translatesAutoresizingMaskIntoConstraints = false
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

        let backspaceButton = UIButton(type: .system)
        backspaceButton.setImage(UIImage(systemName: "delete.left.fill"), for: .normal)
        backspaceButton.tintColor = .label
        backspaceButton.translatesAutoresizingMaskIntoConstraints = false
        backspaceButton.addTarget(self, action: #selector(backspaceTouchDown), for: .touchDown)
        backspaceButton.addTarget(self, action: #selector(backspaceTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        view.addSubview(statusLabel)
        view.addSubview(micButton)
        view.addSubview(nextKeyboardButton)
        view.addSubview(backspaceButton)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            micButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            micButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            micButton.widthAnchor.constraint(equalToConstant: 200),
            micButton.heightAnchor.constraint(equalToConstant: 44),

            nextKeyboardButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            nextKeyboardButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),

            backspaceButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            backspaceButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            backspaceButton.widthAnchor.constraint(equalToConstant: 44),
            backspaceButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        let height = view.heightAnchor.constraint(equalToConstant: 120)
        height.priority = UILayoutPriority(999)
        height.isActive = true
    }

    private var backspaceTimer: Timer?
    private var backspaceStartTime: Date?

    @objc private func backspaceTouchDown() {
        textDocumentProxy.deleteBackward()
        backspaceStartTime = Date()
        backspaceTimer?.invalidate()
        backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.startFastDeleting()
        }
    }

    private func startFastDeleting() {
        backspaceTimer?.invalidate()
        backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            let elapsed = Date().timeIntervalSince(self.backspaceStartTime ?? Date())
            self.textDocumentProxy.deleteBackward()
            if elapsed > 2.0 {
                self.textDocumentProxy.deleteBackward()
            }
        }
    }

    @objc private func backspaceTouchUp() {
        backspaceTimer?.invalidate()
        backspaceTimer = nil
        backspaceStartTime = nil
    }
    
    @objc private func micTapped() {
        guard hasFullAccess else {
            statusLabel.text = "Enable Allow Full Access in Settings"
            return
        }

        SharedStorage.clearResult()
        SharedStorage.requestRecording()
        statusLabel.text = "Opening dictation app..."

        if let url = URL(string: "offlinedictation://record"), openHostApp(url) {
            startPolling()
        } else {
            statusLabel.text = "Could not open the app. Open it manually."
            startPolling()
        }
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
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForResult()
        }
    }

    private func checkForResult() {
        if let result = SharedStorage.readResult(), !result.isEmpty,
           let age = SharedStorage.resultAge(), age < 300 {
            textDocumentProxy.insertText(result)
            SharedStorage.clearResult()
            statusLabel.text = "Tap the mic to dictate"
            pollTimer?.invalidate()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkForResult()
        startPolling()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pollTimer?.invalidate()
    }
}
