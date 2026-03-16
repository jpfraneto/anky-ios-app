import Combine
import SwiftUI

struct MeditationView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedDuration = 10
    @State private var readyResponse = GuidanceCacheStore.loadMeditationReady()
    @State private var isLoadingReady = false
    @State private var activeTimerTarget = 0
    @State private var remainingSeconds = 0
    @State private var sessionID: String?
    @State private var isTimerRunning = false
    @State private var activeGuidedSession: GuidanceSession?
    @State private var history: [MeditationHistoryItem] = []
    @State private var showHistory = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let poll = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    private let silentDurations = [5, 10, 15, 20, 30]

    var body: some View {
        ZStack {
            LinearGradient.ankyBackground
                .ignoresSafeArea()

            if isTimerRunning {
                activeTimerScreen
            } else {
                homeScreen
            }
        }
        .sheet(isPresented: $showHistory) {
            MeditationHistorySheet(history: history)
                .presentationDetents([.fraction(0.55), .fraction(0.92)])
                .presentationBackground(Color.ankyBlack)
        }
        .fullScreenCover(item: $activeGuidedSession, onDismiss: {
            Task {
                await refreshReady()
                await refreshHistory()
            }
        }) { session in
            GuidancePlaybackView(session: session, mode: .meditation)
                .environment(appState)
        }
        .task {
            await refreshReady()
            await refreshHistory()
        }
        .onReceive(tick) { _ in
            guard isTimerRunning else { return }
            if remainingSeconds > 0 {
                remainingSeconds -= 1
            } else {
                Task {
                    await finishSilentTimer(completed: true)
                }
            }
        }
        .onReceive(poll) { _ in
            guard !isTimerRunning, activeGuidedSession == nil else { return }
            Task {
                await refreshReady()
            }
        }
        .animation(AnkyTheme.transition, value: isTimerRunning)
    }

    private var homeScreen: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                Spacer(minLength: 84)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Sit")
                            .font(.custom("Righteous-Regular", size: 34))
                            .foregroundStyle(Color.ankyGold)

                        Spacer()

                        Button {
                            showHistory = true
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.ankyGold)
                                .frame(width: 42, height: 42)
                                .background(
                                    Circle()
                                        .fill(Color.ankyPanelRaised.opacity(0.94))
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Text("From writing.")
                        .font(.custom("Georgia", size: 18))
                        .foregroundStyle(Color.ankyInk.opacity(0.86))
                }

                generatedCard

                Spacer(minLength: 110)
            }
            .padding(.horizontal, 20)
        }
    }

    private var generatedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Automatic")
                .font(.custom("Righteous-Regular", size: 17))
                .foregroundStyle(Color.ankyInk)

            if isLoadingReady && readyResponse == nil {
                ProgressView()
                    .tint(Color.ankyGold)
            } else if let session = readySession {
                Text(session.title)
                    .font(.custom("Righteous-Regular", size: 22))
                    .foregroundStyle(Color.ankyGold)

                Text(durationLabel(seconds: session.durationSeconds))
                    .font(.custom("Georgia", size: 15))
                    .foregroundStyle(Color.ankyMuted)

                Button {
                    activeGuidedSession = session
                } label: {
                    Text("Begin")
                        .font(.custom("Righteous-Regular", size: 16))
                        .foregroundStyle(Color.ankyBlack)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.ankyGold)
                        )
                }
                .buttonStyle(.plain)
            } else {
                Text("Not ready.")
                    .font(.custom("Righteous-Regular", size: 22))
                    .foregroundStyle(Color.ankyGold)
            }
        }
        .padding(22)
        .background(cardBackground)
    }

    private var activeTimerScreen: some View {
        VStack(spacing: 36) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.ankyGold.opacity(0.86), .ankyAmber.opacity(0.28), .clear],
                            center: .center,
                            startRadius: 18,
                            endRadius: 160
                        )
                    )
                    .frame(width: 280, height: 280)
                    .scaleEffect(remainingSeconds.isMultiple(of: 8) ? 0.92 : 1)
                    .animation(.easeInOut(duration: 4.8).repeatForever(autoreverses: true), value: remainingSeconds)

                Circle()
                    .stroke(Color.ankyGold.opacity(0.24), lineWidth: 1)
                    .frame(width: 300, height: 300)
            }

            VStack(spacing: 10) {
                Text("Sit")
                    .font(.custom("Righteous-Regular", size: 30))
                    .foregroundStyle(Color.ankyInk)

                Text("No countdown. No chatter. Just stay.")
                    .font(.custom("Georgia-Italic", size: 18))
                    .foregroundStyle(Color.ankyMuted)
            }

            Button {
                Task {
                    await finishSilentTimer(completed: false)
                }
            } label: {
                Text("End sit")
                    .font(.custom("Righteous-Regular", size: 16))
                    .foregroundStyle(Color.ankyGold)
                    .padding(.horizontal, 18)
                    .frame(height: 48)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.ankyPanelRaised.opacity(0.94))
                    )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .onAppear {
            appState.activeExperience = .meditation
        }
        .onDisappear {
            appState.activeExperience = nil
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(Color.ankyPanelRaised.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.ankyGold.opacity(0.12), lineWidth: 1)
            )
    }

    private var readyValue: String {
        guard let readyResponse else { return "..." }
        return readyResponse.status == "ready" ? "Yes" : "Waiting"
    }

    private var readySession: GuidanceSession? {
        guard let readyResponse, readyResponse.status == "ready" else { return nil }
        return readyResponse.session
    }

    private func refreshReady() async {
        guard appState.isAuthenticated else { return }
        isLoadingReady = true
        defer { isLoadingReady = false }

        do {
            let response = try await AnkyAPI.shared.meditationReady()
            readyResponse = response
            GuidanceCacheStore.saveMeditationReady(response)
        } catch {
            readyResponse = GuidanceCacheStore.loadMeditationReady()
        }
    }

    private func refreshHistory() async {
        guard appState.isAuthenticated else { return }
        history = (try? await AnkyAPI.shared.meditationHistory()) ?? history
    }

    private func startSilentTimer() async {
        activeTimerTarget = selectedDuration * 60
        remainingSeconds = activeTimerTarget
        BellPlayer.shared.ring()

        if appState.isAuthenticated {
            let response = try? await AnkyAPI.shared.startMeditation(minutes: selectedDuration)
            sessionID = response?.sessionId
        }

        isTimerRunning = true
    }

    private func finishSilentTimer(completed: Bool) async {
        BellPlayer.shared.ring()
        isTimerRunning = false
        appState.activeExperience = nil

        if appState.isAuthenticated, let sessionID {
            _ = try? await AnkyAPI.shared.completeMeditation(
                MeditationCompleteRequest(
                    sessionId: sessionID,
                    actualSeconds: max(activeTimerTarget - remainingSeconds, 0),
                    completed: completed
                )
            )
            self.sessionID = nil
        }

        await refreshHistory()
    }

    private func durationLabel(seconds: Int) -> String {
        let minutes = seconds / 60
        return "\(minutes)m"
    }

    @ViewBuilder
    private func phaseSummary(_ phases: [GuidancePhase]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(phases.prefix(4)) { phase in
                    Text(phase.name)
                        .font(.custom("Righteous-Regular", size: 11))
                        .foregroundStyle(Color.ankyGold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.ankyPanel.opacity(0.9))
                        )
                }
            }
        }
    }
}

private struct MeditationHistorySheet: View {
    let history: [MeditationHistoryItem]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    ForEach(history) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(item.completed ? "Completed" : "Ended early")
                                    .font(.custom("Righteous-Regular", size: 15))
                                    .foregroundStyle(item.completed ? Color.ankyGold : Color.ankyMuted)

                                Spacer()

                                Text(item.createdAt.replacingOccurrences(of: "T", with: " ").prefix(16))
                                    .font(.custom("Georgia", size: 13))
                                    .foregroundStyle(Color.ankyMuted)
                            }

                            HStack(spacing: 14) {
                                Text("Target \(item.durationTarget / 60)m")
                                Text("Actual \((item.durationActual ?? 0) / 60)m")
                            }
                            .font(.custom("Georgia", size: 16))
                            .foregroundStyle(Color.ankyInk.opacity(0.88))
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.ankyPanelRaised.opacity(0.92))
                        )
                    }
                }
                .padding(20)
            }
            .background(Color.ankyBlack.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Meditation History")
                        .font(.custom("Righteous-Regular", size: 18))
                        .foregroundStyle(Color.ankyInk)
                }
            }
        }
        .presentationBackground(Color.ankyBlack)
    }
}

private struct MeditationStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.custom("Righteous-Regular", size: 24))
                .foregroundStyle(Color.ankyGold)

            Text(title.uppercased())
                .font(.custom("Righteous-Regular", size: 12))
                .foregroundStyle(Color.ankyMuted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.ankyPanel.opacity(0.95))
        )
    }
}
