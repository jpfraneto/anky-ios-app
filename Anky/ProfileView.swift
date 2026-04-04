//
//  ProfileView.swift
//  Anky
//
//  User profile: anky pfp, anky-given name, total ankys, wallet address, anky collage.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var walletAddress: String = ""

    private var ankys: [CachedWritingEntry] {
        appState.writingHistory.filter { $0.isAnky }
    }

    private var latestAnkyImageURL: URL? {
        ankys.first?.remoteImageURL
    }

    private var displayName: String {
        AnkyNameStore.name ?? appState.user?.displayName ?? appState.user?.username ?? "anky"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Close button
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer().frame(height: 24)

                // Anky PFP
                profileImage
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(appState.kingdom.color.opacity(0.3), lineWidth: 1.5)
                    )

                Spacer().frame(height: 16)

                // Anky-given name
                Text(displayName)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.9))

                Spacer().frame(height: 24)

                // Stats row
                HStack(spacing: 0) {
                    statCell(
                        value: "\(appState.user?.totalAnkys ?? ankys.count)",
                        label: "ankys"
                    )

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 0.5, height: 28)

                    statCell(
                        value: "\(appState.user?.totalWritings ?? appState.writingHistory.count)",
                        label: "sessions"
                    )
                }
                .padding(.horizontal, 40)

                Spacer().frame(height: 20)

                // Wallet address
                if !walletAddress.isEmpty {
                    Button {
                        UIPasteboard.general.string = walletAddress
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "wallet.bifold")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.3))

                            Text(truncatedWallet)
                                .font(.system(size: 12, weight: .light, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.4))

                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.white.opacity(0.2))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.04))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer().frame(height: 32)

                // Anky collage
                if !ankys.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("your ankys")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .padding(.horizontal, 20)

                        ankyCollage
                    }
                }

                Spacer().frame(height: 40)
            }
        }
        .background(Color.ankyVoid.ignoresSafeArea())
        .onAppear {
            walletAddress = (try? SeedIdentityManager.shared.walletAddress()) ?? ""
        }
    }

    // MARK: - Profile Image

    @ViewBuilder
    private var profileImage: some View {
        if let url = latestAnkyImageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    mandalaPlaceholder
                }
            }
        } else {
            mandalaPlaceholder
        }
    }

    /// Mandala generated from the user's combined writing history
    private var mandalaPlaceholder: some View {
        Group {
            if !appState.writingHistory.isEmpty {
                let combinedText = appState.writingHistory.prefix(10).map(\.content).joined(separator: " ")
                MandalaGenerator.generate(
                    text: combinedText,
                    keystrokeDeltas: [],
                    size: 120,
                    kingdom: appState.kingdom
                )
                .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [appState.kingdom.color.opacity(0.15), Color.ankyVoid],
                                center: .center,
                                startRadius: 10,
                                endRadius: 60
                            )
                        )
                    AnkyMark(size: 36)
                        .opacity(0.4)
                }
            }
        }
    }

    // MARK: - Wallet

    private var truncatedWallet: String {
        guard walletAddress.count > 12 else { return walletAddress }
        let prefix = walletAddress.prefix(6)
        let suffix = walletAddress.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    // MARK: - Stats

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.white.opacity(0.85))
            Text(label)
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(Color.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Anky Collage

    private var ankyCollage: some View {
        let columns = [
            GridItem(.flexible(), spacing: 3),
            GridItem(.flexible(), spacing: 3),
            GridItem(.flexible(), spacing: 3),
        ]

        return LazyVGrid(columns: columns, spacing: 3) {
            ForEach(ankys) { anky in
                ankyCell(anky)
                    .aspectRatio(1, contentMode: .fill)
            }
        }
        .padding(.horizontal, 3)
    }

    @ViewBuilder
    private func ankyCell(_ entry: CachedWritingEntry) -> some View {
        if let url = entry.remoteImageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    ankyCellPlaceholder(entry)
                }
            }
            .clipped()
        } else {
            ankyCellPlaceholder(entry)
        }
    }

    private func ankyCellPlaceholder(_ entry: CachedWritingEntry) -> some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: appState.kingdom.gradientColors.map { $0.opacity(0.3) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 4) {
                if let title = entry.ankyTitle {
                    Text(title)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                Text(entry.durationLabel)
                    .font(.system(size: 8, weight: .light, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
            .padding(6)
        }
    }
}
