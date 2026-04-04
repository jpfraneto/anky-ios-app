import SwiftUI

struct CreateChildView: View {
    private enum Step {
        case emojiPattern
        case confirmPattern
        case creating
        case success
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var step: Step = .emojiPattern
    @State private var emojiPattern: [String] = []
    @State private var creationError: String?

    let onCreated: (ChildProfile) -> Void

    private let childName = Self.randomChildName()

    var body: some View {
        NavigationStack {
            ZStack {
                warmBackground
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer(minLength: 0)
                    content
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.ankyInk)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                    .opacity(step == .success || step == .creating ? 0 : 1)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .task(id: stepID) {
                if step == .success {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .emojiPattern:
            emojiStep
        case .confirmPattern:
            confirmStep
        case .creating:
            creatingStep
        case .success:
            successStep
        }
    }

    // MARK: - Step 1: Pick emoji pattern

    private var emojiStep: some View {
        VStack(spacing: 18) {
            Text("Crea el patrón secreto de \(childName)")
                .font(.anky(24))
                .foregroundStyle(Color.ankyInk)
                .multilineTextAlignment(.center)

            Text("Toca 12 emojis en orden")
                .font(.anky(15))
                .foregroundStyle(Color.ankyMuted)

            EmojiSelectionGrid(emojis: ChildEmojiPalette.all) { emoji in
                guard emojiPattern.count < 12 else { return }
                emojiPattern.append(emoji)
            }
            .frame(maxHeight: 360)

            PatternSlotsView(pattern: emojiPattern, revealsEmoji: true)
                .padding(.top, 6)

            HStack(spacing: 12) {
                if !emojiPattern.isEmpty {
                    Button {
                        withAnimation(AnkyTheme.shortTransition) {
                            emojiPattern = []
                        }
                    } label: {
                        Text("Reiniciar")
                            .font(.anky(16))
                            .foregroundStyle(Color.ankyInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }

                if emojiPattern.count == 12 {
                    Button {
                        withAnimation(AnkyTheme.transition) {
                            step = .confirmPattern
                        }
                    } label: {
                        Text("Continuar")
                            .font(.anky(16))
                            .foregroundStyle(Color.ankyBlack)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(Color.ankyGold)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Step 2: Confirm (just show the pattern, one tap to confirm)

    private var confirmStep: some View {
        VStack(spacing: 28) {
            Text("Este es el patrón de \(childName)")
                .font(.anky(24))
                .foregroundStyle(Color.ankyInk)
                .multilineTextAlignment(.center)

            // Show the full pattern with emojis visible, larger
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ], spacing: 10) {
                ForEach(Array(emojiPattern.enumerated()), id: \.offset) { _, emoji in
                    Text(emoji)
                        .font(.system(size: 28))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                }
            }
            .padding(.horizontal, 8)

            Text("Solo quien conozca este patrón podrá entrar a su mundo.")
                .font(.anky(15))
                .foregroundStyle(Color.ankyMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            VStack(spacing: 12) {
                Button {
                    withAnimation(AnkyTheme.transition) {
                        step = .creating
                    }
                } label: {
                    Text("Confirmar")
                        .font(.anky(18))
                        .foregroundStyle(Color.ankyBlack)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color.ankyGold)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    emojiPattern = []
                    withAnimation(AnkyTheme.transition) {
                        step = .emojiPattern
                    }
                } label: {
                    Text("Elegir otro patrón")
                        .font(.anky(15))
                        .foregroundStyle(Color.ankyMuted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Creating

    private var creatingStep: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(Color.ankyGold)
                .scaleEffect(1.2)

            Text("Creando el mundo de \(childName)...")
                .font(.anky(26))
                .foregroundStyle(Color.ankyInk)
                .multilineTextAlignment(.center)

            if let creationError {
                Text(creationError)
                    .font(.anky(16))
                    .foregroundStyle(Color.ankyAmber)
                    .multilineTextAlignment(.center)

                Button {
                    Task { await createChild() }
                } label: {
                    Text("Intentar de nuevo")
                        .font(.anky(17))
                        .foregroundStyle(Color.ankyBlack)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.ankyGold)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            guard creationError == nil else { return }
            await createChild()
        }
    }

    // MARK: - Success

    private var successStep: some View {
        VStack(spacing: 20) {
            Text("El mundo de \(childName) está listo")
                .font(.anky(28))
                .foregroundStyle(Color.ankyInk)
                .multilineTextAlignment(.center)

            Text("Ahora vive dentro de Anky, protegido por su patrón secreto.")
                .font(.anky(17))
                .foregroundStyle(Color.ankyMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
        }
    }

    // MARK: - Background

    private var warmBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.16, green: 0.08, blue: 0.04),
                Color(red: 0.30, green: 0.16, blue: 0.05),
                Color(red: 0.44, green: 0.27, blue: 0.10),
                Color(red: 0.10, green: 0.05, blue: 0.03)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(
                colors: [Color.ankyGold.opacity(0.28), .clear],
                center: .top,
                startRadius: 30,
                endRadius: 420
            )
        )
    }

    // MARK: - Helpers

    private var stepID: Int {
        switch step {
        case .emojiPattern: return 0
        case .confirmPattern: return 1
        case .creating: return 2
        case .success: return 3
        }
    }

    private static func randomChildName() -> String {
        let names = [
            "Rubén", "Luna", "Sol", "Río", "Luz", "Mar", "Kai",
            "Noa", "Leo", "Mía", "Ari", "Zoe", "Ian", "Eva"
        ]
        return names.randomElement() ?? "Rubén"
    }

    private func createChild() async {
        creationError = nil

        guard await appState.ensureAuthenticatedForWrite() else {
            creationError = appState.authError ?? "Anky no pudo restaurar tu sesión."
            return
        }

        let birthdateString = Self.birthdateFormatter.string(from: Date())
        let parentWalletAddress = appState.user?.walletAddress ?? (try? SeedIdentityManager.shared.walletAddress()) ?? ""

        guard !parentWalletAddress.isEmpty else {
            creationError = "La identidad del padre o la madre no está lista."
            return
        }

        do {
            let derivedWalletAddress = try ChildIdentityDeriver.deriveWalletAddress(
                parentWalletAddress: parentWalletAddress,
                name: childName,
                birthdate: birthdateString
            )

            let profile = try await AnkyAPI.shared.createChild(
                CreateChildRequest(
                    name: childName,
                    birthdate: birthdateString,
                    derivedWalletAddress: derivedWalletAddress,
                    emojiPattern: emojiPattern
                )
            )

            ChildProfileStore.add(profile)
            onCreated(profile)

            withAnimation(AnkyTheme.transition) {
                step = .success
            }
        } catch {
            creationError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static let birthdateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
