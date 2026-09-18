import UIKit

class KeyboardViewController: UIInputViewController {
    var micButton: UIButton!
    var statusLabel: UILabel!
    var pollTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    func setupUI() {
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

        view.addSubview(statusLabel)
        view.addSubview(micButton)
        view.addSubview(nextKeyboardButton)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            micButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            micButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            micButton.widthAnchor.constraint(equalToConstant: 200),
            micButton.heightAnchor.constraint(equalToConstant: 44),

            nextKeyboardButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            nextKeyboardButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8)
        ])

        view.heightAnchor.constraint(equalToConstant: 120).isActive = true
    }

    @objc func micTapped() {
        SharedStorage.clearResult()
        SharedStorage.requestRecording()
        statusLabel.text = "Opening dictation app..."

        if let url = URL(string: "offlinedictation://record") {
            var responder: UIResponder? = self
            while responder != nil {
                if let application = responder as? UIApplication {
                    application.perform(#selector(UIApplication.openURL(_:)), with: url)
                    break
                }
                responder = responder?.next
            }
        }

        startPolling()
    }

    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForResult()
        }
    }

    func checkForResult() {
        if let result = SharedStorage.readResult(), !result.isEmpty {
            textDocumentProxy.insertText(result)
            SharedStorage.clearResult()
            statusLabel.text = "Tap the mic to dictate"
            pollTimer?.invalidate()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pollTimer?.invalidate()
    }
}
