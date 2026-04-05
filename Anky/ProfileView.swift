//
//  ProfileView.swift
//  Anky
//
//  User profile: anky pfp, name, total ankys, wallet, 96-day calendar, anky grid.
//  Tapping an anky opens its conversation thread.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var walletAddress: String = ""
    @State private var selectedAnky: CachedWritingEntry?

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
                // Close
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

                Spacer().frame(height: 20)

                // PFP
                profileImage
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(appState.kingdom.color.opacity(0.3), lineWidth: 1.5)
                    )

                Spacer().frame(height: 12)

                Text(displayName)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.9))

                Spacer().frame(height: 16)

                // Stats
                HStack(spacing: 0) {
                    statCell(value: "\(appState.user?.totalAnkys ?? ankys.count)", label: "ankys")
                    Rectangle().fill(Color.white.opacity(0.08)).frame(width: 0.5, height: 24)
                    statCell(value: "\(appState.user?.totalWritings ?? appState.writingHistory.count)", label: "sessions")
                }
                .padding(.horizontal, 48)

                Spacer().frame(height: 14)

                // Wallet
                if !walletAddress.isEmpty {
                    Button {
                        UIPasteboard.general.string = walletAddress
                    } label: {
                        HStack(spacing: 6) {
                            Text(truncatedWallet)
                                .font(.system(size: 11, weight: .light, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.35))
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.white.opacity(0.2))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.04))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer().frame(height: 28)

                // 96-day Ankyverse Calendar
                AnkyverseCalendar(ankys: ankys, onSelectAnky: { anky in
                    selectedAnky = anky
                })
                .padding(.horizontal, 16)

                Spacer().frame(height: 28)

                // Anky grid
                if !ankys.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("your ankys")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.35))
                            .padding(.horizontal, 20)

                        ankyGrid
                    }
                }

                Spacer().frame(height: 40)
            }
        }
        .background(Color.ankyVoid.ignoresSafeArea())
        .onAppear {
            walletAddress = (try? SeedIdentityManager.shared.walletAddress()) ?? ""
        }
        .sheet(item: $selectedAnky) { anky in
            AnkyThreadView(anky: anky)
                .environmentObject(appState)
                .sheetStyleBackground(Color.ankyVoid)
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
                    pfpPlaceholder
                }
            }
        } else {
            pfpPlaceholder
        }
    }

    private var pfpPlaceholder: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [appState.kingdom.color.opacity(0.15), Color.ankyVoid],
                        center: .center,
                        startRadius: 10,
                        endRadius: 50
                    )
                )
            AnkyMark(size: 32)
                .opacity(0.4)
        }
    }

    private var truncatedWallet: String {
        guard walletAddress.count > 12 else { return walletAddress }
        return "\(walletAddress.prefix(6))...\(walletAddress.suffix(4))"
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Color.white.opacity(0.85))
            Text(label)
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(Color.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Anky Grid

    private var ankyGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 3),
            GridItem(.flexible(), spacing: 3),
            GridItem(.flexible(), spacing: 3),
        ]

        return LazyVGrid(columns: columns, spacing: 3) {
            ForEach(ankys) { anky in
                Button { selectedAnky = anky } label: {
                    ankyCell(anky)
                        .aspectRatio(1, contentMode: .fill)
                }
                .buttonStyle(.plain)
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
            VStack(spacing: 3) {
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

// MARK: - 96-Day Ankyverse Calendar

struct AnkyverseCalendar: View {
    let ankys: [CachedWritingEntry]
    let onSelectAnky: (CachedWritingEntry) -> Void

    private let totalDays = Kingdom.ankyverseTotalDays
    private let daysPerWave = Kingdom.ankyverseDaysPerWave
    private let waveCount = Kingdom.ankyverseWaveCount
    private let epoch = Kingdom.ankyverseEpoch

    /// Map day number → anky written on that day (if any)
    private func ankyForDay(_ day: Int) -> CachedWritingEntry? {
        let dayStart = Date(timeIntervalSince1970: epoch + Double(day) * 86400)
        let dayEnd = dayStart.addingTimeInterval(86400)
        return ankys.first { $0.createdAt >= dayStart && $0.createdAt < dayEnd }
    }

    private var currentDay: Int? {
        Kingdom.ankyverseDayNumber()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Wave labels
            ForEach(0..<waveCount, id: \.self) { wave in
                let kingdom = Kingdom(rawValue: wave % 8) ?? .primordia
                HStack(spacing: 3) {
                    ForEach(0..<daysPerWave, id: \.self) { dayInWave in
                        let dayNumber = wave * daysPerWave + dayInWave
                        let dayKingdom = Kingdom.kingdom(forAnkyverseDay: dayNumber)
                        let anky = ankyForDay(dayNumber)
                        let isToday = dayNumber == currentDay
                        let isPast = currentDay != nil && dayNumber < currentDay!
                        let isFuture = currentDay == nil || dayNumber > currentDay!

                        Button {
                            if let anky { onSelectAnky(anky) }
                        } label: {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(cellColor(anky: anky, kingdom: dayKingdom, isPast: isPast, isFuture: isFuture))
                                .frame(height: 20)
                                .overlay {
                                    if isToday {
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                                    }
                                    if anky != nil {
                                        Circle()
                                            .fill(Color.white)
                                            .frame(width: 4, height: 4)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(anky == nil)
                    }
                }
            }
        }
    }

    private func cellColor(anky: CachedWritingEntry?, kingdom: Kingdom, isPast: Bool, isFuture: Bool) -> Color {
        if anky != nil {
            return kingdom.color.opacity(0.6)
        }
        if isFuture {
            return Color.white.opacity(0.02)
        }
        // Past day, no anky
        return Color.white.opacity(0.04)
    }
}

// MARK: - Anky Thread View (conversation for a specific anky)

struct AnkyThreadView: View {
    let anky: CachedWritingEntry
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                .buttonStyle(.plain)

                Spacer()

                if let title = anky.ankyTitle {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer()

                Text(anky.durationLabel)
                    .font(.system(size: 11, weight: .light, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.ankyVoid)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
            }

            // Content
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Anky image
                    if let url = anky.remoteImageURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            default:
                                EmptyView()
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // The writing (user message)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(anky.content)
                            .font(.system(size: 14))
                            .lineSpacing(6)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 11)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .frame(maxWidth: .infinity, alignment: .trailing)

                        Text(anky.createdAtLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.25))
                    }
                    .padding(.horizontal, 20)

                    // Reflection (anky message)
                    if let reflection = anky.response {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reflection)
                                .font(.custom("Georgia", size: 15))
                                .lineSpacing(8)
                                .foregroundStyle(Color.white.opacity(0.88))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer().frame(height: 40)
                }
                .padding(.top, 20)
            }
        }
        .background(Color.ankyVoid.ignoresSafeArea())
    }
}
