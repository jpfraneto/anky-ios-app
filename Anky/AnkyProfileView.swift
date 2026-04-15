//
//  AnkyProfileView.swift
//  Anky
//

import SwiftUI

enum ProfileSection: String, CaseIterable {
    case ankys = "ANKYS WRITTEN"
    case streak = "DAY STREAK"
    case words = "WORDS WRITTEN"
}

struct AnkyProfileView: View {
    @EnvironmentObject private var appState: AppState

    @State private var activeSection: ProfileSection = .ankys
    @State private var showSettings = false
    @State private var selectedAnky: ProfileAnkySession?
    @State private var selectedKingdom: ProfileKingdomSpec?
    @State private var selectedDay: Int?

    var onContinueConversation: ((CachedWritingEntry) -> Void)?

    init(onContinueConversation: ((CachedWritingEntry) -> Void)? = nil) {
        self.onContinueConversation = onContinueConversation
    }

    private var sessions: [ProfileAnkySession] {
        appState.writingHistory
            .filter(\.isAnky)
            .sorted { $0.createdAt > $1.createdAt }
            .map(ProfileAnkySession.init)
    }

    private var totalWords: Int {
        sessions.reduce(0) { $0 + $1.wordCount }
    }

    private var totalSessions: Int {
        sessions.count
    }

    private var currentStreak: Int {
        guard !sessions.isEmpty else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let today = calendar.startOfDay(for: .now)
        var streak = 0
        var checkDate = today

        while sessions.contains(where: { calendar.isDate($0.createdAt, inSameDayAs: checkDate) }) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = previousDay
        }

        return streak
    }

    private var avgFlowScore: Double {
        guard !sessions.isEmpty else { return 0 }
        let total = sessions.reduce(0.0) { $0 + $1.flowScore }
        return total / Double(sessions.count)
    }

    private var points: Int {
        let streakBonus = currentStreak * 10
        return sessions.reduce(0) { total, session in
            let completionBonus = session.isComplete ? 100 : 0
            let flowBonus = Int(floor(session.flowScore * 100))
            let completionStreakBonus = session.isComplete ? streakBonus : 0
            return total + 100 + completionBonus + flowBonus + completionStreakBonus
        }
    }

    private var level: Int {
        min(max((points / 500) + 1, 1), 8)
    }

    private var dominantKingdom: ProfileKingdomSpec {
        let counts = Dictionary(grouping: sessions.compactMap(\.kingdom), by: \.id)
            .mapValues(\.count)
        guard let id = counts.max(by: { $0.value < $1.value })?.key,
              let kingdom = ProfileKingdomSpec.byID[id] else {
            return ProfileKingdomSpec.ordered.first ?? .fallback
        }
        return kingdom
    }

    private var portraitURL: URL? {
        normalizedRemoteURL(appState.user?.profileImageUrl)
    }

    private var displayedMonth: Date {
        let sourceDate = sessions.first?.createdAt ?? .now
        return ProfileCalendarContext.utc.startOfMonth(for: sourceDate)
    }

    private var sessionsByDisplayedDay: [Int: [ProfileAnkySession]] {
        Dictionary(grouping: sessions.filter { ProfileCalendarContext.utc.isDate($0.createdAt, equalTo: displayedMonth, toGranularity: .month) }) {
            ProfileCalendarContext.utc.component(.day, from: $0.createdAt)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                heroSection
                statButtons
                sectionContent
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 100)
        }
        .background(Color.ankyBg.ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(appState)
        }
        .sheet(item: $selectedAnky) { session in
            ProfileConversationSheet(session: session)
                .environmentObject(appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.ankyBg)
        }
        .sheet(item: $selectedKingdom) { kingdom in
            ProfileKingdomDetailSheet(kingdom: kingdom)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.ankyBg)
        }
        .task {
            await appState.refreshWritings()
            ImagePrefetcher.prefetch(urls: sessions.compactMap(\.imageURL))
        }
    }

    private var heroSection: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    dominantKingdom.color.opacity(0.82),
                                    dominantKingdom.color.opacity(0.18),
                                    dominantKingdom.color.opacity(0.82)
                                ],
                                center: .center
                            ),
                            lineWidth: 2.6
                        )
                        .frame(width: 72, height: 72)

                    if let portraitURL {
                        AsyncImage(url: portraitURL, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                profilePortraitPlaceholder
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                    } else {
                        profilePortraitPlaceholder
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("YOU")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.ankyTextPrimary)

                    Text("\(points.formatted()) points · level \(level)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.ankyTextSecondary)
                }

                Spacer(minLength: 0)
            }

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.ankyTextMuted)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profilePortraitPlaceholder: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [dominantKingdom.color.opacity(0.22), Color.ankyBg],
                        center: .center,
                        startRadius: 6,
                        endRadius: 44
                    )
                )
            Text("👽")
                .font(.system(size: 30))
        }
    }

    private var statButtons: some View {
        HStack(spacing: 8) {
            ForEach(ProfileSection.allCases, id: \.self) { section in
                let isActive = activeSection == section

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeSection = section
                        if section != .streak {
                            selectedDay = nil
                        }
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(valueText(for: section))
                            .font(.system(size: 24, weight: .ultraLight))
                            .foregroundStyle(isActive ? Color.ankyTextPrimary : Color.ankyTextSecondary)

                        Text(section.rawValue)
                            .font(.system(size: 8, weight: .medium))
                            .tracking(1.2)
                            .foregroundStyle(isActive ? Color.ankyTextSecondary : Color.ankyTextMuted)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isActive ? Color.white.opacity(0.03) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isActive ? Color.white.opacity(0.07) : Color.white.opacity(0.04), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        if sessions.isEmpty {
            emptyState
        } else {
            switch activeSection {
            case .ankys:
                ankyListSection
            case .streak:
                calendarSection
            case .words:
                territoriesSection
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("no real ankys here yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.ankyTextPrimary.opacity(0.78))

            Text("finish one full 8-minute anky and it will land here with its image, your writing, and the conversation that follows.")
                .font(.custom("Georgia-Italic", size: 13))
                .lineSpacing(6)
                .foregroundStyle(Color.ankyTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.ankyCardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.ankyBorder, lineWidth: 1)
        )
    }

    private var ankyListSection: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                Button {
                    selectedAnky = session
                    onContinueConversation?(session.entry)
                } label: {
                    ProfileAnkyCardRow(session: session, dominantKingdom: dominantKingdom)
                }
                .buttonStyle(.plain)

                if index < sessions.count - 1 {
                    Rectangle()
                        .fill(Color.ankyDivider)
                        .frame(height: 1)
                        .padding(.leading, 78)
                }
            }
        }
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(ProfileCalendarContext.monthTitle(for: displayedMonth))
                .font(.system(size: 11, weight: .medium))
                .tracking(0.9)
                .foregroundStyle(Color(hex: "555555"))
                .frame(maxWidth: .infinity, alignment: .center)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(ProfileCalendarContext.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.6)
                        .foregroundStyle(Color(hex: "333333"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }

                ForEach(ProfileCalendarContext.leadingEmptyDays(for: displayedMonth), id: \.self) { _ in
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                }

                ForEach(ProfileCalendarContext.days(in: displayedMonth), id: \.self) { day in
                    let daySessions = sessionsByDisplayedDay[day] ?? []
                    let session = daySessions.first
                    let kingdom = session?.kingdom ?? dominantKingdom
                    let isSelected = selectedDay == day
                    let isToday = ProfileCalendarContext.utc.isDate(
                        ProfileCalendarContext.utc.date(bySetting: .day, value: day, of: displayedMonth) ?? displayedMonth,
                        inSameDayAs: .now
                    )

                    Button {
                        guard !daySessions.isEmpty else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            selectedDay = isSelected ? nil : day
                        }
                    } label: {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    isSelected
                                        ? kingdom.color.opacity(0.16)
                                        : daySessions.isEmpty ? Color.clear : kingdom.color.opacity(0.08)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(
                                            isSelected
                                                ? kingdom.color.opacity(0.55)
                                                : isToday ? Color.white.opacity(0.25) : Color.clear,
                                            lineWidth: isSelected || isToday ? 1.2 : 0
                                        )
                                )

                            Text("\(day)")
                                .font(.system(size: 12, weight: daySessions.isEmpty ? .regular : .medium))
                                .foregroundStyle(
                                    isSelected
                                        ? Color.white
                                        : daySessions.isEmpty ? Color.ankyTextDim : Color.white.opacity(0.78)
                                )

                            if !daySessions.isEmpty,
                               daySessions.contains(where: \.isComplete),
                               !isSelected {
                                Circle()
                                    .fill(kingdom.color.opacity(0.82))
                                    .frame(width: 4, height: 4)
                                    .padding(.bottom, 3)
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let selectedDay, let daySessions = sessionsByDisplayedDay[selectedDay] {
                LazyVStack(spacing: 0) {
                    ForEach(Array(daySessions.enumerated()), id: \.element.id) { index, session in
                        Button {
                            self.selectedAnky = session
                            onContinueConversation?(session.entry)
                        } label: {
                            ProfileAnkyCardRow(session: session, dominantKingdom: dominantKingdom)
                        }
                        .buttonStyle(.plain)

                        if index < daySessions.count - 1 {
                            Rectangle()
                                .fill(Color.ankyDivider)
                                .frame(height: 1)
                                .padding(.leading, 78)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private var territoriesSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 0) {
                ProfileMetricColumn(value: "\(Int((avgFlowScore * 100).rounded()))%", label: "avg flow score")
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1, height: 44)
                ProfileMetricColumn(value: "\(totalSessions)", label: "total sessions")
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("territories")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(Color.ankyTextMuted)

                VStack(spacing: 10) {
                    ForEach(ProfileKingdomSpec.ordered) { kingdom in
                        let count = sessions.filter { $0.kingdom?.id == kingdom.id }.count
                        let progress = sessions.isEmpty ? 0 : Double(count) / Double(sessions.count)

                        Button {
                            selectedKingdom = kingdom
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 10) {
                                    Text(kingdom.emoji)
                                        .font(.system(size: 14))
                                    Text(kingdom.id)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.white.opacity(count > 0 ? 0.68 : 0.3))
                                    Text(kingdom.chakra)
                                        .font(.system(size: 9, weight: .medium))
                                        .tracking(0.6)
                                        .foregroundStyle(Color.ankyTextDim)

                                    Spacer()

                                    Text("\(count)")
                                        .font(.system(size: 13, weight: .light))
                                        .foregroundStyle(Color.white.opacity(count > 0 ? 0.42 : 0.12))
                                }

                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.white.opacity(0.06))
                                        Capsule()
                                            .fill(kingdom.color.opacity(count > 0 ? 0.7 : 0))
                                            .frame(width: geometry.size.width * progress)
                                    }
                                }
                                .frame(height: 3)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.015))
                            )
                            .opacity(count > 0 ? 1 : 0.3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func valueText(for section: ProfileSection) -> String {
        switch section {
        case .ankys:
            return "\(totalSessions)"
        case .streak:
            return "\(currentStreak)"
        case .words:
            return totalWords.formatted()
        }
    }

    private func normalizedRemoteURL(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        if raw.hasPrefix("/") {
            return URL(string: "https://anky.app\(raw)")
        }
        return URL(string: "https://anky.app/\(raw)")
    }
}

private struct ProfileAnkyCardRow: View {
    let session: ProfileAnkySession
    let dominantKingdom: ProfileKingdomSpec

    var body: some View {
        HStack(spacing: 14) {
            ProfileAnkyThumbnail(session: session, fallbackKingdom: dominantKingdom, size: 64, cornerRadius: 14)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(session.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(hex: "dddddd"))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(session.shortDateLabel)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.ankyTextMuted)
                }

                Text(session.writingPreview)
                    .font(.custom("Georgia", size: 12))
                    .lineSpacing(5)
                    .foregroundStyle(Color(hex: "4a4a4a"))
                    .lineLimit(2)

                if !session.isSealed {
                    Text("saved locally · backend still pending")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.4)
                        .foregroundStyle((session.kingdom ?? dominantKingdom).color.opacity(0.74))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}

private struct ProfileAnkyThumbnail: View {
    let session: ProfileAnkySession
    let fallbackKingdom: ProfileKingdomSpec
    let size: CGFloat
    let cornerRadius: CGFloat

    private var kingdom: ProfileKingdomSpec {
        session.kingdom ?? fallbackKingdom
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                kingdom.color.opacity(0.5),
                                kingdom.color.opacity(0.12),
                                Color.ankyBg.opacity(0.9)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if let imageURL = session.imageURL {
                    AsyncImage(url: imageURL, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            thumbnailPlaceholder
                        }
                    }
                } else {
                    thumbnailPlaceholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: kingdom.color.opacity(0.14), radius: 10, y: 3)

            if !session.isSealed {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 8, height: 8)
                    .padding(4)
            }
        }
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            RadialGradient(
                colors: [kingdom.color.opacity(0.28), .clear],
                center: .center,
                startRadius: 4,
                endRadius: size
            )

            Text(kingdom.emoji)
                .font(.system(size: size * 0.38))
        }
    }
}

private struct ProfileMetricColumn: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color(hex: "999999"))

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .tracking(1)
                .foregroundStyle(Color.ankyTextMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

private struct ProfileConversationSheet: View {
    let session: ProfileAnkySession

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isReplyFocused: Bool

    @State private var storedMessages: [AnkyThreadMessage] = []
    @State private var replyText = ""
    @State private var isAnkyTyping = false
    @State private var isRetryingPendingAnky = false
    @State private var pendingRetryStatus: PendingRetryStatus?

    private let bottomAnchorID = "profile-conversation-bottom"

    private var liveEntry: CachedWritingEntry {
        appState.writingHistory.first(where: { $0.id == session.id }) ?? session.entry
    }

    private var liveSession: ProfileAnkySession {
        ProfileAnkySession(entry: liveEntry)
    }

    private var retryStatusMessage: String {
        if let pendingRetryStatus {
            return pendingRetryStatus.message
        }

        return "this anky is already part of your local history. if the backend stalled, resend the same canonical .anky session from here."
    }

    private var displayMessages: [ProfileConversationDisplayMessage] {
        var messages: [ProfileConversationDisplayMessage] = [
            ProfileConversationDisplayMessage(
                id: "writing-\(session.id)",
                role: "user",
                text: liveEntry.content
            )
        ]

        if let reflection = liveEntry.response?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reflection.isEmpty {
            messages.append(
                ProfileConversationDisplayMessage(
                    id: "reflection-\(session.id)",
                    role: "anky",
                    text: reflection
                )
            )
        }

        messages.append(contentsOf: storedMessages.map {
            ProfileConversationDisplayMessage(id: $0.id, role: $0.role, text: $0.text)
        })

        return messages
    }

    private var historyForFallback: [ChatHistoryItem] {
        var history: [ChatHistoryItem] = []

        if let reflection = liveEntry.response?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reflection.isEmpty {
            history.append(ChatHistoryItem(role: "assistant", content: reflection))
        }

        history.append(contentsOf: storedMessages.map {
            ChatHistoryItem(
                role: $0.role == "user" ? "user" : "assistant",
                content: $0.text
            )
        })

        return history
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        if !liveSession.isSealed {
                            pendingStatusCard
                        }

                        ForEach(displayMessages) { message in
                            bubble(for: message)
                        }

                        if isAnkyTyping {
                            typingIndicator
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorID)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.immediately)
                .onAppear {
                    syncBottom(proxy: proxy)
                }
                .onChange(of: displayMessages.count) { _, _ in
                    syncBottom(proxy: proxy)
                }
                .onChange(of: isAnkyTyping) { _, _ in
                    syncBottom(proxy: proxy)
                }
            }
        }
        .background(Color.ankyBg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            replyBar
        }
        .onAppear {
            storedMessages = AnkyThreadChatStore.shared.load(ankyId: session.id)
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ProfileAnkyThumbnail(
                    session: liveSession,
                    fallbackKingdom: liveSession.kingdom ?? .fallback,
                    size: 44,
                    cornerRadius: 12
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(liveSession.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: "e8e0d0"))
                        .lineLimit(1)

                    Text("\(liveSession.shortDateLabel) · \(liveSession.timeLabel) · \(liveSession.wordCount)w")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color(hex: "4a4a4a"))
                }

                Spacer()

                Text(liveSession.isSealed ? "✦ sealed" : "○ unsealed")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle((liveSession.kingdom ?? .fallback).color.opacity(liveSession.isSealed ? 0.78 : 0.34))
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)

            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)
        }
    }

    private var pendingStatusCard: some View {
        let kingdom = liveSession.kingdom ?? .fallback

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("backend processing is still pending")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ankyTextPrimary)

                    Text(retryStatusMessage)
                        .font(.custom("Georgia", size: 12))
                        .lineSpacing(5)
                        .foregroundStyle(pendingRetryStatus?.tone.color ?? Color(hex: "8a8078"))
                }

                Spacer(minLength: 8)

                Button(action: retryPendingAnkySubmission) {
                    Text(isRetryingPendingAnky ? "sending..." : "send again")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isRetryingPendingAnky ? Color.ankyTextDim : kingdom.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(isRetryingPendingAnky ? Color.white.opacity(0.03) : kingdom.color.opacity(0.12))
                        )
                        .overlay(
                            Capsule()
                                .stroke(isRetryingPendingAnky ? Color.ankyBorder : kingdom.color.opacity(0.28), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isRetryingPendingAnky)
            }

            Text("the resend reuses the same session hash and checks the existing backend status before it posts again.")
                .font(.system(size: 10, weight: .medium))
                .tracking(0.2)
                .foregroundStyle(Color.ankyTextMuted)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(kingdom.color.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(kingdom.color.opacity(0.16), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func bubble(for message: ProfileConversationDisplayMessage) -> some View {
        let isUser = message.role == "user"
        let kingdom = liveSession.kingdom ?? .fallback

        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            Text(isUser ? "YOU" : "ANKY")
                .font(.system(size: 9, weight: .medium))
                .tracking(1)
                .foregroundStyle(isUser ? Color.ankyTextDim : kingdom.color.opacity(0.48))

            Group {
                if isUser {
                    bubbleText(message.text, isUser: true, kingdom: kingdom)
                } else {
                    bubbleText(message.text, isUser: false, kingdom: kingdom)
                        .italic()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private func bubbleText(_ text: String, isUser: Bool, kingdom: ProfileKingdomSpec) -> some View {
        Text(text)
            .font(isUser ? .system(size: 13, weight: .regular, design: .monospaced) : .custom("Georgia", size: 14))
            .lineSpacing(6)
            .foregroundStyle(isUser ? Color(hex: "777777") : Color(hex: "8a8078"))
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
                .fill(isUser ? Color.ankyCardBg : kingdom.color.opacity(0.09))
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 14,
                    bottomLeadingRadius: isUser ? 14 : 4,
                    bottomTrailingRadius: isUser ? 4 : 14,
                    topTrailingRadius: 14
                )
                .stroke(isUser ? Color.ankyBorder : kingdom.color.opacity(0.12), lineWidth: 1)
            )
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 14,
                    bottomLeadingRadius: isUser ? 14 : 4,
                    bottomTrailingRadius: isUser ? 4 : 14,
                    topTrailingRadius: 14
                )
            )
    }

    private var typingIndicator: some View {
        let kingdom = liveSession.kingdom ?? .fallback

        return VStack(alignment: .leading, spacing: 4) {
            Text("ANKY")
                .font(.system(size: 9, weight: .medium))
                .tracking(1)
                .foregroundStyle(kingdom.color.opacity(0.48))

            Text("···")
                .font(.system(size: 18, weight: .regular))
                .tracking(4)
                .foregroundStyle(kingdom.color.opacity(0.44))
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(kingdom.color.opacity(0.09))
                )
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 14,
                        bottomLeadingRadius: 4,
                        bottomTrailingRadius: 14,
                        topTrailingRadius: 14
                    )
                    .stroke(kingdom.color.opacity(0.12), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var replyBar: some View {
        let kingdom = liveSession.kingdom ?? .fallback
        let trimmed = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isActive = !trimmed.isEmpty && !isAnkyTyping

        return HStack(alignment: .bottom, spacing: 10) {
            TextField("say something...", text: $replyText, axis: .vertical)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.82))
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.ankyCardBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isActive ? kingdom.color.opacity(0.28) : Color.ankyBorder, lineWidth: 1)
                )
                .focused($isReplyFocused)
                .submitLabel(.send)
                .onSubmit { sendReply() }

            Button(action: sendReply) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isActive ? kingdom.color : Color.ankyTextDim)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isActive ? kingdom.color.opacity(0.14) : Color.ankyCardBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isActive ? kingdom.color.opacity(0.34) : Color.ankyBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isActive)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .background(
            Color.ankyBg.opacity(0.98)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 1)
                }
        )
    }

    private func sendReply() {
        let trimmed = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAnkyTyping else { return }

        let userMessage = AnkyThreadMessage(
            id: UUID().uuidString,
            role: "user",
            text: trimmed,
            timestamp: .now
        )
        storedMessages.append(userMessage)
        AnkyThreadChatStore.shared.append(ankyId: session.id, message: userMessage)
        replyText = ""
        isAnkyTyping = true
        AnkyHaptics.messageSent()

        let fallbackHistory = historyForFallback

        Task {
            let responseText = await fetchReply(text: trimmed, history: fallbackHistory)
            let reply = AnkyThreadMessage(
                id: UUID().uuidString,
                role: "anky",
                text: responseText,
                timestamp: .now
            )

            await MainActor.run {
                storedMessages.append(reply)
                AnkyThreadChatStore.shared.append(ankyId: session.id, message: reply)
                isAnkyTyping = false
                AnkyHaptics.ankyMessage()
            }
        }
    }

    private func retryPendingAnkySubmission() {
        guard !isRetryingPendingAnky else { return }

        let entry = liveEntry
        isRetryingPendingAnky = true
        pendingRetryStatus = nil

        Task {
            do {
                let result = try await PendingAnkyRetryService.retry(entry: entry, appState: appState)
                await MainActor.run {
                    switch result {
                    case .synced:
                        pendingRetryStatus = PendingRetryStatus(
                            message: "the backend already has this anky now. your archive will refresh with the processed version.",
                            tone: .success
                        )
                    case .alreadyRunning:
                        pendingRetryStatus = PendingRetryStatus(
                            message: "this anky is already being sent again from this device.",
                            tone: .neutral
                        )
                    case .pending(let message):
                        pendingRetryStatus = PendingRetryStatus(message: message, tone: .neutral)
                    }
                    isRetryingPendingAnky = false
                }
            } catch {
                await MainActor.run {
                    pendingRetryStatus = PendingRetryStatus(
                        message: (error as? LocalizedError)?.errorDescription ?? "this device no longer has the canonical .anky payload needed to resend safely.",
                        tone: .error
                    )
                    isRetryingPendingAnky = false
                }
            }
        }
    }

    private func fetchReply(text: String, history: [ChatHistoryItem]) async -> String {
        if let ankyId = liveEntry.ankyId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ankyId.isEmpty {
            do {
                let response = try await AnkyAPI.shared.continueAnkyConversation(ankyId: ankyId, text: text)
                let trimmed = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            } catch {}
        }

        do {
            let response = try await AnkyAPI.shared.chatQuick(
                writing: liveEntry.content,
                message: text,
                history: history
            )
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        } catch {}

        return "i'm here. something slipped. say that again."
    }

    private func syncBottom(proxy: ScrollViewProxy) {
        scrollToBottom(proxy: proxy)
        DispatchQueue.main.async {
            scrollToBottom(proxy: proxy)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
    }
}

private struct ProfileKingdomDetailSheet: View {
    let kingdom: ProfileKingdomSpec

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Capsule()
                    .fill(Color(hex: "333333"))
                    .frame(width: 32, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)

                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(kingdom.color.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(kingdom.color.opacity(0.22), lineWidth: 1)
                            )
                        Text(kingdom.emoji)
                            .font(.system(size: 24))
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(kingdom.id)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.ankyTextPrimary)
                        Text(kingdom.chakra)
                            .font(.system(size: 11, weight: .medium))
                            .tracking(0.8)
                            .foregroundStyle(kingdom.color.opacity(0.8))
                    }
                }

                Text(kingdom.description)
                    .font(.custom("Georgia", size: 13))
                    .lineSpacing(8)
                    .foregroundStyle(Color(hex: "888888"))

                VStack(alignment: .leading, spacing: 4) {
                    Text("lesson")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(1)
                        .foregroundStyle(kingdom.color.opacity(0.5))
                        .textCase(.uppercase)

                    Text("\"\(kingdom.lesson)\"")
                        .font(.custom("Georgia-Italic", size: 12))
                        .lineSpacing(6)
                        .foregroundStyle(Color(hex: "7a7068"))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(kingdom.color.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(kingdom.color.opacity(0.12), lineWidth: 1)
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .background(Color.ankyBg.ignoresSafeArea())
    }
}

private struct ProfileConversationDisplayMessage: Identifiable, Equatable {
    let id: String
    let role: String
    let text: String
}

private struct PendingRetryStatus: Equatable {
    enum Tone: Equatable {
        case neutral
        case success
        case error

        var color: Color {
            switch self {
            case .neutral:
                return Color(hex: "8a8078")
            case .success:
                return Color(hex: "c9b37a")
            case .error:
                return Color(hex: "c17763")
            }
        }
    }

    let message: String
    let tone: Tone
}

private struct ProfileAnkySession: Identifiable, Equatable {
    let entry: CachedWritingEntry

    var id: String { entry.id }
    var title: String {
        if let title = entry.ankyTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        let words = entry.content
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .prefix(6)
            .joined(separator: " ")
        return words.isEmpty ? "anky" : words.lowercased()
    }
    var kingdom: ProfileKingdomSpec? {
        ProfileKingdomSpec.fromBackendName(entry.kingdom)
            ?? entry.ankyKingdom.flatMap { ProfileKingdomSpec.fromBackendName($0.rawValue) }
    }
    var imageURL: URL? { entry.remoteImageURL }
    var createdAt: Date { entry.createdAt }
    var durationSeconds: Double { entry.durationSeconds }
    var wordCount: Int { entry.wordCount }
    var isComplete: Bool { entry.durationSeconds >= LocalWritingCapture.requiredDurationForAnky }
    var isSealed: Bool { entry.syncState == .synced }
    var flowScore: Double {
        if let score = entry.flowScore {
            return min(max(score, 0), 1)
        }
        let durationMinutes = max(entry.durationSeconds / 60, 1)
        let fallback = min(max((Double(entry.wordCount) / durationMinutes) / 60.0, 0), 1)
        return fallback
    }
    var writingPreview: String {
        let flattened = entry.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flattened.count > 120 else { return flattened }
        return String(flattened.prefix(120)) + "..."
    }
    var shortDateLabel: String { ProfileDateFormatters.shortDate.string(from: entry.createdAt).lowercased() }
    var timeLabel: String { ProfileDateFormatters.time.string(from: entry.createdAt).lowercased() }
}

private struct ProfileKingdomSpec: Identifiable {
    let id: String
    let chakra: String
    let emoji: String
    let color: Color
    let lesson: String
    let description: String

    static let ordered: [ProfileKingdomSpec] = [
        ProfileKingdomSpec(
            id: "Primordia",
            chakra: "root",
            emoji: "🔥",
            color: Color(hex: "e63946"),
            lesson: "Survival is not weakness — it's the foundation everything else stands on.",
            description: "Primordia is the kingdom of survival, grounding, and primal energy. It maps to the root chakra — the base of everything. When your writing lands here, you're processing fear, safety, money, shelter, the body itself. The raw material of being alive. Sessions in Primordia tend to be urgent, physical, and close to the bone. This is where you write when something fundamental feels unstable."
        ),
        ProfileKingdomSpec(
            id: "Emblazion",
            chakra: "sacral",
            emoji: "🌊",
            color: Color(hex: "ff6b35"),
            lesson: "Desire isn't the enemy. Repression is.",
            description: "Emblazion is the kingdom of desire, emotion, and creative fire. It maps to the sacral chakra — the seat of feeling and wanting. When your writing lands here, you're processing pleasure, passion, guilt, longing, or the tension between what you want and what you allow yourself to have. Sessions in Emblazion are fluid, sometimes chaotic, always honest about appetite."
        ),
        ProfileKingdomSpec(
            id: "Chryseos",
            chakra: "solar",
            emoji: "⚡",
            color: Color(hex: "ffd166"),
            lesson: "Your power isn't in the outcome. It's in the choice to act.",
            description: "Chryseos is the kingdom of willpower, identity, and personal agency. It maps to the solar plexus — the center of self. When your writing lands here, you're processing confidence, ambition, shame, control, or the question of who you are when no one is watching. Sessions in Chryseos often involve decisions, boundaries, and the friction between who you've been and who you're becoming."
        ),
        ProfileKingdomSpec(
            id: "Eleasis",
            chakra: "heart",
            emoji: "💚",
            color: Color(hex: "2ec4b6"),
            lesson: "The heart doesn't need permission to open.",
            description: "Eleasis is the kingdom of love, compassion, and connection. It maps to the heart chakra — the bridge between lower and upper worlds. When your writing lands here, you're processing relationships, forgiveness, tenderness, grief, or the ache of caring deeply. Sessions in Eleasis are often the most open and unguarded. This is where walls come down."
        ),
        ProfileKingdomSpec(
            id: "Voxlumis",
            chakra: "throat",
            emoji: "✦",
            color: Color(hex: "a78bfa"),
            lesson: "Say the thing you're afraid to say — that's the one that matters.",
            description: "Voxlumis is the kingdom of voice, truth, and expression. It maps to the throat chakra — the channel between inner knowing and outer world. When your writing lands here, you're processing what needs to be said, what's been held back, the gap between thinking and speaking. Sessions in Voxlumis often circle around a conversation you haven't had yet."
        ),
        ProfileKingdomSpec(
            id: "Insightia",
            chakra: "third eye",
            emoji: "👁",
            color: Color(hex: "4361ee"),
            lesson: "What you see when you stop looking is the truth.",
            description: "Insightia is the kingdom of intuition, perception, and inner sight. It maps to the third eye — the seat of seeing beyond. When your writing lands here, you're processing clarity, confusion, patterns you're starting to recognize, or the strange feeling of knowing something before you can prove it. Sessions in Insightia tend to be quieter, more spacious, almost meditative."
        ),
        ProfileKingdomSpec(
            id: "Claridium",
            chakra: "crown",
            emoji: "∞",
            color: Color(hex: "7b2ff7"),
            lesson: "You are not the river. You are not the bank. You are the flowing.",
            description: "Claridium is the kingdom of transcendence, meaning, and the infinite. It maps to the crown chakra — the connection to something larger. When your writing lands here, you're processing purpose, spirituality, existential questions, or moments where the boundary between self and world dissolves. Sessions in Claridium often feel like downloads — the words come through you, not from you."
        ),
        ProfileKingdomSpec(
            id: "Poiesis",
            chakra: "creation",
            emoji: "◈",
            color: Color(hex: "f72585"),
            lesson: "Creation is the only proof you were here.",
            description: "Poiesis is the kingdom of pure creation — making something from nothing. It sits beyond the seven chakras, in the space where all of them converge. When your writing lands here, you're not processing — you're building. You're thinking about craft, about the work, about the act of making itself. Sessions in Poiesis are meta-aware: the writing is about writing, the building is about building."
        )
    ]

    static let byID: [String: ProfileKingdomSpec] = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })

    static func fromBackendName(_ raw: String?) -> ProfileKingdomSpec? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        if let exact = byID[raw] {
            return exact
        }

        let normalized = raw.lowercased()
        return ordered.first { $0.id.lowercased() == normalized }
    }

    static let fallback = ProfileKingdomSpec(
        id: "Primordia",
        chakra: "root",
        emoji: "👽",
        color: Color(hex: "666666"),
        lesson: "Keep writing until the shape appears.",
        description: "Anky has not classified this session yet."
    )
}

private enum ProfileDateFormatters {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}

private enum ProfileCalendarContext {
    static var utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.firstWeekday = 2
        return calendar
    }()

    static let weekdaySymbols = ["m", "t", "w", "t", "f", "s", "s"]

    static func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date).lowercased()
    }

    static func leadingEmptyDays(for date: Date) -> [Int] {
        let firstDay = utc.startOfMonth(for: date)
        let weekday = utc.component(.weekday, from: firstDay)
        let mondayBasedOffset = (weekday + 5) % 7
        return Array(0..<mondayBasedOffset)
    }

    static func days(in date: Date) -> [Int] {
        let range = utc.range(of: .day, in: .month, for: date) ?? 1..<1
        return Array(range)
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}
