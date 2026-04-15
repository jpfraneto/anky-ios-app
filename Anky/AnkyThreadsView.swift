//
//  AnkyThreadsView.swift
//  Anky
//
//  History of ankys — each one a thread with its mandala/image,
//  title, and date. Tapping opens that thread's conversation with
//  the mandala as background.
//

import SwiftUI

// MARK: - Thread Model

struct AnkyThread: Identifiable {
    let id: String
    let title: String
    let date: Date
    let wordCount: Int
    let duration: TimeInterval
    let text: String
    let keystrokeDeltas: [Double]
    let kingdom: Kingdom
    let imageURL: URL?        // AI-generated image if available
    let response: String?     // Anky's reflection
    let isAnky: Bool

    var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    var durationLabel: String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Threads View (History Panel)

struct AnkyThreadsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedThread: AnkyThread?

    private var threads: [AnkyThread] {
        appState.writingHistory
            .filter { $0.isAnky || $0.durationSeconds >= 60 }
            .map { entry in
                // Prefer decrypting from sealed store (encrypted source of truth),
                // fall back to WritingCacheStore plaintext for older sessions.
                let text: String = {
                    if let sealed = SealedSessionStore.find(sessionId: entry.id),
                       let decrypted = try? AnkyProtocol.decryptOwnSession(sealed: sealed) {
                        return decrypted
                    }
                    return entry.content
                }()

                return AnkyThread(
                    id: entry.id,
                    title: entry.ankyTitle ?? threadTitle(from: text),
                    date: entry.createdAt,
                    wordCount: entry.wordCount,
                    duration: entry.durationSeconds,
                    text: text,
                    keystrokeDeltas: [],  // Not stored in cache, mandala uses text hash
                    kingdom: appState.kingdom,
                    imageURL: entry.remoteImageURL,
                    response: entry.response,
                    isAnky: entry.isAnky
                )
            }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if threads.isEmpty {
                emptyState
            } else {
                threadList
            }
        }
        .fullScreenCover(item: $selectedThread) { thread in
            ThreadDetailView(thread: thread)
                .environmentObject(appState)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("no threads yet")
                .font(.system(size: 15, weight: .light, design: .serif))
                .foregroundStyle(Color.white.opacity(0.35))
            Text("write to create your first")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(Color.white.opacity(0.2))
            Spacer()
        }
    }

    private var threadList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 16) {
                Spacer(minLength: 20)

                ForEach(threads) { thread in
                    ThreadCard(thread: thread)
                        .onTapGesture {
                            selectedThread = thread
                        }
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
        }
    }

    private func threadTitle(from text: String) -> String {
        let words = text.split(separator: " ").prefix(6).joined(separator: " ")
        return words.isEmpty ? "untitled" : words + "..."
    }
}

// MARK: - Thread Card

private struct ThreadCard: View {
    let thread: AnkyThread

    var body: some View {
        HStack(spacing: 14) {
            // Mandala thumbnail
            MandalaGenerator.generate(
                text: thread.text,
                keystrokeDeltas: thread.keystrokeDeltas,
                size: 56,
                kingdom: thread.kingdom
            )
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(thread.kingdom.color.opacity(0.2), lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(thread.title)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(thread.dateLabel)
                        .font(.system(size: 11, weight: .light, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.3))

                    Text(thread.durationLabel)
                        .font(.system(size: 11, weight: .light, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.3))

                    Text("\(thread.wordCount)w")
                        .font(.system(size: 11, weight: .light, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.3))
                }
            }

            Spacer()

            if thread.isAnky {
                Circle()
                    .fill(thread.kingdom.color.opacity(0.4))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Thread Detail View (Conversation with mandala background)

struct ThreadDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let thread: AnkyThread

    @State private var replyText = ""
    @State private var conversationMessages: [ChatMessage] = []
    @State private var isAnkyTyping = false

    var body: some View {
        ZStack {
            // Mandala as background
            MandalaGenerator.generate(
                text: thread.text,
                keystrokeDeltas: thread.keystrokeDeltas,
                size: UIScreen.main.bounds.width * 1.5,
                kingdom: thread.kingdom
            )
            .opacity(0.08)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            Color.black.opacity(0.75).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                threadHeader

                Divider().opacity(0.1)

                // Conversation
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            // Original writing (collapsed)
                            writingCard

                            // Anky's reflection
                            if let response = thread.response {
                                ankyBubble(text: response)
                            }

                            // Follow-up conversation
                            ForEach(conversationMessages) { msg in
                                switch msg.kind {
                                case .anky(let text):
                                    ankyBubble(text: text)
                                case .user(let text):
                                    userBubble(text: text)
                                case .ankyImage(let url):
                                    AnkyImageMessageView(urlString: url, timestamp: msg.timestamp)
                                }
                            }

                            if isAnkyTyping {
                                typingIndicator
                            }

                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 80)
                    }
                    .onChange(of: conversationMessages.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo("bottom")
                        }
                    }
                }

                // Reply bar
                replyBar
            }
        }
        .statusBarHidden(true)
    }

    private var threadHeader: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text(thread.title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
                Text(thread.dateLabel)
                    .font(.system(size: 11, weight: .light, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.3))
            }

            Spacer()

            // Mandala mini
            MandalaGenerator.generate(
                text: thread.text,
                keystrokeDeltas: thread.keystrokeDeltas,
                size: 32,
                kingdom: thread.kingdom
            )
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.6))
    }

    private var writingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(thread.text.prefix(200) + (thread.text.count > 200 ? "..." : ""))
                .font(.system(size: 14, weight: .light, design: .serif))
                .foregroundStyle(Color.white.opacity(0.5))
                .lineSpacing(6)

            HStack(spacing: 8) {
                Text("\(thread.wordCount) words")
                Text(thread.durationLabel)
            }
            .font(.system(size: 11, weight: .light, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.25))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(thread.kingdom.color.opacity(0.15), lineWidth: 0.5)
                )
        )
    }

    private func ankyBubble(text: String) -> some View {
        HStack {
            Text(text)
                .font(.custom("Georgia", size: 15))
                .foregroundStyle(Color.white.opacity(0.8))
                .lineSpacing(6)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
            Spacer(minLength: 60)
        }
    }

    private func userBubble(text: String) -> some View {
        HStack {
            Spacer(minLength: 60)
            Text(text)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(thread.kingdom.color.opacity(0.15))
                )
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 5, height: 5)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private var replyBar: some View {
        HStack(spacing: 10) {
            TextField("", text: $replyText, prompt: Text("go deeper...")
                .foregroundColor(Color.white.opacity(0.2)))
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )

            if !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    sendReply()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(thread.kingdom.color)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.8))
    }

    private func sendReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let msg = ChatMessage(
            id: UUID(),
            kind: .user(text: text),
            timestamp: .now,
            isCurrentSession: true
        )
        conversationMessages.append(msg)
        replyText = ""
        isAnkyTyping = true

        Task {
            do {
                var history: [ChatHistoryItem] = []
                if let response = thread.response {
                    history.append(ChatHistoryItem(role: "assistant", content: response))
                }
                for cm in conversationMessages {
                    switch cm.kind {
                    case .user(let t): history.append(ChatHistoryItem(role: "user", content: t))
                    case .anky(let t): history.append(ChatHistoryItem(role: "assistant", content: t))
                    case .ankyImage: break
                    }
                }

                let response = try await AnkyAPI.shared.chatQuick(
                    writing: thread.text,
                    message: text,
                    history: history
                )
                let ankyMsg = ChatMessage(
                    id: UUID(),
                    kind: .anky(text: response),
                    timestamp: .now,
                    isCurrentSession: true
                )
                conversationMessages.append(ankyMsg)
            } catch {
                let fallback = ChatMessage(
                    id: UUID(),
                    kind: .anky(text: "i'm still here. something slipped. say that again."),
                    timestamp: .now,
                    isCurrentSession: true
                )
                conversationMessages.append(fallback)
            }
            isAnkyTyping = false
        }
    }
}
