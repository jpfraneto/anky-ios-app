import SwiftUI

struct ChildShellView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var biometricLock: BiometricLockManager

    @State private var enteredPattern: [String] = []
    @State private var attemptCount = 0
    @State private var shakeTrigger: CGFloat = 0
    @State private var isUnlocked = false
    @State private var isLoadingLibrary = false
    @State private var readyStory: Cuentacuentos?
    @State private var history: [Cuentacuentos] = []
    @State private var errorMessage: String?
    @State private var activeStory: Cuentacuentos?

    let child: ChildProfile

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            Group {
                if isUnlocked {
                    libraryView
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                } else {
                    lockView
                        .transition(.scale(scale: 1.04).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
        .animation(.easeInOut(duration: 0.45), value: isUnlocked)
        .fullScreenCover(item: $activeStory) { story in
            GuidancePlaybackView(
                session: story.playbackSession,
                onFinish: { completed in
                    guard completed else { return }
                    try? await AnkyAPI.shared.completeCuentacuentos(id: story.id)
                    await refreshLibrary()
                }
            )
        }
        .onChange(of: activeStory) { newStory in
            if let story = newStory {
                prefetchPhaseImages(for: story)
            }
        }
        .statusBarHidden(true)
    }

    private var lockView: some View {
        VStack(spacing: 22) {
            topBar

            Spacer(minLength: 10)

            VStack(spacing: 12) {
                Text(child.name)
                    .font(.anky(34))
                    .foregroundStyle(Color(red: 0.31, green: 0.14, blue: 0.05))

                Text("Tu mundo secreto")
                    .font(.anky(16))
                    .foregroundStyle(Color(red: 0.47, green: 0.24, blue: 0.08).opacity(0.85))
            }

            PatternSlotsView(pattern: enteredPattern, revealsEmoji: true)
                .padding(.vertical, 8)
                .modifier(ShakeEffect(animatableData: shakeTrigger))

            if attemptCount >= 3 {
                Text("Pídele ayuda a mamá o papá")
                    .font(.anky(16))
                    .foregroundStyle(Color(red: 0.63, green: 0.24, blue: 0.09))
            } else {
                Text("Toca tu patrón secreto")
                    .font(.anky(16))
                    .foregroundStyle(Color(red: 0.53, green: 0.31, blue: 0.14))
            }

            EmojiSelectionGrid(emojis: ChildEmojiPalette.all) { emoji in
                handleLockTap(emoji)
            }
            .frame(maxHeight: 420)

            Spacer(minLength: 0)
        }
    }

    private var libraryView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                topBar

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tus cuentos, \(child.name)")
                        .font(.anky(30))
                        .foregroundStyle(Color(red: 0.31, green: 0.14, blue: 0.05))

                    Text("Hechos con lo que nació en la escritura de mamá o papá.")
                        .font(.anky(16))
                        .foregroundStyle(Color(red: 0.47, green: 0.24, blue: 0.08).opacity(0.86))
                        .lineSpacing(4)
                }

                if isLoadingLibrary {
                    ProgressView()
                        .tint(Color.ankyGold)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 28)
                } else {
                    if let errorMessage {
                        childCard(background: storyGradient(seed: child.id, muted: false)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("No pude abrir su biblioteca")
                                    .font(.anky(20))
                                    .foregroundStyle(Color.ankyInk)

                                Text(errorMessage)
                                    .font(.anky(16))
                                    .foregroundStyle(Color.ankyInk.opacity(0.88))

                                Button {
                                    Task {
                                        await refreshLibrary()
                                    }
                                } label: {
                                    Text("Intentar de nuevo")
                                        .font(.anky(15))
                                        .foregroundStyle(Color(red: 0.28, green: 0.12, blue: 0.05))
                                        .padding(.horizontal, 14)
                                        .frame(height: 42)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(Color(red: 0.98, green: 0.86, blue: 0.60))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let readyStory {
                        childCard(background: storyGradient(seed: readyStory.id, muted: false)) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Listo para escuchar")
                                    .font(.anky(13))
                                    .foregroundStyle(Color.ankyInk.opacity(0.8))

                                Text(readyStory.title)
                                    .font(.anky(24))
                                    .foregroundStyle(Color.ankyInk)

                                Button {
                                    activeStory = readyStory
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 14, weight: .bold))
                                        Text("Escuchar")
                                            .font(.anky(16))
                                    }
                                    .foregroundStyle(Color(red: 0.28, green: 0.12, blue: 0.05))
                                    .padding(.horizontal, 16)
                                    .frame(height: 46)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color(red: 1.0, green: 0.90, blue: 0.66))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        childCard(background: storyGradient(seed: child.id + "-empty", muted: false)) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Todavía no hay un cuento listo")
                                    .font(.anky(22))
                                    .foregroundStyle(Color.ankyInk)

                                Text("Cuando aparezca uno nuevo, te estará esperando aquí.")
                                    .font(.anky(16))
                                    .foregroundStyle(Color.ankyInk.opacity(0.86))
                                    .lineSpacing(4)
                            }
                        }
                    }

                    if !history.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Ya escuchados")
                                .font(.anky(16))
                                .foregroundStyle(Color(red: 0.47, green: 0.24, blue: 0.08))

                            ForEach(history) { story in
                                childCard(background: storyGradient(seed: story.id, muted: true)) {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(story.title)
                                            .font(.anky(20))
                                            .foregroundStyle(Color.ankyInk.opacity(0.85))

                                        Text(story.generatedAt.replacingOccurrences(of: "T", with: " ").prefix(16))
                                            .font(.anky(13))
                                            .foregroundStyle(Color.ankyInk.opacity(0.6))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .task {
            await refreshLibrary()
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                Task {
                    let didReauthenticate = await biometricLock.reauthenticate(reason: "Return to the parent world.")
                    if didReauthenticate {
                        dismiss()
                    }
                }
            } label: {
                Text("← Salir")
                    .font(.anky(16))
                    .foregroundStyle(Color(red: 0.31, green: 0.14, blue: 0.05))
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.28))
                    )
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.84, blue: 0.56),
                    Color(red: 0.98, green: 0.72, blue: 0.38),
                    Color(red: 0.92, green: 0.52, blue: 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 280, height: 280)
                .blur(radius: 8)
                .offset(x: -120, y: -260)

            Circle()
                .fill(Color(red: 1.0, green: 0.92, blue: 0.66).opacity(0.45))
                .frame(width: 340, height: 340)
                .blur(radius: 10)
                .offset(x: 130, y: 250)
        }
    }

    private func handleLockTap(_ emoji: String) {
        guard enteredPattern.count < child.emojiPattern.count else { return }

        let nextIndex = enteredPattern.count
        guard emoji == child.emojiPattern[nextIndex] else {
            attemptCount += 1
            enteredPattern = []
            withAnimation(.easeInOut(duration: 0.32)) {
                shakeTrigger += 1
            }
            return
        }

        enteredPattern.append(emoji)

        guard enteredPattern.count == child.emojiPattern.count else { return }

        withAnimation(.easeInOut(duration: 0.45)) {
            isUnlocked = true
        }
    }

    @MainActor
    private func refreshLibrary() async {
        guard await appState.ensureAuthenticatedForWrite() else {
            errorMessage = appState.authError ?? "La sesión del padre o la madre no está disponible."
            return
        }

        isLoadingLibrary = true
        errorMessage = nil
        defer { isLoadingLibrary = false }

        do {
            async let ready = AnkyAPI.shared.getCuentacuentosReady(childId: child.id)
            async let storyHistory = AnkyAPI.shared.getCuentacuentosHistory(childId: child.id)
            readyStory = try await ready
            let fetchedHistory = try await storyHistory
            history = fetchedHistory
                .filter(\.played)
                .sorted { $0.generatedAt > $1.generatedAt }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @ViewBuilder
    private func childCard<Content: View>(
        background: LinearGradient,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(background)
            )
    }

    private func prefetchPhaseImages(for story: Cuentacuentos) {
        let urls = story.guidancePhases.prefix(2).compactMap { phase -> URL? in
            guard let urlString = phase.imageUrl else { return nil }
            return URL(string: urlString)
        }
        for url in urls {
            Task.detached(priority: .utility) {
                _ = try? await URLSession.shared.data(from: url)
            }
        }
    }

    private func storyGradient(seed: String, muted: Bool) -> LinearGradient {
        let palettes: [[Color]] = [
            [Color(red: 0.88, green: 0.47, blue: 0.22), Color(red: 0.95, green: 0.72, blue: 0.40)],
            [Color(red: 0.78, green: 0.35, blue: 0.18), Color(red: 0.95, green: 0.63, blue: 0.27)],
            [Color(red: 0.88, green: 0.56, blue: 0.24), Color(red: 0.98, green: 0.80, blue: 0.48)],
            [Color(red: 0.66, green: 0.30, blue: 0.14), Color(red: 0.94, green: 0.60, blue: 0.30)]
        ]

        let palette = palettes[abs(seed.unicodeScalars.reduce(0) { $0 + Int($1.value) }) % palettes.count]
        let colors = muted ? palette.map { $0.opacity(0.55) } : palette
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private extension Cuentacuentos {
    var playbackSession: GuidanceSession {
        GuidanceSession(
            id: id,
            title: title,
            description: content,
            durationSeconds: max(guidancePhases.reduce(0) { $0 + $1.durationSeconds }, 1),
            phases: guidancePhases
        )
    }
}
