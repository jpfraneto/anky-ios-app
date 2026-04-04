import SwiftUI

struct DebugLandingView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var biometricLock: BiometricLockManager

    @State private var activeFlow: DebugFlow?
    @State private var showPostMortem = false
    @State private var identityRefresh = UUID()
    @State private var generateState: ActionState = .idle
    @State private var restartState: ActionState = .idle
    @State private var clearWelcomeState: ActionState = .idle

    var body: some View {
        ZStack {
            LinearGradient.ankyBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    header
                    identityCard
                    flowButtonsGrid
                    tabButtonsRow
                    dangerZone
                    Spacer(minLength: 120)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }

            VStack {
                Spacer()
                debugNavBar
            }
        }
        .fullScreenCover(item: $activeFlow) { flow in
            DebugFlowContainer(flow: flow, dismiss: { activeFlow = nil })
                .environmentObject(appState)
                .environmentObject(biometricLock)
        }
        .alert("Post-Mortem", isPresented: $showPostMortem) {
            Button("OK") {}
        } message: {
            Text("The post-mortem flow will appear here. This is where a user's digital legacy is handled after they pass.")
        }
        .task {
            await appState.bootstrap()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Text("hello world")
                .font(.anky(36))
                .foregroundStyle(Color.ankyInk)

            Text("Anky Debug Console")
                .font(.anky(14))
                .foregroundStyle(Color.ankyMuted)

            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                .font(.anky(11))
                .foregroundStyle(Color.ankyMuted.opacity(0.6))
        }
        .padding(.top, 12)
    }

    // MARK: - Identity Card

    private var identityCard: some View {
        let status = SeedIdentityManager.shared.status()
        let wallet = (try? SeedIdentityManager.shared.walletAddress()) ?? ""
        let phrase = status.pendingMnemonic
            ?? KeychainHelper.get("anky.seed.pending-mnemonic", synchronizable: true)
            ?? ""

        return VStack(alignment: .leading, spacing: 12) {
            Label("Seed Identity", systemImage: "key.horizontal")
                .font(.anky(14))
                .foregroundStyle(Color.ankyGold)

            if status.hasIdentity {
                Text(wallet)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.ankyInk)
                    .textSelection(.enabled)

                if !phrase.isEmpty {
                    Divider().background(Color.ankyGold.opacity(0.15))

                    Text(phrase)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.ankyInk.opacity(0.8))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                } else {
                    Text("phrase backed up & cleared")
                        .font(.anky(12))
                        .foregroundStyle(Color.ankyMuted)
                }
            } else {
                Text("No identity found")
                    .font(.anky(16))
                    .foregroundStyle(Color.ankyAmber)

                ActionButtonView(
                    state: generateState,
                    idleLabel: "Generate Identity",
                    workingLabel: "Generating...",
                    doneLabel: "Identity Created",
                    errorPrefix: "Failed"
                ) {
                    generateState = .working
                    do {
                        _ = try SeedIdentityManager.shared.generateIdentity()
                        await appState.bootstrap()
                        identityRefresh = UUID()
                        generateState = .done
                    } catch {
                        generateState = .error(error.localizedDescription)
                    }
                }
            }

            HStack(spacing: 8) {
                statusPill("Identity", active: status.hasIdentity)
                statusPill("Backup", active: status.hasCompletedBackup)
                statusPill("Auth", active: appState.isAuthenticated)
                statusPill("Unlocked", active: appState.hasUnlockedFullExperience)
            }
        }
        .id(identityRefresh)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.ankyPanelRaised.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.ankyGold.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func statusPill(_ label: String, active: Bool) -> some View {
        Text(label)
            .font(.anky(10))
            .foregroundStyle(active ? Color.ankyBlack : Color.ankyMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(active ? Color.ankyGold : Color.ankyPanel)
            )
    }

    // MARK: - Flow Buttons

    private var flowButtonsGrid: some View {
        VStack(spacing: 14) {
            Text("Flows")
                .font(.anky(13))
                .foregroundStyle(Color.ankyMuted)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14),
            ], spacing: 14) {
                glowButton("Onboarding", icon: "hand.wave", color: .ankyPurple) {
                    activeFlow = .onboarding
                }
                glowButton("Write", icon: "pencil.line", color: .ankyGold) {
                    activeFlow = .write
                }
                glowButton("Send Anky", icon: "paperplane.fill", color: .ankyAmber) {
                    activeFlow = .sendAnky
                }
                glowButton("Story", icon: "book.fill", color: .ankyPurpleSoft) {
                    activeFlow = .listenStory
                }
                glowButton("Profile", icon: "person.fill", color: .ankyGold) {
                    activeFlow = .profile
                }
                glowButton("Kids", icon: "figure.and.child.holdinghands", color: .ankyAmber) {
                    activeFlow = .childWorld
                }
                glowButton("Lock Screen", icon: "lock.fill", color: .ankyMuted) {
                    activeFlow = .lockScreen
                }
                glowButton("Post-Mortem", icon: "heart.slash", color: Color(red: 0.8, green: 0.2, blue: 0.2)) {
                    showPostMortem = true
                }
            }
        }
    }

    private func glowButton(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [color.opacity(0.5), color.opacity(0.15), .clear],
                                center: .center,
                                startRadius: 4,
                                endRadius: 36
                            )
                        )
                        .frame(width: 56, height: 56)

                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(color.opacity(0.5), lineWidth: 1)
                        )

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(color)
                }

                Text(label)
                    .font(.anky(11))
                    .foregroundStyle(Color.ankyInk.opacity(0.75))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab Buttons (match real nav bar)

    private var tabButtonsRow: some View {
        VStack(spacing: 10) {
            Text("Tabs (as in production)")
                .font(.anky(13))
                .foregroundStyle(Color.ankyMuted)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                tabButton("Stories", icon: "book.fill") { activeFlow = .tabStories }
                tabButton("Write", icon: "pencil.line") { activeFlow = .tabWrite }
                tabButton("You", icon: "person.fill") { activeFlow = .tabYou }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.ankyPanel.opacity(0.9))
            )
        }
    }

    private func tabButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                Text(label)
                    .font(.anky(10))
            }
            .foregroundStyle(Color.ankyMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Danger Zone

    private var dangerZone: some View {
        VStack(spacing: 12) {
            Text("Danger Zone")
                .font(.anky(13))
                .foregroundStyle(Color.ankyAmber)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Mirror state info
            VStack(alignment: .leading, spacing: 6) {
                Text("Mirror State: \(appState.mirrorState.rawValue) (\(mirrorStateName))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.6))
                Text("Kingdom: \(appState.kingdom.name)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(appState.kingdom.color)
                Text("Sessions: \(appState.totalCompletedSessions)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
            )

            ActionButtonView(
                state: restartState,
                idleLabel: "RESTART FRESH",
                workingLabel: "Deleting everything...",
                doneLabel: "Fresh start ready",
                errorPrefix: "Failed",
                style: .danger
            ) {
                restartState = .working
                await appState.rebootIdentity()
                identityRefresh = UUID()
                restartState = .done
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                restartState = .idle
            }

            ActionButtonView(
                state: clearWelcomeState,
                idleLabel: "Clear Welcome State",
                workingLabel: "Clearing...",
                doneLabel: "Welcome state cleared",
                errorPrefix: "Failed",
                style: .danger
            ) {
                clearWelcomeState = .working
                UserDefaults.standard.set(false, forKey: "anky.has_completed_welcome")
                UserDefaults.standard.set(false, forKey: "anky.has_unlocked_full_experience")
                UserDefaults.standard.set(0, forKey: "anky.mirror_state")
                try? await Task.sleep(nanoseconds: 300_000_000)
                clearWelcomeState = .done
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                clearWelcomeState = .idle
            }
        }
    }

    private var mirrorStateName: String {
        switch appState.mirrorState {
        case .virgin: return "virgin"
        case .seedRevealed: return "seed revealed"
        case .seedConfirmed: return "seed confirmed"
        case .firstSessionInProgress: return "first session"
        case .mirrorDissolved: return "mirror dissolved"
        case .firstMintComplete: return "first mint"
        case .returningUser: return "returning"
        }
    }

    @available(*, deprecated, message: "Use ActionButtonView instead")
    private func dangerButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 14, weight: .medium))
                Text(label)
                    .font(.anky(14))
                Spacer()
            }
            .foregroundStyle(Color.ankyAmber)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.ankyPanelRaised.opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.ankyAmber.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Debug Nav Bar

    private var debugNavBar: some View {
        HStack(spacing: 0) {
            navBarButton(.stories) { activeFlow = .tabStories }
            navBarButton(.write) { activeFlow = .tabWrite }
            navBarButton(.you) { activeFlow = .tabYou }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            Color.ankyPanel.opacity(0.96)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.ankyGold.opacity(0.08))
                        .frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func navBarButton(_ tab: AppState.Tab, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: .medium))
                Text(tab.label)
                    .font(.anky(10))
            }
            .foregroundStyle(Color.ankyMuted)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Enum

enum DebugFlow: String, Identifiable {
    case onboarding
    case write
    case sendAnky
    case listenStory
    case profile
    case childWorld
    case lockScreen
    case tabStories
    case tabWrite
    case tabYou

    var id: String { rawValue }
}

// MARK: - Flow Container

private struct DebugFlowContainer: View {
    let flow: DebugFlow
    let dismiss: () -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var biometricLock: BiometricLockManager

    private var hidesCloseButton: Bool {
        switch flow {
        case .write, .tabWrite:
            return true
        default:
            return false
        }
    }

    var body: some View {
        if hidesCloseButton {
            // Write flows manage their own safe areas and keyboard
            flowContent
        } else {
            ZStack(alignment: .topTrailing) {
                flowContent

                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.ankyMuted)
                        .padding(16)
                }
                .buttonStyle(.plain)
            }
            .background(Color.ankyBlack.ignoresSafeArea())
        }
    }

    @ViewBuilder
    private var flowContent: some View {
        switch flow {
        case .onboarding:
            DebugOnboardingWrapper(dismiss: dismiss)

        case .write, .tabWrite:
            WritingsView()

        case .sendAnky:
            DebugSendAnkyView(dismiss: dismiss)

        case .listenStory:
            DebugStoryPicker(dismiss: dismiss)

        case .profile, .tabYou:
            DebugYouWrapper()

        case .childWorld:
            DebugChildWorldWrapper()

        case .lockScreen:
            DebugLockedShell()

        case .tabStories:
            DebugStoriesWrapper()
        }
    }
}

// MARK: - Onboarding Wrapper (debug preview — mirrors real WelcomeFlowView)

private struct DebugOnboardingWrapper: View {
    let dismiss: () -> Void
    @State private var stepIndex = 0

    private let copy = AppCopy.current
    private let imageNames = ["onboarding_write", "onboarding_protect", "onboarding_seed", "onboarding_sunrise"]

    private var bodyTexts: [String] {
        [
            copy[.welcomeIntroBody],
            copy[.welcomeBiometryBody],
            copy[.welcomeKeychainBody],
            copy[.welcomeNotificationsBody],
        ]
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ZStack {
                    Color.ankyBlack

                    Image(imageNames[stepIndex])
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height * 0.55)
                        .clipped()
                        .overlay(alignment: .bottom) {
                            LinearGradient(
                                colors: [.clear, .ankyBlack],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 120)
                        }
                }
                .frame(height: proxy.size.height * 0.55)

                VStack(spacing: 0) {
                    Spacer(minLength: 12)

                    Text(bodyTexts[stepIndex])
                        .font(.anky(24))
                        .foregroundStyle(Color.ankyInk)
                        .lineSpacing(6)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 28)

                    Spacer(minLength: 12)

                    HStack(spacing: 10) {
                        ForEach(0..<4, id: \.self) { index in
                            Circle()
                                .fill(index <= stepIndex ? Color.ankyGold : Color.white.opacity(0.12))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.bottom, 20)

                    Button {
                        if stepIndex < 3 {
                            stepIndex += 1
                        } else {
                            dismiss()
                        }
                    } label: {
                        Text(stepIndex < 3 ? copy[.welcomeContinueAction] : "Done")
                            .font(.anky(18))
                            .foregroundStyle(Color.ankyBlack)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(Color.ankyGold)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 22)
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom, 8) + 16)
                }
                .frame(maxWidth: .infinity)
                .background(Color.ankyBlack)
            }
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.4), value: stepIndex)
    }
}

// MARK: - Send Anky (simulate processing)

private struct DebugSendAnkyView: View {
    let dismiss: () -> Void
    @EnvironmentObject private var appState: AppState
    @State private var phase: SendPhase = .ready
    @State private var errorDetail: String?

    enum SendPhase {
        case ready, submitting, success, failed
    }

    var body: some View {
        ZStack {
            LinearGradient.ankyBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    Spacer(minLength: 80)

                    switch phase {
                    case .ready:
                        readyView
                    case .submitting:
                        submittingView
                    case .success:
                        successView
                    case .failed:
                        failedView
                    }

                    Spacer(minLength: 40)
                }
                .padding(22)
            }
        }
    }

    private var readyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.ankyGold)

            Text("Simulate Anky Submission")
                .font(.anky(22))
                .foregroundStyle(Color.ankyInk)

            Text("Auth: \(appState.isAuthenticated ? "yes" : "NO")")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(appState.isAuthenticated ? Color.ankyGold : Color.ankyAmber)

            Button {
                phase = .submitting
                Task { await simulateSubmission(fullSession: true) }
            } label: {
                Text("Send 8-min Anky (1267 words)")
                    .font(.anky(16))
                    .foregroundStyle(Color.ankyBlack)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.ankyGold)
                    )
            }
            .buttonStyle(.plain)

            Button {
                phase = .submitting
                Task { await simulateSubmission(fullSession: false) }
            } label: {
                Text("Send 4-min Writing (partial)")
                    .font(.anky(16))
                    .foregroundStyle(Color.ankyInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.ankyPanelRaised)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(Color.ankyGold.opacity(0.3), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var submittingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(Color.ankyGold)
                .scaleEffect(1.5)

            Text("An anky is forming.")
                .font(.anky(22))
                .foregroundStyle(Color.ankyInk)

            Text("The writing is already safe. I am sending the real anky now.")
                .font(.anky(15))
                .foregroundStyle(Color.ankyMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
        }
    }

    private var successView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.ankyGold)

            Text("An anky was born.")
                .font(.anky(22))
                .foregroundStyle(Color.ankyInk)

            Text("The page held long enough. Sit with what it opened.")
                .font(.anky(15))
                .foregroundStyle(Color.ankyMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(5)

            Button { dismiss() } label: {
                Text("Done")
                    .font(.anky(18))
                    .foregroundStyle(Color.ankyBlack)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.ankyGold)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var failedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.ankyAmber)

            Text("Submission failed")
                .font(.anky(22))
                .foregroundStyle(Color.ankyInk)

            if let errorDetail {
                Text(errorDetail)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.ankyAmber)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.ankyPanel)
                    )
            }

            Button {
                phase = .ready
                errorDetail = nil
            } label: {
                Text("Back")
                    .font(.anky(18))
                    .foregroundStyle(Color.ankyBlack)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.ankyAmber)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // 2026-03-12 · 14m 30s · 1267 words
    private static let sampleAnkyText = """
yesterday was one of the most brutal experiences that i have had in my whole life. i was playing with mila and ema on the afternoon. having fun. then cleme, mila's cousin came to the house out of nowhere. he knocked the door. interrupted out game, and then they started playing together. i felt that something had been taken away from me because i was enjkoying a lot that moment of intimacy between the three of us. but of course she wanted to play with his cousin. and then they made a big mess on the living room. i accepted it amnd told them that they had to clean afterwards and organize everythigng. they agreed. then they kept playing and i was with ema. and at 6pm laura (the cousing of mila that has her same age - 4, sister of cleme) came and they started playing together the three of thenm. at 6:27 i was on the kitchen and they were on mila's room (the mess was still on the living room) andn i grabbed my phone and made up as if my cousin (htheir mother) had called me and i said ok i will send them to your home! (they live next door) and before tell them to order and clean up. so i told them that their mother had called and that they had to go. so that they had to orgnaninze. and they started organizing amnd mila went wild. gcrazy. she got really angry and started yelling and shiuting and crying. and then she started hitting me. and on that hitting me. y grabbed her arm. i notince in myself an unosconcisou drive to use my strength in order to make her feel pain, so that she could understand whthat i didn't want her to continue hitting me. i didn't want to hit me anymore, and i could,bt tell her it in any other way that making her feel pain. so i grabbed her arm and told her stop hitting me please. and then she kinda stopped but then cojtinue making a big bmess. while laura and cleme kept organizing and she was just shouting. and i started organizing a bit while that was happening, without giving her attention . and ema was all this time on the floor on the playmat looking at all this. and then i told laura and cleme to go away and then mila was still shotugin and calling for her mom and i was telling her to pleas e stop and organize and order the mess and then i told her that she had not respected the agreement we had and that the next time that they came ohome i wouldn't allow them to enter because she was not capable of keeping her agreements. i todld her then that i didn't want her to talk to me so to please stop. and i was very angry at her. and i feel how much in all that time i didn;t give her the attention that she was requesting me. ididn't give anything of what whse needed from me. and i feel very miserable about it tbh. trying to integrated it as much as possible but this can't happen again. i CANT use my strength to do somethng to her EVER AGAIN. and then she went to bed with nacha and she was crying all the time because her arm hurt. she was saying to nacha that her arm hurted a lot. and it was because iof what i grabbed her. i dont realy know if she was really in aipain phsyically or emotionally and it was all a projection of how much pain she felt because of this whole situation, but then she fall asleep and sewe were talking with nacha and she was telling me that THIS ASNCANT HAPPEN AGAIN and then mila worke up again crying because she was on pain. and i was outside her room listening to this whole thing feeling minmense pain inside me cbecause of hearing my daughter pain that was produced by me and my incapacidty for estalblishing healthy boundaries. this is the limit. rock bottom. today she is not going to school because yesterday was an intense thday. and i could see while nacha was putting her to sleep that i was thinking on what would other people think if mila told hethem that her father hit her or grabberd her and meade her feel pain. and i was worried abiout those kind of wconsequences. and then i realized that the thing to worry about was happening NOW. not after. NOW. hearing my daughter in pain because of me WAS IT. that's the nmost painful thing. not what other people would think of me because ifof what i idid. but what my dauthter was going through NOW> . as we were there. so it was really brutak tbh. it was really intense emotionally. and no w wim at home and i woke aup aearly and they are sleeping and i hosnestly don't know what to do. where to put myself. what doto do with y life now a biart bitg part of me wants to go away and hide forever. but another part of me wasnts to be here for them to know wthat im sorry. but wnacha told me that this is what i do every time that something that like this happens. say im sorry it probably wont happen again and then it happesns again, and it needs to STOP. but it is so cufucking hard. so incredibly fucking hard. and i don't know how to deal with it. and i was thinking yeah ogo to therapy and go to this and go to that. but that's all hding the fact that IT CANT STOP sorry IT WICANT HAPPEN AGAIN. and the next eimte that wsomething like that happens on which im in a situation on which she is hitting me i need to be able to see myself and recognize that it is not helpful to hit her or make her hardm. i was not able to calpture myself yesterday on that moment. nbut next time I NEED TO BE ABLE TO. like my dlife fedependts on it. and i see the cunoncscous pattern on not taking care of what i have. of not valuing what i have. its been like that throughout my life. i have so many things that i cant aembrade embrace them and love tham and take thcare of them because i take them for granted. and tdoing tht with my daughter is like the upmost expression of that. and it ca'tn't be. but i don't knw different. im stuck in this way of acting and being like this. and the more i dig into it the mosre i try to get out of it abut then something like this happens and it is all like going back in time and i don't know what the fuck to do in order to deal with it. i know that IT CANT HAPPEN AGAIN. i know that i need to be clear about that inside me. i know that this moment needs to be the turnign point. it is not I WILL DO MY BEST FOR IT TO NOT HAPPEN AGAIN. bthat's bullshing. cant be. IT WONT HAPPEN AGAIN. NEVER. MY DAUGHTERS ARE SACRED. MY FAMILY IS ASACRED. I AM SACRED. AND I NEED TO HONOR MY WORD. IN EVERY SPACE OF MY AWARENESS . HONOR YOUR WORD, AS IF YOUR LIFE DEPENDED ON IT. BECAUSE IT DEPENDS ON IT. EVERYTHING IS DOWNSTREAM OF THAT.
"""

    private func simulateSubmission(fullSession: Bool) async {
        let fullText = Self.sampleAnkyText

        // For 4-min partial: take roughly the first half
        let text: String
        let duration: Double
        if fullSession {
            text = fullText
            duration = 870
        } else {
            let words = fullText.split(separator: " ")
            let halfWords = words.prefix(words.count / 2)
            text = halfWords.joined(separator: " ")
            duration = 240
        }

        print("[DebugSend] Starting submission — fullSession=\(fullSession), words=\(text.split(separator: " ").count), duration=\(duration)")
        print("[DebugSend] Auth status: \(appState.authStatus), isAuthenticated=\(appState.isAuthenticated)")

        guard await appState.ensureAuthenticatedForWrite() else {
            let msg = "ensureAuthenticatedForWrite() returned false. authStatus=\(appState.authStatus), authError=\(appState.authError ?? "nil"), offline=\(appState.isOfflineMode)"
            print("[DebugSend] FAIL: \(msg)")
            errorDetail = msg
            phase = .failed
            return
        }

        print("[DebugSend] Authenticated. Sending to API...")

        let request = MobileWriteRequest(
            text: text,
            duration: duration,
            sessionId: UUID().uuidString,
            keystrokeDeltas: nil,
            isCheckpoint: nil
        )

        do {
            let response = try await AnkyAPI.shared.submitWriting(request)
            print("[DebugSend] SUCCESS: persisted=\(response.persisted), isAnky=\(response.isAnky), ankyId=\(response.ankyId ?? "nil")")
            let capture = LocalWritingCapture(
                sessionId: request.sessionId ?? UUID().uuidString,
                prompt: appState.prompt,
                text: text,
                duration: duration,
                wordCount: text.split(separator: " ").count,
                keystrokeDeltas: [],
                finishedAt: Date(),
                estimatedFlowScore: 0.75
            )
            appState.recordWriting(capture, response: response, syncState: .synced)
            phase = .success
        } catch {
            let msg: String
            if let ankyErr = error as? AnkyError {
                msg = "AnkyError: \(ankyErr)"
            } else {
                msg = "\(type(of: error)): \(error.localizedDescription)"
            }
            print("[DebugSend] FAIL: \(msg)")
            errorDetail = msg
            phase = .failed
        }
    }
}

// MARK: - Story Picker

private struct DebugStoryPicker: View {
    let dismiss: () -> Void
    @EnvironmentObject private var appState: AppState
    @State private var stories: [Cuentacuentos] = []
    @State private var activeSession: IdentifiableSession?

    private struct IdentifiableSession: Identifiable {
        let id: String
        let session: GuidanceSession
    }
    @State private var isLoading = true
    @State private var fetchError: String?

    var body: some View {
        ZStack {
            LinearGradient.ankyBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Stories")
                        .font(.anky(30))
                        .foregroundStyle(Color.ankyInk)
                        .padding(.top, 60)

                    if isLoading {
                        ProgressView()
                            .tint(Color.ankyGold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        if let fetchError {
                            Text(fetchError)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color.ankyAmber)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.ankyPanel)
                                )
                        }

                        if stories.isEmpty && fetchError == nil {
                            Text("No stories yet. Complete an 8-minute writing session to generate one.")
                                .font(.anky(16))
                                .foregroundStyle(Color.ankyMuted)
                                .lineSpacing(5)
                                .padding(20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .fill(Color.ankyPanelRaised.opacity(0.94))
                                )
                        }

                        ForEach(stories) { story in
                            storyRow(
                                title: story.title,
                                subtitle: story.played ? "Played" : "New",
                                isNew: !story.played
                            ) {
                                activeSession = IdentifiableSession(id: story.id, session: story.asGuidanceSession)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .fullScreenCover(item: $activeSession) { wrapper in
            GuidancePlaybackView(
                session: wrapper.session,
                onFinish: { _ in }
            )
        }
        .task {
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
                if let r = readyStory, !all.contains(where: { $0.id == r.id }) {
                    all.insert(r, at: 0)
                }
                stories = all.sorted { $0.generatedAt > $1.generatedAt }
            } catch {
                fetchError = "\(error)"
                print("[DebugStory] Fetch error: \(error)")
            }
            isLoading = false
        }
    }

    private func storyRow(title: String, subtitle: String, isNew: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.anky(17))
                        .foregroundStyle(Color.ankyInk)
                    Text(subtitle)
                        .font(.anky(12))
                        .foregroundStyle(isNew ? Color.ankyGold : Color.ankyMuted)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.ankyGold)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.ankyPanelRaised.opacity(0.94))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Thin wrappers for tab content

private struct DebugYouWrapper: View {
    var body: some View {
        YouView()
    }
}

private struct DebugStoriesWrapper: View {
    var body: some View {
        StoriesLibraryView()
    }
}

private struct DebugChildWorldWrapper: View {
    @State private var childProfiles = ChildProfileStore.load()
    @State private var isShowingCreate = false
    @State private var activeChild: ChildProfile?

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var biometricLock: BiometricLockManager

    var body: some View {
        ZStack {
            LinearGradient.ankyBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Child Worlds")
                        .font(.anky(30))
                        .foregroundStyle(Color.ankyInk)
                        .padding(.top, 60)

                    if childProfiles.isEmpty {
                        Button {
                            isShowingCreate = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 22))
                                Text("Create a child world")
                                    .font(.anky(17))
                            }
                            .foregroundStyle(Color.ankyGold)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(Color.ankyPanelRaised.opacity(0.94))
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        ForEach(childProfiles) { child in
                            Button {
                                activeChild = child
                            } label: {
                                HStack {
                                    Text(child.name)
                                        .font(.anky(18))
                                        .foregroundStyle(Color.ankyInk)
                                    Spacer()
                                    Image(systemName: "arrow.right.circle")
                                        .foregroundStyle(Color.ankyGold)
                                }
                                .padding(18)
                                .background(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .fill(Color.ankyPanelRaised.opacity(0.94))
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            isShowingCreate = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle")
                                Text("Add another")
                                    .font(.anky(14))
                            }
                            .foregroundStyle(Color.ankyMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $isShowingCreate) {
            CreateChildView { _ in
                childProfiles = ChildProfileStore.load()
            }
            .environmentObject(appState)
        }
        .fullScreenCover(item: $activeChild) { child in
            ChildShellView(child: child)
                .environmentObject(appState)
                .environmentObject(biometricLock)
        }
    }
}

private struct DebugLockedShell: View {
    var body: some View {
        WritingsView()
    }
}

// MARK: - Shared helper

extension Cuentacuentos {
    var asGuidanceSession: GuidanceSession {
        GuidanceSession(
            id: id,
            title: title,
            description: content,
            durationSeconds: max(guidancePhases.reduce(0) { $0 + $1.durationSeconds }, 1),
            phases: guidancePhases
        )
    }
}

// MARK: - Reusable Action Button

enum ActionState: Equatable {
    case idle
    case working
    case done
    case error(String)
}

struct ActionButtonView: View {
    let state: ActionState
    let idleLabel: String
    var workingLabel: String = "Working..."
    var doneLabel: String = "Done"
    var errorPrefix: String = "Error"
    var style: Style = .primary

    let action: () async -> Void

    enum Style {
        case primary
        case danger
    }

    private var label: String {
        switch state {
        case .idle: return idleLabel
        case .working: return workingLabel
        case .done: return doneLabel
        case .error(let msg): return "\(errorPrefix): \(msg)"
        }
    }

    private var icon: String {
        switch state {
        case .idle:
            return style == .danger ? "exclamationmark.triangle" : ""
        case .working:
            return ""
        case .done:
            return "checkmark.circle.fill"
        case .error:
            return "xmark.circle.fill"
        }
    }

    private var foreground: Color {
        switch state {
        case .idle:
            return style == .danger ? .ankyAmber : .ankyBlack
        case .working:
            return style == .danger ? .ankyAmber : .ankyBlack
        case .done:
            return .ankyBlack
        case .error:
            return .white
        }
    }

    private var background: Color {
        switch state {
        case .idle:
            return style == .danger ? .ankyPanelRaised : .ankyGold
        case .working:
            return style == .danger ? .ankyPanelRaised : .ankyGold.opacity(0.6)
        case .done:
            return Color(red: 0.2, green: 0.7, blue: 0.3)
        case .error:
            return Color(red: 0.7, green: 0.15, blue: 0.15)
        }
    }

    private var borderColor: Color {
        switch (state, style) {
        case (.idle, .danger): return .ankyAmber.opacity(0.3)
        case (.error, _): return Color(red: 0.9, green: 0.2, blue: 0.2).opacity(0.5)
        default: return .clear
        }
    }

    var body: some View {
        Button {
            guard state == .idle else { return }
            Task { await action() }
        } label: {
            HStack(spacing: 8) {
                if state == .working {
                    ProgressView()
                        .tint(foreground)
                        .scaleEffect(0.8)
                }

                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                }

                Text(label)
                    .font(.anky(14))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if style == .danger && state == .idle {
                    Spacer()
                }
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, alignment: style == .danger ? .leading : .center)
            .frame(height: 48)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(state == .working)
        .opacity(state == .working ? 0.85 : 1)
        .animation(.easeInOut(duration: 0.25), value: state)
    }
}
