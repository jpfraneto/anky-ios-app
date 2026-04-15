//
//  ProfileView.swift
//  Anky
//

import SwiftUI
import UIKit

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var walletAddress = ""
    @State private var selectedAnky: CachedWritingEntry?
    @State private var selectedArchivedDay: ChatArchiveDay?
    @State private var showSupportSheet = false
    @State private var showBackupSheet = false

    private var ankySessions: [CachedWritingEntry] {
        appState.writingHistory
            .filter { $0.isAnky }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var archivedDays: [ChatArchiveDay] {
        ChatStore.shared.loadArchivedDays()
    }

    private var latestAnkyImageURL: URL? {
        ankySessions.first?.remoteImageURL
    }

    private var displayName: String {
        AnkyNameStore.name ?? appState.user?.displayName ?? appState.user?.username ?? "anky"
    }

    private var ankyRead: String {
        let reflections = ankySessions.compactMap(\.response)
        if reflections.isEmpty {
            if ankySessions.isEmpty {
                return "Anky does not have enough writing yet to form a read on you. Keep showing up and the pattern will sharpen."
            }

            return "You keep returning to the page. There is patience in the way you stay with yourself, and your archive already reads like someone willing to look directly at what is real."
        }

        var sentences: [String] = []
        sentences.append("You keep returning to the page. \(ankySessions.count) real session\(ankySessions.count == 1 ? "" : "s") is enough to show that you do not flinch from your own interior life.")
        sentences.append(contentsOf: reflections.prefix(2).map(firstSentence(from:)))
        return sentences
            .filter { !$0.isEmpty }
            .prefix(3)
            .joined(separator: " ")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header
                heroCard
                backupRow
                interpretationCard

                if !archivedDays.isEmpty {
                    archivedDaysSection
                }

                sessionsSection
                supportSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .background(Color.ankyVoid.ignoresSafeArea())
        .onAppear {
            walletAddress = (try? SeedIdentityManager.shared.walletAddress()) ?? ""
            ImagePrefetcher.prefetch(urls: ankySessions.prefix(8).compactMap(\.remoteImageURL))
            Task {
                await appState.refreshWritings()
            }
        }
        .sheet(item: $selectedAnky) { anky in
            AnkyThreadView(anky: anky)
                .environmentObject(appState)
                .sheetStyleBackground(Color.ankyVoid)
        }
        .sheet(item: $selectedArchivedDay) { day in
            ArchivedChatDayView(day: day)
                .sheetStyleBackground(Color.ankyVoid)
        }
        .sheet(isPresented: $showSupportSheet) {
            AltarView()
                .environmentObject(appState)
        }
        .fullScreenCover(isPresented: $showBackupSheet) {
            SeedPhraseBackupView()
                .environmentObject(appState)
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
    }

    private var heroCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(appState.kingdom.color.opacity(0.34), lineWidth: 1.4)
                    .frame(width: 108, height: 108)

                if let latestAnkyImageURL {
                    AsyncImage(url: latestAnkyImageURL, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            profilePlaceholder
                        }
                    }
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
                } else {
                    profilePlaceholder
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                }
            }

            VStack(spacing: 6) {
                Text(displayName)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.92))

                Text("\(appState.user?.totalAnkys ?? ankySessions.count) ankys · \(appState.user?.totalWritings ?? appState.writingHistory.count) sessions")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.38))
            }

            if !walletAddress.isEmpty {
                Button {
                    UIPasteboard.general.string = walletAddress
                } label: {
                    HStack(spacing: 6) {
                        Text(truncatedWallet)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.white.opacity(0.58))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        )
    }

    private var interpretationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Anky’s Read On You")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(appState.kingdom.color.opacity(0.88))

            Text(ankyRead)
                .font(.system(size: 16, weight: .regular))
                .lineSpacing(6)
                .foregroundStyle(Color.white.opacity(0.88))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(hex: "151517"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
        )
    }

    private var archivedDaysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Past Days")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.74))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(archivedDays) { day in
                        Button {
                            selectedArchivedDay = day
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(day.date.map(dayFormatter.string(from:)) ?? day.dayKey)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.9))

                                Text("\(day.messages.count) messages · \(day.sessionCount) session\(day.sessionCount == 1 ? "" : "s")")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.42))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(width: 190, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your Sessions")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.74))

            if ankySessions.isEmpty {
                Text("Your sessions will gather here after your first real anky.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.46))
            } else {
                LazyVStack(spacing: 18) {
                    ForEach(ankySessions) { entry in
                        Button {
                            selectedAnky = entry
                        } label: {
                            sessionCard(entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func sessionCard(_ entry: CachedWritingEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.06))

                if let url = entry.remoteImageURL {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        default:
                            sessionImagePlaceholder(entry)
                        }
                    }
                } else {
                    sessionImagePlaceholder(entry)
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 26,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 26
                )
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(entry.createdAtLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.72))

                    Spacer()

                    Text(entry.durationLabel)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.42))
                }

                if let firstLine = firstLine(from: entry.content) {
                    Text(firstLine)
                        .font(.system(size: 16, weight: .regular))
                        .lineLimit(2)
                        .foregroundStyle(Color.white.opacity(0.9))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "151517"))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
        )
    }

    private var backupRow: some View {
        Group {
            if !appState.hasBackedUpPhrase {
                Button {
                    showBackupSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.ankyGold)

                        Text("back up recovery phrase")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.92))

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.3))
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.ankyGold.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.ankyGold.opacity(0.15), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.25))

                    Text("recovery phrase secured")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.3))

                    Spacer()
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.02))
                )
            }
        }
    }

    private var supportSection: some View {
        Button {
            showSupportSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: "f0b35a"))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Support Anky’s development")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                    Text("A simple, honest contribution. No subscription pitch.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.42))
                }

                Spacer()
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }

    private var profilePlaceholder: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [appState.kingdom.color.opacity(0.2), Color.ankyVoid],
                        center: .center,
                        startRadius: 12,
                        endRadius: 60
                    )
                )
            AnkyMark(size: 34)
                .opacity(0.44)
        }
    }

    private func sessionImagePlaceholder(_ entry: CachedWritingEntry) -> some View {
        ZStack {
            LinearGradient(
                colors: appState.kingdom.gradientColors.map { $0.opacity(0.32) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 10) {
                if let title = entry.ankyTitle, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.84))
                }

                Text(entry.durationLabel)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.44))
            }
            .padding(20)
        }
    }

    private var truncatedWallet: String {
        guard walletAddress.count > 12 else { return walletAddress }
        return "\(walletAddress.prefix(6))...\(walletAddress.suffix(4))"
    }

    private func firstLine(from text: String) -> String? {
        text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func firstSentence(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let parts = trimmed.split(whereSeparator: { ".!?".contains($0) })
        guard let first = parts.first else { return trimmed }
        return String(first).trimmingCharacters(in: .whitespacesAndNewlines) + "."
    }

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
}

struct ArchivedChatDayView: View {
    let day: ChatArchiveDay
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        if let date = day.date {
            return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        }
        return day.dayKey
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .buttonStyle(.plain)

                Spacer()

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.88))

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.ankyVoid)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(day.messages) { message in
                        archivedRow(message)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }
        .background(Color.ankyVoid.ignoresSafeArea())
    }

    @ViewBuilder
    private func archivedRow(_ message: PersistedMessage) -> some View {
        switch message.kind {
        case .anky(let text):
            AnkyMessageView(text: text, timestamp: message.timestamp)
        case .user(let text):
            UserMessageView(text: text, timestamp: message.timestamp, duration: message.duration)
        case .ankyImage(let url):
            AnkyImageMessageView(urlString: url, timestamp: message.timestamp)
        case .writingSession(let preview, _, _, let duration):
            UserMessageView(text: preview, timestamp: message.timestamp, duration: message.duration ?? duration)
        }
    }
}

struct AnkyThreadView: View {
    let anky: CachedWritingEntry
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var threadMessages: [AnkyThreadMessage] = []
    @State private var replyText = ""
    @State private var isAnkyTyping = false
    @FocusState private var isReplyFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .buttonStyle(.plain)

                Spacer()

                Text(anky.ankyTitle ?? anky.createdAtLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.ankyVoid)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
            }

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        if let url = anky.remoteImageURL {
                            ZStack {
                                Rectangle()
                                    .fill(Color.white.opacity(0.06))

                                AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    default:
                                        Rectangle()
                                            .fill(Color.white.opacity(0.06))
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        }

                        VStack(alignment: .trailing, spacing: 8) {
                            Text(anky.content)
                                .font(.system(size: 15, weight: .regular))
                                .lineSpacing(6)
                                .foregroundStyle(Color(hex: "1a1a1a"))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color(hex: "f5c6c2"))
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                            Button {
                                UIPasteboard.general.string = anky.content
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color(hex: "f5c6c2"))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color(hex: "1c1c1e"))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)

                        if let reflection = anky.response, !reflection.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Anky")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(appState.kingdom.color.opacity(0.88))

                                Text(reflection)
                                    .font(.custom("Georgia", size: 17))
                                    .lineSpacing(8)
                                    .foregroundStyle(Color.white.opacity(0.9))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Thread messages
                        ForEach(threadMessages) { msg in
                            if msg.role == "user" {
                                Text(msg.text)
                                    .font(.system(size: 15, weight: .regular))
                                    .lineSpacing(5)
                                    .foregroundStyle(Color(hex: "1a1a1a"))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(hex: "f5c6c2"))
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            } else {
                                Text(msg.text)
                                    .font(.custom("Georgia", size: 16))
                                    .lineSpacing(7)
                                    .foregroundStyle(Color.white.opacity(0.9))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if isAnkyTyping {
                            HStack(spacing: 4) {
                                ForEach(0..<3, id: \.self) { _ in
                                    Circle()
                                        .fill(Color.white.opacity(0.38))
                                        .frame(width: 6, height: 6)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Color.clear.frame(height: 1).id("thread-bottom")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                }
                .onChange(of: threadMessages.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo("thread-bottom")
                    }
                }
            }

            // Reply input
            HStack(spacing: 8) {
                TextField("talk to this anky...", text: $replyText, axis: .vertical)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1...4)
                    .focused($isReplyFocused)
                    .submitLabel(.send)
                    .onSubmit { sendReply() }

                if !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: sendReply) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.82))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color(hex: "f0b35a")))
                    }
                    .buttonStyle(.plain)
                    .disabled(isAnkyTyping)
                    .opacity(isAnkyTyping ? 0.5 : 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(hex: "1c1c1e"))
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
            }
        }
        .background(Color.ankyVoid.ignoresSafeArea())
        .onAppear {
            threadMessages = AnkyThreadChatStore.shared.load(ankyId: anky.id)
        }
    }

    private func sendReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isAnkyTyping else { return }

        let userMsg = AnkyThreadMessage(
            id: UUID().uuidString,
            role: "user",
            text: text,
            timestamp: .now
        )
        threadMessages.append(userMsg)
        AnkyThreadChatStore.shared.append(ankyId: anky.id, message: userMsg)
        replyText = ""
        isAnkyTyping = true

        let history = buildHistory()
        Task {
            do {
                let response = try await AnkyAPI.shared.chatQuick(
                    writing: anky.content,
                    message: text,
                    history: history
                )
                let normalized = response.trimmingCharacters(in: .whitespacesAndNewlines)
                let ankyResponse = normalized.isEmpty ? "i'm here. say more." : normalized
                let ankyMsg = AnkyThreadMessage(
                    id: UUID().uuidString,
                    role: "anky",
                    text: ankyResponse,
                    timestamp: .now
                )
                threadMessages.append(ankyMsg)
                AnkyThreadChatStore.shared.append(ankyId: anky.id, message: ankyMsg)
            } catch {
                let ankyMsg = AnkyThreadMessage(
                    id: UUID().uuidString,
                    role: "anky",
                    text: "i'm here. something slipped. say that again.",
                    timestamp: .now
                )
                threadMessages.append(ankyMsg)
                AnkyThreadChatStore.shared.append(ankyId: anky.id, message: ankyMsg)
            }
            isAnkyTyping = false
        }
    }

    private func buildHistory() -> [ChatHistoryItem] {
        threadMessages.compactMap { msg in
            ChatHistoryItem(
                role: msg.role == "user" ? "user" : "assistant",
                content: msg.text
            )
        }
    }
}

enum ImagePrefetcher {
    static func prefetch(urls: [URL]) {
        let uniqueURLs = Array(Set(urls))
        for url in uniqueURLs {
            Task.detached(priority: .background) {
                let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
                _ = try? await URLSession.shared.data(for: request)
            }
        }
    }
}
