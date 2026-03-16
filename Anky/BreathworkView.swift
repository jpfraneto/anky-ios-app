import Combine
import SwiftUI

struct BreathworkView: View {
    @Environment(AppState.self) private var appState

    @State private var readyResponse = GuidanceCacheStore.loadBreathworkReady()
    @State private var activeSession: GuidanceSession?
    @State private var history: [BreathworkHistoryItem] = []
    @State private var showHistory = false

    private let poll = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                Spacer(minLength: 84)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Breathe")
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
        .background(LinearGradient.ankyBackground.ignoresSafeArea())
        .sheet(isPresented: $showHistory) {
            BreathworkHistorySheet(history: history)
                .presentationDetents([.fraction(0.55), .fraction(0.92)])
                .presentationBackground(Color.ankyBlack)
        }
        .fullScreenCover(item: $activeSession, onDismiss: {
            Task {
                await loadReady()
                await loadHistory()
            }
        }) { session in
            GuidancePlaybackView(session: session, mode: .breathwork(style: session.style ?? readyResponse?.style))
                .environment(appState)
        }
        .task {
            await loadReady()
            await loadHistory()
        }
        .onReceive(poll) { _ in
            guard activeSession == nil else { return }
            Task {
                await loadReady()
            }
        }
        .animation(AnkyTheme.transition, value: readyResponse?.status)
    }

    private var generatedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Automatic")
                .font(.custom("Righteous-Regular", size: 17))
                .foregroundStyle(Color.ankyInk)

            if let session = readySession {
                Text(session.title)
                    .font(.custom("Righteous-Regular", size: 22))
                    .foregroundStyle(Color.ankyGold)

                Text(minutesLabel(for: session))
                    .font(.custom("Georgia", size: 15))
                    .foregroundStyle(Color.ankyMuted)

                Button {
                    activeSession = session
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
            } else if readyResponse == nil {
                ProgressView()
                    .tint(Color.ankyGold)
            } else {
                Text("Not ready.")
                    .font(.custom("Righteous-Regular", size: 22))
                    .foregroundStyle(Color.ankyGold)
            }
        }
        .padding(22)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(Color.ankyPanelRaised.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.ankyGold.opacity(0.12), lineWidth: 1)
            )
    }

    private var readySession: GuidanceSession? {
        guard let readyResponse, readyResponse.status == "ready" else { return nil }
        return readyResponse.session
    }

    private func minutesLabel(for session: GuidanceSession) -> String {
        "\(max(session.durationSeconds / 60, 1))m"
    }

    private func loadReady() async {
        guard appState.isAuthenticated else { return }

        do {
            let response = try await AnkyAPI.shared.breathworkReady()
            readyResponse = response
            GuidanceCacheStore.saveBreathworkReady(response)
        } catch {
            readyResponse = GuidanceCacheStore.loadBreathworkReady()
        }
    }

    private func loadHistory() async {
        guard appState.isAuthenticated else { return }
        if let response = try? await AnkyAPI.shared.breathworkHistory() {
            history = response.history
        }
    }
}

private struct BreathworkHistorySheet: View {
    let history: [BreathworkHistoryItem]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    ForEach(history) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(item.style.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.custom("Righteous-Regular", size: 18))
                                .foregroundStyle(Color.ankyGold)

                            Text(item.completedAt.replacingOccurrences(of: "T", with: " ").prefix(16))
                                .font(.custom("Georgia", size: 15))
                                .foregroundStyle(Color.ankyInk.opacity(0.88))
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                    Text("Breathwork History")
                        .font(.custom("Righteous-Regular", size: 18))
                        .foregroundStyle(Color.ankyInk)
                }
            }
        }
        .presentationBackground(Color.ankyBlack)
    }
}

private struct BreathingOrb: View {
    @State private var expanded = false

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [.ankyGold.opacity(0.9), .ankyAmber.opacity(0.36), .clear],
                    center: .center,
                    startRadius: 18,
                    endRadius: 160
                )
            )
            .frame(width: 240, height: 240)
            .scaleEffect(expanded ? 1 : 0.48)
            .animation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true), value: expanded)
            .frame(maxWidth: .infinity)
            .onAppear {
                expanded = true
            }
    }
}
