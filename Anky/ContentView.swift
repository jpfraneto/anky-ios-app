import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.route {
            case .booting:
                SplashView()
            case .backupCeremony:
                BackupCeremonyView()
            case .recoveryImport:
                RecoveryImportView()
            case .locked:
                LockedNowShell()
            case .unlocked:
                UnlockedShellView()
            }
        }
        .background(Color.ankyBlack.ignoresSafeArea())
        .task {
            await appState.bootstrap()
        }
        .animation(AnkyTheme.transition, value: appState.route)
    }
}

private struct SplashView: View {
    var body: some View {
        ZStack {
            LinearGradient.ankyBackground
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.ankyGold.opacity(0.92), .ankyAmber.opacity(0.35), .clear],
                            center: .center,
                            startRadius: 8,
                            endRadius: 120
                        )
                    )
                    .frame(width: 170, height: 170)
                    .overlay(
                        Text("A")
                            .font(.custom("Righteous-Regular", size: 74))
                            .foregroundStyle(Color.ankyBlack)
                    )

                Text("Anky")
                    .font(.custom("Righteous-Regular", size: 34))
                    .foregroundStyle(Color.ankyInk)

                Text("Listening for what is true.")
                    .font(.custom("Georgia-Italic", size: 18))
                    .foregroundStyle(Color.ankyMuted)
            }
        }
    }
}

private struct BackupCeremonyView: View {
    @Environment(AppState.self) private var appState

    private let copy = AppCopy.current

    private var words: [String] {
        (appState.pendingMnemonic ?? "").split(separator: " ").map(String.init)
    }

    private var wordColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 12) {
                    Text(copy[.backupTitle])
                        .font(.custom("Righteous-Regular", size: 34))
                        .foregroundStyle(Color.ankyInk)

                    Text(copy[.backupBody])
                        .font(.custom("Georgia", size: 18))
                        .foregroundStyle(Color.ankyInk.opacity(0.88))
                        .lineSpacing(6)
                }

                if !words.isEmpty {
                    LazyVGrid(columns: wordColumns, spacing: 12) {
                        ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.custom("Righteous-Regular", size: 12))
                                    .foregroundStyle(Color.ankyGold)
                                    .frame(width: 28, alignment: .leading)

                                Text(word)
                                    .font(.custom("Georgia", size: 18))
                                    .foregroundStyle(Color.ankyInk)

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.ankyPanelRaised.opacity(0.94))
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    BackupWarning(text: copy[.backupLoseWarning])
                    BackupWarning(text: copy[.backupNoRecoveryWarning])
                    BackupWarning(text: copy[.backupNeverLeavesWarning])
                }

                Button {
                    Task {
                        await appState.completeBackupCeremony()
                    }
                } label: {
                    Text(copy[.backupSavedAction])
                        .font(.custom("Righteous-Regular", size: 18))
                        .foregroundStyle(Color.ankyBlack)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.ankyGold)
                        )
                }
                .buttonStyle(.plain)

                Button(copy[.restorePhraseAction]) {
                    appState.showRecoveryImport()
                }
                .font(.custom("Georgia", size: 17))
                .foregroundStyle(Color.ankyMuted)
                .buttonStyle(.plain)

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 28)
        }
        .background(LinearGradient.ankyBackground.ignoresSafeArea())
    }
}

private struct BackupWarning: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.custom("Georgia", size: 16))
            .foregroundStyle(Color.ankyInk.opacity(0.86))
            .lineSpacing(5)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.ankyPanel.opacity(0.94))
            )
    }
}

private struct RecoveryImportView: View {
    @Environment(AppState.self) private var appState
    @State private var phrase = ""
    @State private var isSubmitting = false

    private let copy = AppCopy.current

    var body: some View {
        ZStack {
            LinearGradient.ankyBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Spacer(minLength: 12)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(copy[.restoreTitle])
                            .font(.custom("Righteous-Regular", size: 34))
                            .foregroundStyle(Color.ankyInk)

                        Text(copy[.restoreBody])
                            .font(.custom("Georgia", size: 18))
                            .foregroundStyle(Color.ankyInk.opacity(0.88))
                            .lineSpacing(6)
                    }

                    ZStack(alignment: .topLeading) {
                        if phrase.isEmpty {
                            Text(copy[.restorePlaceholder])
                                .font(.custom("Georgia-Italic", size: 18))
                                .foregroundStyle(Color.ankyMuted)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 18)
                        }

                        TextEditor(text: $phrase)
                            .scrollContentBackground(.hidden)
                            .font(.custom("Georgia", size: 18))
                            .foregroundStyle(Color.ankyInk)
                            .frame(minHeight: 180)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.ankyPanelRaised.opacity(0.94))
                    )

                    if let authError = appState.authError {
                        Text(authError)
                            .font(.custom("Georgia", size: 16))
                            .foregroundStyle(Color.ankyAmber)
                    }

                    Button {
                        Task {
                            isSubmitting = true
                            defer { isSubmitting = false }
                            _ = await appState.importRecoveryPhrase(phrase)
                        }
                    } label: {
                        Text(isSubmitting ? "..." : copy[.restoreConfirmAction])
                            .font(.custom("Righteous-Regular", size: 18))
                            .foregroundStyle(Color.ankyBlack)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(Color.ankyGold)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                    .opacity(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting ? 0.62 : 1)

                    Button(copy[.restoreCancelAction]) {
                        appState.cancelRecoveryImport()
                    }
                    .font(.custom("Georgia", size: 17))
                    .foregroundStyle(Color.ankyMuted)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 28)
            }
        }
    }
}

private struct LockedNowShell: View {
    @Environment(AppState.self) private var appState

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

private struct UnlockedShellView: View {
    @Environment(AppState.self) private var appState

    private let copy = AppCopy.current

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient.ankyBackground
                .ignoresSafeArea()

            Group {
                switch appState.currentTab {
                case .now:
                    WritingsView()
                case .ankys:
                    PersistedAnkysView()
                case .seed:
                    SeedIdentityView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if appState.activeExperience == nil {
                VStack(spacing: 12) {
                    if appState.isOfflineMode || appState.syncMessage != nil {
                        SyncBadge(text: appState.isOfflineMode ? "offline" : (appState.syncMessage ?? ""))
                    }

                    FloatingTabBar(labels: [
                        .now: copy[.nowTab],
                        .ankys: copy[.ankysTab],
                        .seed: copy[.seedTab],
                    ])
                }
                .padding(.bottom, 18)
            }
        }
        .statusBarHidden(true)
    }
}

private struct SyncBadge: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.custom("Righteous-Regular", size: 11))
            .foregroundStyle(Color.ankyGold)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.ankyPanelRaised.opacity(0.92))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.ankyGold.opacity(0.16), lineWidth: 1)
                    )
            )
    }
}

private struct FloatingTabBar: View {
    @Environment(AppState.self) private var appState
    let labels: [AppState.Tab: String]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppState.Tab.allCases, id: \.rawValue) { tab in
                Button {
                    appState.currentTab = tab
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .semibold))

                        Text(labels[tab] ?? tab.label)
                            .font(.custom("Righteous-Regular", size: 11))
                    }
                    .foregroundStyle(appState.currentTab == tab ? Color.ankyGold : Color.ankyMuted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(appState.currentTab == tab ? Color.ankyPanelRaised.opacity(0.95) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.ankyPanel.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.ankyGold.opacity(0.12), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }
}

private struct PersistedAnkysView: View {
    @Environment(AppState.self) private var appState

    private let copy = AppCopy.current

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if !appState.pendingPersistedWrites.isEmpty {
                        pendingSection
                    }

                    if appState.cloudHistory.isEmpty {
                        emptyState
                    } else {
                        ForEach(appState.cloudHistory) { entry in
                            PersistedWritingRow(entry: entry)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.ankyBlack.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(copy[.persistedAnkysTitle])
                        .font(.custom("Righteous-Regular", size: 18))
                        .foregroundStyle(Color.ankyInk)
                }
            }
        }
        .task {
            await appState.refreshWritings()
        }
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(copy[.pendingSyncTitle])
                .font(.custom("Righteous-Regular", size: 16))
                .foregroundStyle(Color.ankyGold)

            Text(copy[.pendingSyncBody])
                .font(.custom("Georgia", size: 16))
                .foregroundStyle(Color.ankyInk.opacity(0.88))
                .lineSpacing(5)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.ankyPanelRaised.opacity(0.94))
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(copy[.noPersistedAnkysTitle])
                .font(.custom("Righteous-Regular", size: 24))
                .foregroundStyle(Color.ankyInk)

            Text(copy[.noPersistedAnkysBody])
                .font(.custom("Georgia", size: 17))
                .foregroundStyle(Color.ankyMuted)
                .lineSpacing(5)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.ankyPanelRaised.opacity(0.94))
        )
    }
}

private struct PersistedWritingRow: View {
    let entry: CachedWritingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.createdAtLabel)
                        .font(.custom("Righteous-Regular", size: 15))
                        .foregroundStyle(Color.ankyInk)

                    Text(entry.durationLabel)
                        .font(.custom("Georgia", size: 14))
                        .foregroundStyle(Color.ankyMuted)
                }

                Spacer()

                if entry.isAnky {
                    Text("ANKY")
                        .font(.custom("Righteous-Regular", size: 11))
                        .foregroundStyle(Color.ankyGold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.ankyPanel.opacity(0.95))
                        )
                }
            }

            Text(entry.content)
                .font(.custom("Georgia", size: 17))
                .foregroundStyle(Color.ankyInk.opacity(0.9))
                .lineSpacing(6)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.ankyPanelRaised.opacity(0.92))
        )
    }
}

private struct SeedIdentityView: View {
    @Environment(AppState.self) private var appState
    @State private var walletAddress = ""
    @State private var isConfirmingReboot = false

    private let copy = AppCopy.current

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(copy[.seedIdentityTitle])
                        .font(.custom("Righteous-Regular", size: 30))
                        .foregroundStyle(Color.ankyInk)

                    Text(copy[.rebootIdentityBody])
                        .font(.custom("Georgia", size: 17))
                        .foregroundStyle(Color.ankyMuted)
                        .lineSpacing(5)
                }

                identityCard(
                    title: copy[.walletLabel],
                    value: walletAddress.isEmpty ? "..." : walletAddress
                )

                HStack(spacing: 12) {
                    identityCard(
                        title: copy[.backupStatusLabel],
                        value: appState.hasBackedUpPhrase ? copy[.backedUpValue] : copy[.notBackedUpValue]
                    )

                    identityCard(
                        title: copy[.localIdentityLabel],
                        value: appState.hasLocalIdentity ? copy[.identityReadyValue] : copy[.identityMissingValue]
                    )
                }

                Button(role: .destructive) {
                    isConfirmingReboot = true
                } label: {
                    Text(copy[.rebootIdentityAction])
                        .font(.custom("Righteous-Regular", size: 18))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(.ankyAmber)
            }
            .padding(20)
        }
        .background(Color.ankyBlack.ignoresSafeArea())
        .confirmationDialog(copy[.rebootIdentityAction], isPresented: $isConfirmingReboot, titleVisibility: .visible) {
            Button(copy[.rebootIdentityAction], role: .destructive) {
                Task {
                    await appState.rebootIdentity()
                }
            }
        } message: {
            Text(copy[.rebootIdentityBody])
        }
        .task {
            walletAddress = appState.user?.walletAddress ?? (try? SeedIdentityManager.shared.walletAddress()) ?? ""
        }
    }

    private func identityCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.custom("Righteous-Regular", size: 12))
                .foregroundStyle(Color.ankyMuted)

            Text(value)
                .font(.custom("Georgia", size: 16))
                .foregroundStyle(Color.ankyInk)
                .lineLimit(3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.ankyPanelRaised.opacity(0.94))
        )
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
