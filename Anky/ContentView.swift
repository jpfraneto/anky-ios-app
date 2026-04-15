import Combine
import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        AnkyChatView()
            .background(Color.black.ignoresSafeArea())
            .task {
                await appState.bootstrap()
            }
    }
}

// MARK: - Splash

private struct SplashView: View {
    @State private var scale: CGFloat = 1.2
    @State private var opacity: Double = 0
    @State private var glowRadius: CGFloat = 0

    private var dayKingdom: Kingdom { Kingdom.ankyverseDay() }

    var body: some View {
        ZStack {
            Color.ankyVoid
                .ignoresSafeArea()

            // Kingdom-colored portal glow
            RadialGradient(
                colors: [
                    dayKingdom.color.opacity(0.25),
                    dayKingdom.color.opacity(0.08),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 200
            )
            .scaleEffect(scale)
            .opacity(opacity)
            .ignoresSafeArea()

            VStack(spacing: 16) {
                AnkyMark(size: 48)
                    .opacity(0.8)
                    .shadow(color: dayKingdom.color.opacity(0.4), radius: glowRadius)

                Text(Kingdom.ankyverseTimeLabel())
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(dayKingdom.color.opacity(0.5))
                    .opacity(opacity)
            }
            .scaleEffect(scale)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) {
                scale = 1.0
                opacity = 1.0
                glowRadius = 20
            }
        }
    }
}

// MARK: - Recovery Import

private struct RecoveryImportView: View {
    @EnvironmentObject private var appState: AppState
    @State private var phrase = ""
    @State private var isSubmitting = false

    var body: some View {
        ZStack {
            Color.ankyVoid
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Spacer(minLength: 80)

                    Text("restaurar identidad")
                        .font(.ankyBody(24))
                        .foregroundStyle(Color.white)

                    Text("escribe tu frase de 12 palabras para recuperar tu cuenta.")
                        .font(.ankyBody(14))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .lineSpacing(4)

                    ZStack(alignment: .topLeading) {
                        if phrase.isEmpty {
                            Text("tu frase de recuperación...")
                                .font(.ankyBody(16))
                                .foregroundStyle(Color.white.opacity(0.15))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 18)
                        }

                        TextEditor(text: $phrase)
                            .scrollContentBackground(.hidden)
                            .font(.ankyBody(16))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .frame(minHeight: 160)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                    )

                    if let authError = appState.authError {
                        Text(authError)
                            .font(.ankyBody(13))
                            .foregroundStyle(Color(hex: "8b0000"))
                    }

                    Button {
                        Task {
                            isSubmitting = true
                            defer { isSubmitting = false }
                            _ = await appState.importRecoveryPhrase(phrase)
                        }
                    } label: {
                        Text(isSubmitting ? "..." : "restaurar")
                            .font(.ankyLabel(16, weight: .medium))
                            .foregroundStyle(Color.ankyVoid)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .fill(Color.white)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                    .opacity(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting ? 0.4 : 1)

                    Button("cancelar") {
                        appState.cancelRecoveryImport()
                    }
                    .font(.ankyBody(14))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
            }
        }
    }
}

// MARK: - Biometric Lock

private struct BiometricLockView: View {
    @EnvironmentObject private var biometricLock: BiometricLockManager

    var body: some View {
        ZStack {
            Color.ankyVoid.opacity(0.97)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                AnkyMark(size: 36)
                    .opacity(0.5)
                    .padding(.bottom, 8)

                Text("desbloquear anky")
                    .font(.ankyBody(20))
                    .foregroundStyle(Color.white)

                Button {
                    Task { _ = await biometricLock.unlockIfNeeded() }
                } label: {
                    Text(biometricLock.biometryLabel)
                        .font(.ankyLabel(14, weight: .medium))
                        .foregroundStyle(Color.ankyVoid)
                        .frame(width: 180, height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color.white)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Locked Shell

private struct LockedNowShell: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack(alignment: .topLeading) {
            WritingsView()

            if appState.isOfflineMode || appState.syncMessage != nil {
                SyncBadge(text: appState.isOfflineMode ? "offline" : (appState.syncMessage ?? ""))
                    .padding(.top, 20)
                    .padding(.leading, 20)
            }
        }
    }
}

// MARK: - Unlocked Shell

private struct UnlockedShellView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var biometricLock: BiometricLockManager

    @State private var childProfiles = ChildProfileStore.load()
    @State private var isShowingCreateChild = false
    @State private var activeChild: ChildProfile?
    @State private var isShowingChildPrompt = false

    private static let childPromptKey = "anky.child_world_prompt_shown"

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.ankyVoid
                .ignoresSafeArea()

            Group {
                switch appState.currentTab {
                case .stories:
                    HistoriasView()
                case .write:
                    HomeView()
                case .you:
                    TuView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if appState.activeExperience == nil {
                VStack(spacing: 0) {
                    if appState.isOfflineMode || appState.syncMessage != nil {
                        SyncBadge(text: appState.isOfflineMode ? "offline" : (appState.syncMessage ?? ""))
                            .padding(.bottom, 10)
                    }
                    BottomNav()
                }
            }
        }
        .sheet(isPresented: $isShowingCreateChild) {
            CreateChildView { _ in reloadChildProfiles() }
                .environmentObject(appState)
        }
        .fullScreenCover(item: $activeChild, onDismiss: { reloadChildProfiles() }) { child in
            ChildShellView(child: child)
                .environmentObject(appState)
                .environmentObject(biometricLock)
        }
        .alert("¿Tienes hijos? Puedes crear su mundo dentro de Anky.", isPresented: $isShowingChildPrompt) {
            Button("Crear ahora") { isShowingCreateChild = true }
            Button("Más tarde", role: .cancel) {}
        }
        .task {
            reloadChildProfiles()
            maybePresentChildPrompt()
        }
        .onChange(of: appState.hasUnlockedFullExperience) { _ in
            maybePresentChildPrompt()
        }
        .statusBarHidden(true)
    }

    private func reloadChildProfiles() {
        childProfiles = ChildProfileStore.load().sorted { $0.createdAt > $1.createdAt }
    }

    private func maybePresentChildPrompt() {
        guard appState.hasUnlockedFullExperience else { return }
        guard childProfiles.isEmpty else { return }
        guard !UserDefaults.standard.bool(forKey: Self.childPromptKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.childPromptKey)
        isShowingChildPrompt = true
    }
}

// MARK: - Screen 1 — Home (Center Tab)

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showWritingSession = false

    var body: some View {
        ZStack {
            Color.ankyVoid.ignoresSafeArea()

            VStack(spacing: 0) {
                // Upper 85% — tap target
                VStack {
                    Spacer()

                    Text(appState.prompt)
                        .font(.ankyBody(19))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                        .padding(.horizontal, 36)

                    // Faint vertical line
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 0.5, height: 40)
                        .padding(.top, 24)

                    Text("toca para escribir")
                        .font(.ankyBody(13))
                        .foregroundStyle(Color.white.opacity(0.15))
                        .padding(.top, 8)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    showWritingSession = true
                }

                // Bottom 15% reserved for nav bar
                Spacer()
                    .frame(height: AnkyTheme.navBarHeight + 20)
            }
        }
        .fullScreenCover(isPresented: $showWritingSession) {
            ActiveWritingSessionView()
                .environmentObject(appState)
        }
    }
}

// MARK: - Keyboard Observer (for legacy writing session)

class KeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0

    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self,
                      let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                    return
                }

                let screenBounds = UIScreen.main.bounds
                let overlap = screenBounds.intersection(frame).height
                self.height = max(overlap, 0)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ in CGFloat(0) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.height = $0 }
            .store(in: &cancellables)
    }
}

// MARK: - Screen 2 — Active Writing Session

struct ActiveWritingSessionView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = WritingFlowModel(prompt: PromptLibrary.currentPrompt())
    @StateObject private var keyboard = KeyboardObserver()
    var onSessionComplete: ((LocalWritingCapture) -> Void)?

    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    private let sessionGoal: TimeInterval = 480

    var body: some View {
        GeometryReader { geometry in
            let kbHeight = keyboard.height > 0
                ? keyboard.height - geometry.safeAreaInsets.bottom
                : 0

            ZStack {
                Color(hex: "0A0A0A").ignoresSafeArea()

                if model.phase == .complete {
                    postSession
                } else {
                    VStack(spacing: 0) {
                        // Idle bar — 3px, appears after 3s idle
                        idleBar

                        // Textarea — fills the screen
                        AnkyComposerTextView(
                            text: $model.text,
                            isFocused: $model.composerFocused,
                            placeholder: model.prompt,
                            font: UIFont(name: "Palatino-Roman", size: 18) ?? .systemFont(ofSize: 18),
                            textInsets: UIEdgeInsets(top: 8, left: 20, bottom: 20, right: 20),
                            onUserInput: { model.handleInput($0) }
                        )
                        .frame(maxHeight: .infinity)
                        .onTapGesture { model.beginFocus() }

                        // Progress bar + timer
                        VStack(spacing: 0) {
                            progressBar
                            timerLabel
                        }

                        // Keyboard spacer
                        Color.clear
                            .frame(height: kbHeight)
                            .animation(.easeOut(duration: 0.25), value: kbHeight)
                    }
                }
            }
        }
        .statusBarHidden(true)
        .onReceive(tick) { now in model.tick(at: now) }
        .onAppear {
            model.updatePrompt(appState.prompt)
            model.beginFocus()
        }
        .onChange(of: appState.prompt) { newValue in
            model.updatePrompt(newValue)
        }
        .onChange(of: model.phase) { newPhase in
            appState.activeExperience = newPhase == .writing ? .writing : nil
            appState.hasInProgressWriting = WritingSessionStore.hasDraft()
            if newPhase == .complete, let capture = model.completedCapture {
                onSessionComplete?(capture)
            }
        }
        .task(id: model.pendingCapture) {
            await model.submitFinishedCapture(appState: appState)
        }
    }

    // MARK: - Idle bar (top)

    private var idleBar: some View {
        GeometryReader { proxy in
            let idle = model.idleElapsed
            let visible = model.hasStarted && idle > 3
            let pct = min(idle / 8, 1)
            let color: Color = pct > 0.75
                ? Color(hex: "FF3B30")
                : pct > 0.5 ? Color(hex: "FF9500") : Color(hex: "FF6B35")

            ZStack(alignment: .leading) {
                if visible {
                    Rectangle()
                        .fill(color.opacity(0.8))
                        .frame(width: proxy.size.width * pct)
                        .animation(.linear(duration: 0.1), value: pct)
                }
            }
        }
        .frame(height: 3)
        .opacity(model.hasStarted && model.idleElapsed > 3 ? 1 : 0)
        .animation(.easeOut(duration: 0.4), value: model.idleElapsed > 3)
    }

    // MARK: - Progress bar (bottom)

    private var progressBar: some View {
        GeometryReader { proxy in
            let pct = model.hasStarted
                ? min(model.sessionElapsed / sessionGoal, 1)
                : 0

            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.04))

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "FF6B35"), Color(hex: "F7C948"),
                                Color(hex: "2EC4B6"), Color(hex: "3A86FF"),
                                Color(hex: "8338EC"), Color(hex: "FF006E")
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * pct)
                    .animation(.linear(duration: 0.1), value: pct)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 20)
    }

    // MARK: - Timer

    private var timerLabel: some View {
        let elapsed = model.sessionElapsed
        let remaining = max(sessionGoal - elapsed, 0)
        let display = model.hasStarted
            ? (elapsed < sessionGoal
                ? formatTime(remaining)
                : formatTime(elapsed))
            : "8:00"

        return Text(display)
            .font(.system(size: 14, design: .monospaced))
            .foregroundStyle(Color.white.opacity(model.hasStarted ? 0.4 : 0.15))
            .kerning(1)
            .padding(.vertical, 10)
            .padding(.bottom, 6)
    }

    // MARK: - Post session

    private var postSession: some View {
        VStack(spacing: 0) {
            // Stats header
            HStack {
                Text("\(model.wordCount) words")
                    .font(.ankyBody(14))
                    .foregroundStyle(Color.white.opacity(0.35))
                Spacer()
                Text(formatTime(model.sessionElapsed))
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5).padding(.horizontal, 20)

            // Raw writing
            ScrollView(showsIndicators: false) {
                Text(model.text)
                    .font(.ankyBody(17))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineSpacing(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
            }

            // Submission status
            if model.isSubmitting {
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: "FF6B35")).frame(width: 6, height: 6)
                    Text("anchoring")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: "FF6B35"))
                        .textCase(.uppercase)
                        .kerning(1)
                }
                .padding(.top, 12)
            }

            Spacer().frame(height: 16)

            // Actions
            Button {
                model.reset(for: appState.prompt)
            } label: {
                Text("write again")
                    .font(.ankyLabel(14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.04))
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            Button("close") { dismiss() }
                .font(.ankyBody(13))
                .foregroundStyle(Color.white.opacity(0.2))
                .buttonStyle(.plain)
                .padding(.top, 12)
                .padding(.bottom, 40)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

// MARK: - Screen 4 — Session Summary

struct SessionSummaryView: View {
    let model: WritingFlowModel
    let onReset: () -> Void
    let onDismiss: () -> Void
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer(minLength: 60)

                // Duration hero
                Text(formatDuration(model.sessionElapsed))
                    .font(.ankyDisplay(52))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .kerning(-1)

                Text("minutos escribiendo")
                    .font(.ankyBody(12))
                    .foregroundStyle(Color.white.opacity(0.2))
                    .kerning(1)
                    .padding(.top, 4)

                // Rhythm visualization
                RhythmVisualization(keystrokeDeltas: model.keystrokeDeltas)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                // Stats row
                HStack(spacing: 0) {
                    statCell(value: "\(model.wordCount)", label: "palabras")
                    statDivider
                    statCell(value: formatAvgPause(), label: "pausa media")
                    statDivider
                    statCell(value: flowLabel(), label: "estado final")
                }
                .padding(.vertical, 16)
                .padding(.top, 16)

                // Story card
                if let outcome = model.outcome {
                    storyCard(outcome: outcome)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                }

                // Swipe to seal (for anky-worthy sessions)
                if model.completedCapture?.qualifiesForAnky == true,
                   let capture = model.completedCapture {
                    SwipeToSealView(
                        kingdom: appState.kingdom,
                        sessionId: capture.sessionId,
                        onSealed: {
                            appState.incrementCompletedSessions()
                            onDismiss()
                        },
                        onKeepPrivate: {
                            onDismiss()
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 32)
                }

                // Actions
                Button {
                    onReset()
                } label: {
                    Text("escribir de nuevo")
                        .font(.ankyLabel(14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Button("cerrar") {
                    onDismiss()
                }
                .font(.ankyBody(13))
                .foregroundStyle(Color.white.opacity(0.25))
                .buttonStyle(.plain)
                .padding(.top, 12)

                Spacer(minLength: 100)
            }
        }
        .background(Color(hex: "0a0a0f").ignoresSafeArea())
    }

    private func storyCard(outcome: WritingOutcome) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                // Thumbnail placeholder
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [.orange, .yellow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: "4a8a4a"))
                            .frame(width: 6, height: 6)

                        switch outcome.delivery {
                        case .synced:
                            Text("historia lista")
                                .font(.ankyBody(11))
                                .foregroundStyle(Color(hex: "4a8a4a"))
                        case .queued:
                            Text("en cola")
                                .font(.ankyBody(11))
                                .foregroundStyle(Color(hex: "c4845a"))
                        case .failed:
                            Text("guardada localmente")
                                .font(.ankyBody(11))
                                .foregroundStyle(Color.white.opacity(0.4))
                        }
                    }

                    Text("sesión completada")
                        .font(.ankyLabel(12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))

                    Text(formatDuration(model.sessionElapsed))
                        .font(.ankyBody(10))
                        .foregroundStyle(Color.white.opacity(0.35))
                }

                Spacer()
            }

            if outcome.delivery == .synced {
                HStack(spacing: 8) {
                    Button {
                        appState.currentTab = .stories
                        onDismiss()
                    } label: {
                        Text("escuchar")
                            .font(.ankyLabel(13, weight: .medium))
                            .foregroundStyle(Color.ankyVoid)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        // Share action
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.ankyBody(18))
                .foregroundStyle(Color.white.opacity(0.7))

            Text(label)
                .font(.ankyBody(9))
                .foregroundStyle(Color.white.opacity(0.2))
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 0.5, height: 32)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formatAvgPause() -> String {
        guard !model.keystrokeDeltas.isEmpty else { return "—" }
        let avg = model.keystrokeDeltas.reduce(0, +) / Double(model.keystrokeDeltas.count) / 1000
        return String(format: "%.1fs", avg)
    }

    private func flowLabel() -> String {
        if model.completedCapture?.qualifiesForAnky == true { return "flow" }
        return "parcial"
    }
}

// MARK: - Screen 5 — Historias Tab

struct HistoriasView: View {
    @EnvironmentObject private var appState: AppState

    @State private var stories: [Cuentacuentos] = []
    @State private var activeStory: Cuentacuentos?
    @State private var isLoading = true
    @State private var selectedFilter: String = "todas"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("historias")
                    .font(.ankyLabel(18, weight: .medium))
                    .foregroundStyle(Color.white)
                    .padding(.top, 60)

                // Filter pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterPill("todas", isSelected: selectedFilter == "todas") {
                            selectedFilter = "todas"
                        }
                    }
                }

                if isLoading {
                    VStack {
                        Spacer(minLength: 80)
                        ProgressView()
                            .tint(Color.white.opacity(0.3))
                            .frame(maxWidth: .infinity)
                        Spacer()
                    }
                } else if stories.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("aún no hay historias")
                            .font(.ankyBody(16))
                            .foregroundStyle(Color.white.opacity(0.5))

                        Text("escribe 8 minutos. una historia nace de lo que sale.")
                            .font(.ankyBody(13))
                            .foregroundStyle(Color.white.opacity(0.25))
                            .lineSpacing(4)
                    }
                    .padding(.top, 40)
                } else {
                    // Story list
                    VStack(spacing: 10) {
                        ForEach(stories) { story in
                            ZStack(alignment: .topTrailing) {
                                StoryCardView(
                                    story: story,
                                    downloadState: story.played ? .downloaded : .notDownloaded,
                                    onPlay: { activeStory = story }
                                )

                                if UserSettings.shared.isStoryCompleted(story.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.green)
                                        .padding(8)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(Color.ankyVoid.ignoresSafeArea())
        .fullScreenCover(item: $activeStory) { story in
            StoryPlayerView(story: story) { completed in
                guard completed else { return }
                try? await AnkyAPI.shared.completeCuentacuentos(id: story.id)
                await refreshStories()
            }
        }
        .task {
            await refreshStories()
        }
    }

    private func filterPill(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.ankyBody(12))
                .foregroundStyle(Color.white.opacity(isSelected ? 0.85 : 0.4))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
                        .overlay(
                            Capsule()
                                .stroke(
                                    isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.08),
                                    lineWidth: 0.5
                                )
                        )
                )
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func refreshStories() async {
        guard appState.isAuthenticated else {
            isLoading = false
            return
        }

        do {
            async let ready = AnkyAPI.shared.getCuentacuentosReady(childId: nil)
            async let history = AnkyAPI.shared.getCuentacuentosHistory(childId: nil)

            let readyStory = try await ready
            let pastStories = try await history

            var all = pastStories
            if let readyStory, !all.contains(where: { $0.id == readyStory.id }) {
                all.insert(readyStory, at: 0)
            }

            stories = all.sorted { $0.generatedAt > $1.generatedAt }
        } catch {}

        isLoading = false
    }
}

// MARK: - Screen 6 — Tú Tab (The Mirror)

struct TuView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isConfirmingReboot = false
    @State private var isShowingKeyboardSetup = false
    @State private var isShowingSettings = false
    @State private var itemsResponse: UserItemsResponse?
    @State private var isLoadingItems = true
    @State private var selectedItem: KingdomItem?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.user?.displayName ?? "tú")
                        .font(.ankyLabel(18, weight: .medium))
                        .foregroundStyle(Color.white)

                    HStack(spacing: 8) {
                        Text("\(appState.user?.totalWritings ?? 0) sesiones")
                            .font(.ankyBody(11))
                            .foregroundStyle(Color.white.opacity(0.25))

                        if appState.hasMintedFirstNFT {
                            Text("mirror minted")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(appState.kingdom.color.opacity(0.6))
                        }
                    }

                    Text("\(appState.kingdom.name) · \(appState.kingdom.chakra)")
                        .font(.system(size: 12, weight: .light, design: .monospaced))
                        .foregroundStyle(appState.kingdom.color.opacity(0.5))
                        .padding(.top, 2)
                }
                .padding(.top, 60)

                // Kingdom Items Grid
                kingdomItemsSection

                // Stats row
                HStack(spacing: 0) {
                    statCard(value: "\(appState.totalCompletedSessions)", label: "sessions")
                    Spacer().frame(width: 8)
                    statCard(value: formatAvgSession(), label: "avg session")
                    Spacer().frame(width: 8)
                    statCard(value: "—", label: "streak")
                }

                // Settings
                VStack(spacing: 10) {
                    Button { isShowingSettings = true } label: {
                        settingsRow(icon: "gearshape", title: "ajustes", subtitle: "idioma, tamaño de texto")
                    }
                    .buttonStyle(.plain)

                    Button { isShowingKeyboardSetup = true } label: {
                        settingsRow(icon: "keyboard", title: "teclado anky", subtitle: "instalar o configurar")
                    }
                    .buttonStyle(.plain)

                    settingsRow(
                        icon: "key.horizontal",
                        title: "identidad",
                        subtitle: appState.hasBackedUpPhrase ? "asegurada" : "pendiente"
                    )

                    Button(role: .destructive) {
                        isConfirmingReboot = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 14))
                            Text("reiniciar identidad")
                                .font(.ankyBody(13))
                            Spacer()
                        }
                        .foregroundStyle(Color(hex: "8b0000").opacity(0.7))
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.04))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(Color.ankyVoid.ignoresSafeArea())
        .task { await loadItems() }
        .sheet(item: $selectedItem) { item in
            KingdomItemDetailSheet(item: item)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $isShowingKeyboardSetup) {
            KeyboardSetupView()
        }
        .sheet(isPresented: $isShowingSettings) {
            UserSettingsView()
                .presentationDetents([.medium])
                .sheetStyleBackground(Color.ankyVoid)
        }
        .confirmationDialog("reiniciar identidad", isPresented: $isConfirmingReboot, titleVisibility: .visible) {
            Button("reiniciar", role: .destructive) {
                Task { await appState.rebootIdentity() }
            }
        } message: {
            Text("Esto borra tu identidad local y todas las sesiones guardadas. No se puede deshacer.")
        }
    }

    // MARK: - Kingdom Items

    @ViewBuilder
    private var kingdomItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("your 8 items")
                .font(.ankyLabel(14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.6))

            if isLoadingItems {
                HStack {
                    Spacer()
                    ProgressView().tint(Color.white.opacity(0.3))
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if let items = itemsResponse?.items, !items.isEmpty {
                // 2×4 grid of items
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(items) { item in
                        KingdomItemCard(item: item)
                            .onTapGesture { selectedItem = item }
                    }
                }

                if itemsResponse?.source == "derived" {
                    Text("items evolve as you write more")
                        .font(.ankyBody(11))
                        .foregroundStyle(Color.white.opacity(0.2))
                } else if itemsResponse?.source == "mirror" {
                    Text("sealed on-chain")
                        .font(.system(size: 11, weight: .light, design: .monospaced))
                        .foregroundStyle(appState.kingdom.color.opacity(0.4))
                }
            } else {
                Text(itemsResponse?.message ?? "write your first anky to discover your items")
                    .font(.ankyBody(13))
                    .foregroundStyle(Color.white.opacity(0.25))
                    .lineSpacing(4)
                    .padding(.vertical, 16)
            }
        }
    }

    private func loadItems() async {
        isLoadingItems = true
        defer { isLoadingItems = false }

        do {
            itemsResponse = try await AnkyAPI.shared.getUserItems()
            if let items = itemsResponse?.items {
                appState.mirrorItems = items
            }
        } catch {
            // Silent failure — items are not critical
        }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.ankyBody(16))
                .foregroundStyle(Color.white.opacity(0.6))

            Text(label)
                .font(.ankyBody(9))
                .foregroundStyle(Color.white.opacity(0.2))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    private func settingsRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.4))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.ankyBody(13))
                    .foregroundStyle(Color.white.opacity(0.7))
                Text(subtitle)
                    .font(.ankyBody(11))
                    .foregroundStyle(Color.white.opacity(0.25))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.2))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func formatAvgSession() -> String {
        guard let total = appState.user?.totalWritings, total > 0 else { return "—" }
        return "~5m"
    }
}

// MARK: - User Settings View

struct UserSettingsView: View {
    @ObservedObject private var settings = UserSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Language
                Section {
                    Menu {
                        ForEach(StoryLanguage.available) { lang in
                            Button {
                                settings.preferredLanguageId = lang.id
                            } label: {
                                HStack {
                                    Text(lang.label)
                                    if lang.id == settings.preferredLanguageId {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("idioma")
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(settings.preferredStoryLanguage.label)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("idioma y voz")
                } footer: {
                    Text("el idioma predeterminado para la reproducción de historias y la grabación de voz")
                }

                // Font size
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("tamaño de texto")
                                .font(.system(size: 14))
                            Spacer()
                            Text("\(Int(settings.fontSize))px")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.fontSize, in: 14...28, step: 1)
                            .tint(.orange)
                    }
                    .padding(.vertical, 4)

                    // Preview
                    Text("así se ve tu texto cuando escribes")
                        .font(.custom("Georgia", size: settings.fontSize))
                        .lineSpacing(8)
                        .foregroundStyle(.primary.opacity(0.7))
                        .padding(.vertical, 4)
                } header: {
                    Text("escritura")
                }
            }
            .navigationTitle("ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("listo") { dismiss() }
                        .fontWeight(.medium)
                }
            }
        }
    }
}

// MARK: - Screen 7 — Story Player

struct StoryPlayerView: View {
    let story: Cuentacuentos
    let onFinish: ((Bool) async -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @StateObject private var model: StoryPlaybackModel
    @State private var showLanguagePicker = false
    @State private var showVoiceSettings = false
    @State private var showShareSheet = false
    @State private var showVoicesSheet = false
    @StateObject private var voicesModel: StoryVoicesModel

    init(story: Cuentacuentos, onFinish: ((Bool) async -> Void)? = nil) {
        let wordCount = story.content
            .split { $0.isWhitespace || $0.isNewline }
            .count
        self.story = story
        self.onFinish = onFinish
        _model = StateObject(wrappedValue: StoryPlaybackModel(
            session: GuidanceSession(
                id: story.id,
                title: story.title,
                description: story.content,
                durationSeconds: max(story.guidancePhases.reduce(0) { $0 + $1.durationSeconds }, 1),
                phases: story.guidancePhases
            ),
            storyId: story.id,
            onFinish: onFinish
        ))
        _voicesModel = StateObject(wrappedValue: StoryVoicesModel(
            storyId: story.id,
            storyWordCount: wordCount
        ))
    }

    private var currentPhaseImageUrl: URL? {
        guard model.currentPhaseIndex < model.session.phases.count,
              let urlString = model.session.phases[model.currentPhaseIndex].imageUrl,
              let url = URL(string: urlString) else { return nil }
        return url
    }

    private var allPhaseImageUrls: [URL] {
        model.session.phases.compactMap { $0.imageUrl.flatMap { URL(string: $0) } }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            fullBleedImage
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topControls
                    .padding(.top, 52)
                    .padding(.horizontal, 20)

                imageDots
                    .padding(.top, 16)

                Spacer()

                // Narration text overlay — scrollable, current phase highlighted
                if !model.subtitle.isEmpty && !model.isComplete {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(Array(model.session.phases.enumerated()), id: \.offset) { index, phase in
                                    Text(phase.translatedNarration(for: model.selectedLanguage.id))
                                        .font(.custom("Georgia", size: UserSettings.shared.fontSize))
                                        .lineSpacing(8)
                                        .foregroundStyle(
                                            index == model.currentPhaseIndex
                                                ? Color.white
                                                : index < model.currentPhaseIndex
                                                    ? Color.white.opacity(0.3)
                                                    : Color.white.opacity(0.15)
                                        )
                                        .shadow(color: .black.opacity(0.8), radius: 4, x: 0, y: 2)
                                        .id("phase-\(index)")
                                }
                            }
                            .padding(.horizontal, 28)
                        }
                        .frame(maxHeight: 200)
                        .mask(
                            LinearGradient(
                                colors: [.clear, .black, .black, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .padding(.bottom, 8)
                        .onChange(of: model.currentPhaseIndex) { newIndex in
                            withAnimation(.easeOut(duration: 0.4)) {
                                proxy.scrollTo("phase-\(newIndex)", anchor: .center)
                            }
                        }
                    }
                }

                bottomOverlay
            }

            if showLanguagePicker {
                languagePicker
            }
        }
        .statusBarHidden(true)
        .task { model.start() }
        .task { await prefetchAllImages() }
        .sheet(isPresented: $showVoiceSettings) {
            VoiceSettingsSheet(model: model)
                .presentationDetents([.fraction(0.65)])
                .sheetStyle(cornerRadius: 24, material: true)
        }
        .sheet(isPresented: $showShareSheet) {
            AnkyShareSheet(story: story)
                .presentationDetents([.medium])
                .sheetStyleBackground(Color.ankyVoid)
        }
        .sheet(isPresented: $showVoicesSheet) {
            NavigationStack {
                ScrollView {
                    StoryVoicesSection(
                        model: voicesModel,
                        storyTitle: story.title,
                        storyText: story.content,
                        language: model.selectedLanguage.id
                    )
                    .onAppear { voicesModel.currentUserId = appState.user?.userId }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .background(Color.ankyVoid.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("voices")
                            .font(.ankyLabel(15, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showVoicesSheet = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.6))
                        }
                    }
                }
            }
            .presentationDetents([.large])
            .sheetStyleBackground(Color.ankyVoid)
        }
    }

    private func prefetchAllImages() async {
        for url in allPhaseImageUrls {
            Task.detached(priority: .background) {
                let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
                _ = try? await URLSession.shared.data(for: request)
            }
        }
    }

    private var fullBleedImage: some View {
        Group {
            if let url = currentPhaseImageUrl {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                            .transition(.opacity.animation(.easeIn(duration: 0.3)))
                    case .failure:
                        warmGradient
                    case .empty:
                        ZStack {
                            warmGradient
                            ProgressView()
                                .tint(.white.opacity(0.5))
                        }
                    @unknown default:
                        warmGradient
                    }
                }
            } else {
                warmGradient
            }
        }
        .animation(.easeInOut(duration: 0.8), value: model.currentPhaseIndex)
    }

    private var warmGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.12, green: 0.07, blue: 0.22),
                Color(red: 0.06, green: 0.04, blue: 0.14)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var topControls: some View {
        HStack(spacing: 8) {
            // Language pill
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showLanguagePicker.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 11))
                    Text(model.selectedLanguage.id.uppercased())
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.4))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)

            // Voice settings gear
            Button {
                showVoiceSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            // Voices
            Button {
                showVoicesSheet = true
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)

            // Share pill
            Button {
                showShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)

            // Close
            Button {
                Task { await model.finishEarly() }
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var imageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<model.session.phases.count, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(i == model.currentPhaseIndex ? 0.9 : 0.3))
                    .frame(width: 5, height: 5)
            }
        }
    }

    private var bottomOverlay: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.7), Color.black.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 100)

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.session.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.95))

                    Text(model.totalLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Progress bar
                VStack(spacing: 6) {
                    HStack {
                        Text(model.elapsedLabel)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.4))
                        Spacer()
                        Text(model.totalLabel)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 3)
                            Capsule()
                                .fill(Color.white.opacity(0.75))
                                .frame(width: max(proxy.size.width * model.progress, 10), height: 3)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 10, height: 10)
                                .offset(x: max(proxy.size.width * model.progress - 5, 0))
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let fraction = max(0, min(1, value.location.x / proxy.size.width))
                                    model.seekTo(fraction: fraction)
                                }
                        )
                    }
                    .frame(height: 10)
                }

                // Playback controls
                HStack(spacing: 36) {
                    Button {
                        model.skipToPrevious()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.togglePause()
                    } label: {
                        Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(width: 56, height: 56)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.12))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                                    )
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.skipToNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .background(Color.black.opacity(0.95))
        }
    }

    private var languagePicker: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showLanguagePicker = false
                    }
                }

            VStack(spacing: 0) {
                Text("language")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.white)
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                ScrollView(showsIndicators: true) {
                    VStack(spacing: 0) {
                        ForEach(StoryLanguage.available) { lang in
                            Button {
                                model.changeLanguage(to: lang)
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    showLanguagePicker = false
                                }
                            } label: {
                                HStack {
                                    Text(lang.label)
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color.white.opacity(0.8))
                                    Spacer()
                                    if lang.id == model.selectedLanguage.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(Color.white.opacity(0.6))
                                    }
                                }
                                .padding(.horizontal, 20)
                                .frame(height: 42)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
            .frame(maxWidth: 280)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: "0a0a0f").opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
        .transition(.opacity)
    }
}

// MARK: - Voice Settings Sheet

struct VoiceSettingsSheet: View {
    @ObservedObject var model: StoryPlaybackModel
    @Environment(\.dismiss) private var dismiss
    @State private var localRate: Float
    @State private var localPitch: Float
    @State private var localVoiceId: String?

    init(model: StoryPlaybackModel) {
        self.model = model
        _localRate = State(initialValue: model.speechRate)
        _localPitch = State(initialValue: model.speechPitch)
        _localVoiceId = State(initialValue: model.selectedVoiceId)
    }

    var body: some View {
        NavigationStack {
            List {
                // Speed
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("speed")
                                .font(.system(size: 14))
                            Spacer()
                            Text(speedLabel)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $localRate, in: 0.1...0.65, step: 0.01)
                            .tint(.orange)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("playback")
                }

                // Pitch
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("pitch")
                                .font(.system(size: 14))
                            Spacer()
                            Text(pitchLabel)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $localPitch, in: 0.5...2.0, step: 0.05)
                            .tint(.orange)
                    }
                    .padding(.vertical, 4)
                }

                // Voice picker
                Section {
                    if model.availableVoices.isEmpty {
                        Text("no voices available for this language")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.availableVoices) { voice in
                            Button {
                                localVoiceId = voice.id
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(voice.name)
                                            .font(.system(size: 14))
                                            .foregroundStyle(.primary)
                                        Text("\(voice.language) · \(voice.qualityLabel)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if localVoiceId == voice.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("voice (\(model.availableVoices.count) available)")
                }
            }
            .navigationTitle("voice settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("apply") {
                        model.speechRate = localRate
                        model.speechPitch = localPitch
                        model.selectedVoiceId = localVoiceId
                        model.applyVoiceSettings()
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var speedLabel: String {
        let pct = Int((localRate / 0.38) * 100)
        return "\(pct)%"
    }

    private var pitchLabel: String {
        String(format: "%.2f", localPitch)
    }
}

// MARK: - Sync Badge

private struct SyncBadge: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.ankyBody(11))
            .foregroundStyle(Color.white.opacity(0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - Legacy Compatibility

// WritingsView now routes to active writing session via HomeView
struct WritingsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = WritingFlowModel(prompt: PromptLibrary.currentPrompt())
    @State private var keyboardOverlap: CGFloat = 0

    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        let copy = WritingExperienceStrings.current

        ZStack {
            Color.ankyVoid.ignoresSafeArea()

            switch model.phase {
            case .landing, .writing, .paused:
                composeScreen(copy: copy)
            case .complete:
                completionScreen(copy: copy)
            }

            // Hidden text view
            AnkyComposerTextView(
                text: $model.text,
                isFocused: $model.composerFocused,
                isVisuallyHidden: true,
                onUserInput: { model.handleInput($0) }
            )
            .frame(width: 1, height: 1)
            .opacity(0)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .onReceive(tick) { now in model.tick(at: now) }
        .onAppear {
            model.updatePrompt(appState.prompt)
            if model.hasStarted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    model.beginFocus()
                }
            }
        }
        .onChange(of: appState.prompt) { newValue in model.updatePrompt(newValue) }
        .onChange(of: model.phase) { newPhase in
            appState.activeExperience = (newPhase == .writing || newPhase == .paused) ? .writing : nil
            appState.hasInProgressWriting = WritingSessionStore.hasDraft()
        }
        .task(id: model.pendingCapture) {
            await model.submitFinishedCapture(appState: appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            updateKeyboardOverlap(from: note)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.22)) { keyboardOverlap = 0 }
        }
        .animation(.easeInOut(duration: 0.6), value: model.phase)
    }

    private func composeScreen(copy: WritingExperienceStrings) -> some View {
        GeometryReader { proxy in
            let bottomInset = max(keyboardOverlap, proxy.safeAreaInsets.bottom) + 12
            let width = proxy.size.width

            ZStack(alignment: .bottom) {
                if model.hasStarted {
                    // Text stream
                    ScrollView(showsIndicators: false) {
                        Text(model.text)
                            .font(.ankyBody(16))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .lineSpacing(10)
                            .padding(.horizontal, 28)
                            .padding(.top, 200)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [Color.ankyVoid, Color.ankyVoid.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 120)
                        .allowsHitTesting(false)
                    }

                    // Metrics
                    VStack(spacing: 8) {
                        CommandCenterBarView(
                            phase: .flow,
                            streakSeconds: model.idleElapsed,
                            totalDuration: model.sessionElapsed,
                            livesRemaining: model.livesRemaining,
                            totalLives: WritingFlowModel.totalLives,
                            idleDrainProgress: model.idleDrainProgress
                        )
                    }
                    .padding(.bottom, bottomInset)
                } else {
                    // Landing
                    VStack(spacing: 0) {
                        Spacer()
                        Text(model.prompt)
                            .font(.ankyBody(19))
                            .foregroundStyle(Color.white)
                            .multilineTextAlignment(.center)
                            .lineSpacing(6)
                            .padding(.horizontal, 36)

                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 0.5, height: 40)
                            .padding(.top, 24)

                        Text("toca para escribir")
                            .font(.ankyBody(13))
                            .foregroundStyle(Color.white.opacity(0.15))
                            .padding(.top, 8)
                        Spacer()
                    }
                    .frame(width: width, height: proxy.size.height)
                }
            }
            .frame(width: width, height: proxy.size.height)
            .contentShape(Rectangle())
            .onTapGesture { model.beginFocus() }
        }
    }

    private func completionScreen(copy: WritingExperienceStrings) -> some View {
        VStack(spacing: 0) {
            Spacer()

            Text(formatDuration(model.sessionElapsed))
                .font(.ankyDisplay(52))
                .foregroundStyle(Color.white.opacity(0.85))
                .kerning(-1)

            Text("minutos escribiendo")
                .font(.ankyBody(12))
                .foregroundStyle(Color.white.opacity(0.2))
                .kerning(1)
                .padding(.top, 4)

            Spacer().frame(height: 48)

            if model.isSubmitting || (model.completedCapture?.qualifiesForAnky == true && model.outcome == nil) {
                HStack(spacing: 8) {
                    ProgressView().tint(Color.white.opacity(0.3))
                    Text("procesando...")
                        .font(.ankyBody(12))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
            }

            Spacer()

            Button {
                model.reset(for: appState.prompt)
            } label: {
                Text("otra vez")
                    .font(.ankyLabel(14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.04))
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func updateKeyboardOverlap(from note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let screenMaxY = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .screen.bounds.maxY
            ?? UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.screen.bounds.maxY }
                .first
            ?? frame.maxY
        let overlap = max(0, screenMaxY - frame.minY)
        withAnimation(.easeInOut(duration: 0.22)) { keyboardOverlap = overlap }
    }
}

// Keep old StoryCard and StoriesLibraryView for backward compat
struct StoriesLibraryView: View {
    var body: some View { HistoriasView() }
}

struct StoryCard: View {
    let story: Cuentacuentos
    let onPlay: () -> Void

    var body: some View {
        StoryCardView(story: story, downloadState: story.played ? .downloaded : .notDownloaded, onPlay: onPlay)
    }
}

struct YouView: View {
    var body: some View { TuView() }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppState())
            .environmentObject(BiometricLockManager.shared)
    }
}
