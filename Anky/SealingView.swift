import SwiftUI
import UIKit

struct SealingView: View {
    enum Phase {
        case portal
        case sealing
        case sealed
        case done
    }

    @EnvironmentObject private var appState: AppState

    @ObservedObject var viewModel: ChatViewModel
    let capture: LocalWritingCapture
    let kingdom: Kingdom
    let onComplete: () -> Void
    let onSkip: () -> Void

    @State private var phase: Phase = .portal
    @State private var dragOffset: CGFloat = 0
    @State private var didStartDrag = false
    @State private var didCrossCompletionThreshold = false
    @State private var statusHasAccepted = false
    @State private var titleText: String?
    @State private var fullReflection = ""
    @State private var streamedImageURL: String?
    @State private var submitErrorMessage: String?
    @State private var pulseCircles = false
    @State private var didPersistStoredSubmission = false
    @State private var didDeliverReflectionToChat = false
    @State private var didDeliverImageToChat = false
    @State private var didRecordPendingSubmission = false
    @State private var streamTask: Task<Void, Never>?

    private let backgroundColor = Color(hex: "080612")
    private let trackBackground = Color(hex: "0c0816")
    private let cardBorder = Color(hex: "1a1030")

    private var accent: Color { kingdom.sealingColor }
    private var displayName: String { kingdom.sealingDisplayName }
    private var metadataLine: String { "\(kingdom.chakra) · \(kingdom.sealingElement)" }
    private var reflectionPreview: String { previewSentence(from: fullReflection) }

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    accent.opacity(phase == .sealed ? 0.08 : 0.05),
                    Color.clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 260
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Text("SESSION COMPLETE")
                    .font(.ankyBody(9))
                    .foregroundStyle(Color(hex: "444444"))
                    .tracking(1.8)
                    .padding(.top, 22)

                Spacer(minLength: 28)

                switch phase {
                case .portal:
                    portalContent
                case .sealing:
                    sealingContent
                case .sealed, .done:
                    sealedContent
                }

                Spacer(minLength: 24)

                if phase == .portal {
                    portalFooter
                        .padding(.horizontal, 16)
                        .padding(.bottom, 22)
                }
            }
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .sealing {
                beginStreamingSubmission()
            }
        }
        .onDisappear {
            streamTask?.cancel()
        }
    }

    private var portalContent: some View {
        VStack(spacing: 0) {
            SealingCirclesView(
                accent: accent,
                emojiSize: 32,
                pulsing: false,
                animatePulse: false
            )
            .frame(width: 120, height: 120)

            Text(displayName.uppercased())
                .font(.system(size: 26, weight: .ultraLight))
                .foregroundStyle(accent)
                .tracking(2.6)
                .padding(.top, 26)

            Text(metadataLine.uppercased())
                .font(.ankyBody(9))
                .foregroundStyle(Color(hex: "444444"))
                .tracking(1.35)
                .padding(.top, 10)

            HStack(spacing: 14) {
                SealingStatView(value: formatDuration(capture.duration), label: "DURATION")
                SealingStatView(value: "\(capture.wordCount)", label: "WORDS")
                SealingStatView(value: "\(Int((capture.estimatedFlowScore * 100).rounded()))%", label: "FLOW")
            }
            .padding(.top, 34)
            .padding(.horizontal, 22)

            Text("today the ankyverse speaks through \(displayName.lowercased())")
                .font(.custom("Georgia-Italic", size: 11))
                .foregroundStyle(Color(hex: "555555"))
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.top, 32)
                .padding(.horizontal, 38)
        }
    }

    private var sealingContent: some View {
        VStack(spacing: 0) {
            SealingCirclesView(
                accent: accent,
                emojiSize: 32,
                pulsing: true,
                animatePulse: pulseCircles
            )
            .frame(width: 120, height: 120)

            Text(statusHasAccepted ? "ANCHORING TO THE ANKYVERSE" : "WRITING TO SOLANA")
                .font(.ankyBody(9))
                .foregroundStyle(accent.opacity(0.55))
                .tracking(1.8)
                .padding(.top, 28)
                .id(statusHasAccepted)
                .transition(.opacity)

            SealingAnimatedDotsView(color: accent)
                .padding(.top, 16)

            if let submitErrorMessage, !submitErrorMessage.isEmpty {
                Text(submitErrorMessage)
                    .font(.ankyBody(10))
                    .foregroundStyle(Color(hex: "666666"))
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
                    .padding(.horizontal, 34)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseCircles = true
            }
        }
    }

    private var sealedContent: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .stroke(accent.opacity(0.35), lineWidth: 1)
                    .frame(width: 108, height: 108)
                    .shadow(color: accent.opacity(0.32), radius: 22, y: 0)

                Text("🦋")
                    .font(.system(size: 56))
            }

            Text("SEALED")
                .font(.ankyBody(13))
                .foregroundStyle(accent)
                .tracking(2.6)
                .padding(.top, 24)

            Text("your words are in the ankyverse forever")
                .font(.custom("Georgia-Italic", size: 11))
                .foregroundStyle(Color(hex: "444444"))
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 10) {
                Text("ANKY SEES")
                    .font(.ankyBody(9))
                    .foregroundStyle(Color(hex: "444444"))
                    .tracking(1.2)

                if reflectionPreview.isEmpty {
                    SealingAnimatedDotsView(color: Color(hex: "666666"))
                        .padding(.top, 4)
                } else {
                    Text(reflectionPreview)
                        .font(.custom("Georgia-Italic", size: 10))
                        .foregroundStyle(Color(hex: "666666"))
                        .lineSpacing(7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(trackBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(cardBorder, lineWidth: 1)
                    )
            )
            .padding(.top, 28)
            .padding(.horizontal, 18)

            Button(action: completeSealingFlow) {
                Text("TALK TO ANKY ABOUT THIS →")
                    .font(.ankyBody(12))
                    .foregroundStyle(accent)
                    .tracking(0.96)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(accent.opacity(0.09))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(accent.opacity(0.27), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 22)
            .padding(.horizontal, 18)
        }
    }

    private var portalFooter: some View {
        VStack(spacing: 14) {
            GeometryReader { proxy in
                let thumbSize: CGFloat = 44
                let trackInset: CGFloat = 4
                let maxTravel = max(proxy.size.width - thumbSize - (trackInset * 2), 0)
                let progress = maxTravel > 0 ? min(max(dragOffset / maxTravel, 0), 1) : 0
                let labelOpacity = max(0, 1 - max(progress - 0.5, 0) * 2)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(trackBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .stroke(accent.opacity(0.27), lineWidth: 1)
                        )

                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(accent.opacity(0.10))
                        .frame(width: thumbSize + dragOffset + trackInset)

                    Text("SEAL INTO THE ANKYVERSE")
                        .font(.ankyBody(10))
                        .foregroundStyle(accent.opacity(0.4))
                        .tracking(1.2)
                        .frame(maxWidth: .infinity)
                        .opacity(labelOpacity)

                    Circle()
                        .fill(accent)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: accent.opacity(0.4), radius: 10, y: 0)
                        .overlay(
                            Image(systemName: "arrow.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.white)
                        )
                        .offset(x: trackInset + dragOffset)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if !didStartDrag {
                                        didStartDrag = true
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }

                                    let updatedOffset = min(max(value.translation.width, 0), maxTravel)
                                    let updatedProgress = maxTravel > 0 ? min(max(updatedOffset / maxTravel, 0), 1) : 0
                                    dragOffset = updatedOffset
                                    if updatedProgress >= 0.9, !didCrossCompletionThreshold {
                                        didCrossCompletionThreshold = true
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    } else if updatedProgress < 0.9 {
                                        didCrossCompletionThreshold = false
                                    }
                                }
                                .onEnded { _ in
                                    didStartDrag = false
                                    let finalProgress = maxTravel > 0 ? min(max(dragOffset / maxTravel, 0), 1) : 0
                                    if finalProgress >= 0.9 {
                                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                                            dragOffset = maxTravel
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                            phase = .sealing
                                        }
                                    } else {
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                            dragOffset = 0
                                        }
                                        didCrossCompletionThreshold = false
                                    }
                                }
                        )
                }
            }
            .frame(height: 52)

            Button(action: skipSealingFlow) {
                Text("not now")
                    .font(.ankyBody(10))
                    .foregroundStyle(Color(hex: "222222"))
            }
            .buttonStyle(.plain)
        }
    }

    private func beginStreamingSubmission() {
        guard streamTask == nil else { return }

        if !didRecordPendingSubmission {
            didRecordPendingSubmission = true
            appState.recordWriting(capture, response: nil, syncState: .pending)
        }

        streamTask = Task {
            do {
                for try await event in AnkyAPI.shared.streamAnkySubmit(capture: capture, kingdom: kingdom) {
                    await MainActor.run {
                        handleStreamEvent(event)
                    }
                }

                await MainActor.run {
                    handleStreamCompletionIfNeeded()
                }
            } catch let streamFailure as AnkySubmitStreamFailure {
                await MainActor.run {
                    handleStreamFailure(stage: streamFailure.stage)
                }
            } catch {
                await MainActor.run {
                    handleStreamFailure(stage: "persist")
                }
            }
        }
    }

    private func handleStreamEvent(_ event: AnkySubmitStreamEvent) {
        switch event {
        case .accepted(let ankyId):
            withAnimation(.easeInOut(duration: 0.25)) {
                statusHasAccepted = true
            }
            viewModel.markSealingAccepted(ankyId: ankyId)
            persistStoredSubmissionIfNeeded(ankyId: ankyId)

        case .title(let title):
            titleText = title
            persistArtifacts()

        case .reflectionChunk(let chunk):
            fullReflection += chunk
            viewModel.appendSealingReflectionChunk(chunk)

        case .reflectionComplete(let reflection):
            fullReflection = reflection
            viewModel.replaceSealingReflection(reflection)
            persistArtifacts()
            deliverStreamedOutcomeIfPossible(markComplete: false)

        case .imageURL(let imageURL):
            streamedImageURL = imageURL
            persistArtifacts()
            deliverStreamedOutcomeIfPossible(markComplete: false)

        case .solana:
            break

        case .done(let ankyId):
            viewModel.markSealingDone(ankyId: ankyId)
            persistStoredSubmissionIfNeeded(ankyId: ankyId)
            persistArtifacts()
            deliverStreamedOutcomeIfPossible(markComplete: true)
            reconcileCanonicalArchive(pollUntilSettled: true, markComplete: true)
            transitionToSealed()

        case .error(let stage, _):
            if (stage == "solana" || stage == "image"), viewModel.sealingAnkyId != nil {
                viewModel.markSealingDone(ankyId: viewModel.sealingAnkyId)
                if let ankyId = viewModel.sealingAnkyId {
                    persistStoredSubmissionIfNeeded(ankyId: ankyId)
                }
                persistArtifacts()
                deliverStreamedOutcomeIfPossible(markComplete: true)
                reconcileCanonicalArchive(pollUntilSettled: true, markComplete: true)
                transitionToSealed()
            } else {
                handleStreamFailure(stage: stage)
            }
        }
    }

    private func handleStreamCompletionIfNeeded() {
        guard phase == .sealing else { return }

        if viewModel.isSealingComplete {
            streamTask = nil
            return
        }

        if let ankyId = viewModel.sealingAnkyId {
            persistStoredSubmissionIfNeeded(ankyId: ankyId)
            persistArtifacts()
            deliverStreamedOutcomeIfPossible(markComplete: true)
            reconcileCanonicalArchive(pollUntilSettled: true, markComplete: true)
            transitionToSealed()
            streamTask = nil
            return
        }

        handleStreamFailure(stage: "persist")
    }

    private func handleStreamFailure(stage: String) {
        submitErrorMessage = "something went wrong. your writing is saved."
        streamTask?.cancel()
        streamTask = nil

        guard stage == "claude" || stage == "persist" else {
            transitionToSealed()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            onSkip()
        }
    }

    private func persistStoredSubmissionIfNeeded(ankyId: String) {
        guard !didPersistStoredSubmission else { return }
        didPersistStoredSubmission = true

        Task {
            await appState.storeCanonicalAcceptedSubmission(
                for: capture.sessionId,
                backendAnkyId: ankyId
            )
            await DailyPromptNotificationManager.scheduleWithPrompt(appState.prompt)
            DailyPromptNotificationManager.clearPendingSession()
            WritingFlowModel.autoMintCNFT(sessionId: capture.sessionId, appState: appState)
            WritingFlowModel.archiveToArweave(sessionId: capture.sessionId, text: capture.text)
        }
    }

    private func persistArtifacts() {
        appState.storeGeneratedArtifacts(
            for: capture.sessionId,
            reflection: fullReflection.isEmpty ? nil : fullReflection,
            ankyTitle: titleText,
            ankyImagePath: streamedImageURL
        )

        if !fullReflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AnkyNameStore.updateFromReflection(fullReflection)
        }
    }

    private func reconcileCanonicalArchive(
        pollUntilSettled: Bool,
        markComplete: Bool
    ) {
        Task {
            guard let updated = await appState.reconcileCanonicalArchiveRecord(
                sessionId: capture.sessionId,
                pollUntilSettled: pollUntilSettled
            ) else {
                return
            }

            await MainActor.run {
                absorbArchiveRecord(updated, markComplete: markComplete)
            }
        }
    }

    private func absorbArchiveRecord(
        _ record: LocalArchiveRecord,
        markComplete: Bool
    ) {
        if let title = record.sessionBundle.title3Words?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            titleText = title
        }

        if let reflection = record.sessionBundle.reflection?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reflection.isEmpty {
            fullReflection = reflection
            viewModel.replaceSealingReflection(reflection)
        }

        if let imageLocator = record.sessionBundle.image?.canonicalLocator?.trimmingCharacters(in: .whitespacesAndNewlines),
           !imageLocator.isEmpty {
            streamedImageURL = imageLocator
        }

        persistArtifacts()
        deliverStreamedOutcomeIfPossible(markComplete: markComplete)
    }

    private func deliverStreamedOutcomeIfPossible(markComplete: Bool) {
        let reflection = fullReflection.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageURL = streamedImageURL?.trimmingCharacters(in: .whitespacesAndNewlines)

        if !didDeliverReflectionToChat, !reflection.isEmpty, let imageURL, !imageURL.isEmpty {
            didDeliverReflectionToChat = true
            didDeliverImageToChat = true
            Task {
                await viewModel.deliverWritingOutcome(reflection: reflection, imageURL: imageURL)
            }
            return
        }

        if !didDeliverReflectionToChat, !reflection.isEmpty {
            didDeliverReflectionToChat = true
            Task {
                await viewModel.deliverWritingOutcome(reflection: reflection, imageURL: nil)
            }
        }

        if didDeliverReflectionToChat,
           !didDeliverImageToChat,
           let imageURL,
           !imageURL.isEmpty,
           (markComplete || !reflection.isEmpty) {
            didDeliverImageToChat = true
            viewModel.isAnkyTyping = true
            Task {
                await viewModel.deliverWritingOutcome(reflection: "", imageURL: imageURL)
            }
        }
    }

    private func transitionToSealed() {
        guard phase != .sealed else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            phase = .sealed
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func completeSealingFlow() {
        guard phase == .sealed else { return }
        phase = .done
        onComplete()
    }

    private func skipSealingFlow() {
        onSkip()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded(.down)), 0)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func previewSentence(from reflection: String) -> String {
        let trimmed = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let periodIndex = trimmed.firstIndex(of: ".") {
            return String(trimmed[...periodIndex])
        }

        if trimmed.count > 120 {
            let endIndex = trimmed.index(trimmed.startIndex, offsetBy: 120)
            return String(trimmed[..<endIndex]) + "…"
        }

        return trimmed
    }
}

private struct SealingCirclesView: View {
    let accent: Color
    let emojiSize: CGFloat
    let pulsing: Bool
    let animatePulse: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.2), lineWidth: 1)
                .frame(width: 120, height: 120)

            Circle()
                .stroke(accent.opacity(0.33), lineWidth: 1)
                .frame(width: 88, height: 88)

            Circle()
                .fill(accent.opacity(0.07))
                .frame(width: 56, height: 56)

            Text("🦋")
                .font(.system(size: emojiSize))
        }
        .scaleEffect(pulsing ? (animatePulse ? 1.04 : 1.0) : 1.0)
    }
}

private struct SealingStatView: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 18, weight: .ultraLight))
                .foregroundStyle(Color(hex: "d4c8b8"))

            Text(label)
                .font(.ankyBody(8))
                .foregroundStyle(Color(hex: "444444"))
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SealingAnimatedDotsView: View {
    let color: Color
    @State private var animate = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color.opacity(animate ? 0.85 : 0.25))
                    .frame(width: 6, height: 6)
                    .animation(
                        .easeInOut(duration: 0.7)
                            .repeatForever()
                            .delay(Double(index) * 0.16),
                        value: animate
                    )
            }
        }
        .onAppear {
            animate = true
        }
    }
}
