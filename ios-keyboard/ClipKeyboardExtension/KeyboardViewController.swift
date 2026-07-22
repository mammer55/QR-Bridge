import UIKit

/// A custom iOS keyboard that shows the most recent entries from your
/// QR-Bridge "clips" table (Supabase). Tap a row and its full text is
/// inserted straight into whatever field you're typing in — no copy/paste.
///
/// Requires "Allow Full Access" (Settings → General → Keyboard → Keyboards →
/// Clip) so the extension is permitted to make network requests.
class KeyboardViewController: UIInputViewController {

    // MARK: - Config (these match your QR-Bridge web app's index.html)

    private let supaURL   = "https://owcukwsouruowulhohyq.supabase.co"
    private let supaAnon  = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im93Y3Vrd3NvdXJ1b3d1bGhvaHlxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE5ODgzNzMsImV4cCI6MjA4NzU2NDM3M30.3njPBQGD1LEQc-h_j4VhAhngNzEH2p2gpqtRplqan_E"
    private let fetchLimit = 12

    // Mint accent from the web app (#c2f6e5)
    private let accent = UIColor(red: 0.760, green: 0.965, blue: 0.898, alpha: 1)

    // MARK: - State

    private var clips: [String] = []

    // MARK: - Views

    private var stackView: UIStackView!
    private var statusLabel: UILabel!
    private var refreshButton: UIButton!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        fetchClips()
    }

    // MARK: - UI setup

    private func setupUI() {
        view.backgroundColor = UIColor(white: 0.95, alpha: 1)

        // Fixed keyboard height. Slightly below required so the system can
        // still adjust in edge cases without an unsatisfiable-constraint log.
        let height = view.heightAnchor.constraint(equalToConstant: 270)
        height.priority = .required - 1
        height.isActive = true

        let toolbar = makeToolbar()
        view.addSubview(toolbar)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .none
        view.addSubview(scroll)

        stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stackView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 46),

            scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])

        renderStatus("Loading…")
    }

    private func makeToolbar() -> UIView {
        let bar = UIView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.backgroundColor = accent

        // Globe — switch to the next keyboard.
        let globe = toolbarButton("🌐")
        globe.addTarget(self, action: #selector(nextKeyboard), for: .touchUpInside)

        let title = UILabel()
        title.text = "Universal Clipboard"
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = UIColor(white: 0.10, alpha: 1)
        title.translatesAutoresizingMaskIntoConstraints = false

        // Refresh — re-pull the latest clips.
        refreshButton = toolbarButton("↻")
        refreshButton.addTarget(self, action: #selector(handleRefresh), for: .touchUpInside)

        // Backspace — since this keyboard has no letter keys.
        let backspace = toolbarButton("⌫")
        backspace.addTarget(self, action: #selector(handleBackspace), for: .touchUpInside)

        [globe, title, refreshButton, backspace].forEach { bar.addSubview($0) }

        NSLayoutConstraint.activate([
            globe.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 6),
            globe.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            title.leadingAnchor.constraint(equalTo: globe.trailingAnchor, constant: 8),
            title.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            backspace.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -6),
            backspace.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            refreshButton.trailingAnchor.constraint(equalTo: backspace.leadingAnchor, constant: -2),
            refreshButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    private func toolbarButton(_ symbol: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(symbol, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 18)
        b.tintColor = UIColor(white: 0.10, alpha: 1)
        b.setTitleColor(UIColor(white: 0.10, alpha: 1), for: .normal)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 40).isActive = true
        b.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return b
    }

    // MARK: - Toolbar actions

    @objc private func nextKeyboard() { advanceToNextInputMode() }

    @objc private func handleBackspace() { textDocumentProxy.deleteBackward() }

    @objc private func handleRefresh() { fetchClips() }

    // MARK: - Data

    private func fetchClips() {
        guard hasFullAccess else {
            renderStatus("Enable “Allow Full Access” in Settings →\nGeneral → Keyboard → Keyboards → Clip")
            return
        }

        renderStatus("Loading…")
        spinRefresh(true)

        // Only non-expired clips, newest first — mirrors the web app's query.
        let now = ISO8601DateFormatter().string(from: Date())
        var comps = URLComponents(string: "\(supaURL)/rest/v1/clips")!
        comps.queryItems = [
            URLQueryItem(name: "select", value: "content,created_at"),
            URLQueryItem(name: "expires_at", value: "gt.\(now)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: String(fetchLimit)),
        ]

        var req = URLRequest(url: comps.url!)
        req.setValue(supaAnon, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(supaAnon)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self = self else { return }
            DispatchQueue.main.async { self.spinRefresh(false) }

            if let error = error {
                DispatchQueue.main.async { self.renderStatus("Network error:\n\(error.localizedDescription)") }
                return
            }
            guard
                let data = data,
                let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else {
                DispatchQueue.main.async { self.renderStatus("Couldn’t read clips.") }
                return
            }

            let texts = rows.compactMap { $0["content"] as? String }
                            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

            DispatchQueue.main.async {
                self.clips = texts
                self.renderClips()
            }
        }.resume()
    }

    // MARK: - Rendering

    private func renderStatus(_ message: String) {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        statusLabel = UILabel()
        statusLabel.text = message
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = UIColor(white: 0.45, alpha: 1)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 28),
            statusLabel.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -28),
            statusLabel.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -20),
        ])
        stackView.addArrangedSubview(wrap)
    }

    private func renderClips() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if clips.isEmpty {
            renderStatus("Nothing waiting.\nPush something from your PC.")
            return
        }

        for (index, text) in clips.enumerated() {
            stackView.addArrangedSubview(makeClipRow(text: text, index: index))
            stackView.addArrangedSubview(makeSeparator())
        }
    }

    private func makeClipRow(text: String, index: Int) -> UIButton {
        let b = UIButton(type: .system)
        b.tag = index
        b.contentHorizontalAlignment = .leading
        b.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        b.titleLabel?.font = .systemFont(ofSize: 15)
        b.titleLabel?.numberOfLines = 1
        b.titleLabel?.lineBreakMode = .byTruncatingTail
        b.setTitleColor(UIColor(white: 0.12, alpha: 1), for: .normal)
        b.backgroundColor = .white

        let preview = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        b.setTitle(preview, for: .normal)

        b.addTarget(self, action: #selector(insertClip(_:)), for: .touchUpInside)
        b.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return b
    }

    private func makeSeparator() -> UIView {
        let line = UIView()
        line.backgroundColor = UIColor(white: 0.88, alpha: 1)
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    // MARK: - Insert

    @objc private func insertClip(_ sender: UIButton) {
        guard sender.tag >= 0, sender.tag < clips.count else { return }
        textDocumentProxy.insertText(clips[sender.tag])

        // Brief flash so it's obvious which row fired.
        let original = sender.backgroundColor
        sender.backgroundColor = accent
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            sender.backgroundColor = original
        }
    }

    // MARK: - Helpers

    private func spinRefresh(_ on: Bool) {
        refreshButton.isEnabled = !on
        refreshButton.alpha = on ? 0.4 : 1.0
    }
}
