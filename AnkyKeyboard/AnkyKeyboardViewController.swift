import UIKit
import SwiftUI

class AnkyKeyboardViewController: UIInputViewController {

    private var hostingController: UIHostingController<AnkyKeyboardView>?
    private var sessionTimer: Timer?
    private var currentSession: AnkySession = AnkySession()
    private var store = SharedSessionStore.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        setupKeyboardView()
        startSessionTimer()
    }

    private func setupKeyboardView() {
        let keyboardView = AnkyKeyboardView(
            onKeyPress: { [weak self] char in self?.handleKeyPress(char) },
            onDelete: { [weak self] in self?.handleDelete() },
            onFormatAndReplace: { [weak self] in self?.formatAndReplace() }
        )
        let hosting = UIHostingController(rootView: keyboardView)
        hostingController = hosting

        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let bundleID = Bundle.main.bundleIdentifier ?? ""
        var state = store.load()
        state.isExternalApp = !bundleID.contains("com.jpfraneto.Anky")
        store.save(state)
    }

    // MARK: - Timer

    private func startSessionTimer() {
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        var state = store.load()
        guard state.isActive else { return }

        let now = Date().timeIntervalSince1970
        let lastKeystroke = currentSession.keystrokes.last?.timestamp ?? now
        let streak = now - lastKeystroke
        let total = Date().timeIntervalSince(currentSession.startTime)

        state.streakSeconds = streak
        state.totalDuration = total
        state.phase = computePhase(streak: streak, total: total)

        if streak >= 8.0 {
            endSession(state: &state)
        } else {
            store.save(state)
        }
    }

    private func computePhase(streak: Double, total: Double) -> SessionPhase {
        if streak >= 8.0 { return .broken }
        if total < 15.0 { return .warming }
        if total > 60.0 && streak < 2.0 { return .transcendent }
        return .flow
    }

    // MARK: - Keystroke handling

    func handleKeyPress(_ character: String) {
        let now = Date().timeIntervalSince1970
        let previous = currentSession.keystrokes.last?.timestamp ?? now
        let delta = currentSession.keystrokes.isEmpty ? 0 : now - previous

        let keystroke = AnkyKeystroke(character: character, delta: delta, timestamp: now)
        currentSession.keystrokes.append(keystroke)

        textDocumentProxy.insertText(character)

        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()

        var state = store.load()
        if !state.isActive {
            currentSession = AnkySession()
            currentSession.startTime = Date()
            currentSession.id = UUID()
            state.isActive = true
            state.sessionID = currentSession.id
            state.keystrokeCount = 0
        }
        state.keystrokeCount += 1
        state.streakSeconds = 0
        store.save(state)
    }

    func handleDelete() {
        textDocumentProxy.deleteBackward()

        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }

    // MARK: - Session end

    private func endSession(state: inout AnkySessionState) {
        currentSession.endTime = Date()
        currentSession.phase = .broken

        let notif = UINotificationFeedbackGenerator()
        notif.notificationOccurred(.warning)

        state.isActive = false
        state.phase = .broken
        state.streakSeconds = 0

        saveSessionToDisk(currentSession)

        if state.isExternalApp {
            state.pendingFormattedText = nil
            Task {
                await requestFormatting()
            }
        }

        store.save(state)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            var idleState = self?.store.load() ?? AnkySessionState()
            idleState.phase = .idle
            idleState.streakSeconds = 0
            self?.store.save(idleState)
        }
    }

    // MARK: - Disk storage (append-only)

    private func saveSessionToDisk(_ session: AnkySession) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.suiteName
        ) else { return }

        let sessionsDir = containerURL.appendingPathComponent("sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        let fileURL = sessionsDir.appendingPathComponent("\(session.id.uuidString).txt")
        let content = session.toRawStream()
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)

        let metaURL = sessionsDir.appendingPathComponent("\(session.id.uuidString).json")
        if let data = try? JSONEncoder().encode(session) {
            try? data.write(to: metaURL)
        }
    }

    // MARK: - Claude formatting

    private func requestFormatting() async {
        let rawText = currentSession.text
        guard !rawText.isEmpty else { return }

        let apiKey = UserDefaults(suiteName: AppGroup.suiteName)?.string(forKey: AppGroup.claudeAPIKey) ?? ""
        guard !apiKey.isEmpty else { return }

        let prompt = buildFormattingPrompt(rawText: rawText)

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-sonnet-4-5-20250514",
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return }
        request.httpBody = httpBody

        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let firstBlock = content.first,
            let formatted = firstBlock["text"] as? String
        else { return }

        var state = store.load()
        state.pendingFormattedText = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
        store.save(state)
    }

    private func buildFormattingPrompt(rawText: String) -> String {
        return """
        You are formatting raw stream-of-consciousness writing into clean, postable text.

        Rules:
        - Preserve the writer's voice completely. Do not add what wasn't there.
        - Remove false starts and repetitions only if they are clearly errors, not intentional rhythm.
        - Fix obvious typos (remember: no backspace was available while writing).
        - Format for a short social post or note — clean paragraphs, no headers.
        - Return ONLY the formatted text. No preamble, no explanation, nothing else.

        Raw text:
        \(rawText)
        """
    }

    // MARK: - Replace text in host app

    func formatAndReplace() {
        let state = store.load()
        guard let formatted = state.pendingFormattedText else { return }

        let existing = textDocumentProxy.documentContextBeforeInput ?? ""
        for _ in existing {
            textDocumentProxy.deleteBackward()
        }

        textDocumentProxy.insertText(formatted)

        var newState = store.load()
        newState.pendingFormattedText = nil
        store.save(newState)
    }
}
