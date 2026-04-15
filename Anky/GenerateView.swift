//
//  GenerateView.swift
//  Anky
//

import SwiftUI
import Combine
import Photos
import UIKit

@MainActor
final class GenerateViewModel: ObservableObject {
    enum StatusTone {
        case neutral
        case success
        case error

        var foregroundColor: Color {
            switch self {
            case .neutral:
                return Color.white.opacity(0.76)
            case .success:
                return Color(hex: "f0b35a")
            case .error:
                return Color(hex: "ff9e9e")
            }
        }

        var backgroundColor: Color {
            switch self {
            case .neutral:
                return Color.white.opacity(0.05)
            case .success:
                return Color(hex: "2a2112")
            case .error:
                return Color(hex: "2a1515")
            }
        }
    }

    @Published var prompt = ""
    @Published var selectedAspectRatio = "1:1"
    @Published var isGenerating = false
    @Published var isLoading = true
    @Published var statusMessage: String?
    @Published var statusTone: StatusTone = .neutral
    @Published var pendingGenerationIDs: [String] = GeneratedAnkyStore.loadPendingGenerationIDs()
    @Published var activeGenerationPrompt: String?
    @Published var latestPendingPrompt: String?
    @Published var myGallery: [GeneratedAnky] = GeneratedAnkyStore.loadCompleted()
    @Published var publicGallery: [GeneratedAnky] = []
    @Published var selectedAnky: GeneratedAnky?

    private var pollTasks: [String: Task<Void, Never>] = [:]
    private var hasLoadedOnce = false

    deinit {
        for task in pollTasks.values {
            task.cancel()
        }
    }

    func load() async {
        guard !hasLoadedOnce else { return }
        hasLoadedOnce = true
        syncPendingGenerations()
        await refresh()
        resumePendingGenerations()
    }

    var hasPendingGenerations: Bool {
        !pendingGenerationIDs.isEmpty
    }

    var showsGenerationActivity: Bool {
        isGenerating || hasPendingGenerations
    }

    var activityHeadline: String {
        let count = pendingGenerationIDs.count + (isGenerating ? 1 : 0)
        return count == 1 ? "Generating 1 anky" : "Generating \(count) ankys"
    }

    var activityBody: String {
        if isGenerating && pendingGenerationIDs.isEmpty {
            return "Your prompt is being sent to Flux now. Stay here. The collage will fill in as soon as the backend hands back a generation id."
        }

        if pendingGenerationIDs.count == 1 {
            return "This image is still rendering on the backend. The collage below will update the second it lands."
        }
        return "These images are still rendering on the backend. The collage below will update as each one finishes."
    }

    var generationPlaceholderCount: Int {
        pendingGenerationIDs.count + (isGenerating ? 1 : 0)
    }

    var activityPromptPreview: String? {
        activeGenerationPrompt ?? latestPendingPrompt
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        async let publicFetch: Void = loadPublicGallery()
        async let myFetch: Void = loadMyGallery()
        _ = await (publicFetch, myFetch)
    }

    func generate() async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusTone = .error
            statusMessage = "describe what Anky is doing, feeling, or becoming."
            return
        }

        isGenerating = true
        activeGenerationPrompt = trimmed
        defer {
            isGenerating = false
            activeGenerationPrompt = nil
        }

        statusTone = .neutral
        statusMessage = "sending to flux..."

        do {
            let response = try await AnkyAPI.shared.generateAnky(
                writing: normalizedPrompt(from: trimmed),
                aspectRatio: selectedAspectRatio
            )

            if let error = response.error?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty {
                statusTone = .error
                statusMessage = error
                return
            }

            guard let ankyID = response.ankyId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !ankyID.isEmpty else {
                statusTone = .error
                statusMessage = "the server did not return a generation id."
                return
            }

            rememberPendingGeneration(id: ankyID, promptPreview: trimmed)
            prompt = ""
            statusTone = .neutral
            statusMessage = "generation queued. anky is rendering now."
            startPolling(ankyID, silent: false)
        } catch let error as AnkyError {
            statusTone = .error
            statusMessage = error.errorDescription ?? "generation failed."
        } catch {
            statusTone = .error
            statusMessage = error.localizedDescription
        }
    }

    private func loadPublicGallery() async {
        do {
            let items = try await AnkyAPI.shared.generatedAnkyGallery()
                .filter { $0.remoteImageURL != nil }
            publicGallery = dedupe(items)
            ImagePrefetcher.prefetch(urls: publicGallery.prefix(18).compactMap(\.remoteImageURL))
        } catch {
            if publicGallery.isEmpty, statusMessage == nil {
                statusTone = .neutral
                statusMessage = "the gallery is quiet right now."
            }
        }
    }

    private func loadMyGallery() async {
        var merged = GeneratedAnkyStore.loadCompleted()

        do {
            let remoteItems = try await AnkyAPI.shared.myGeneratedAnkys()
                .filter { $0.remoteImageURL != nil }
            merged = dedupe(remoteItems + merged)
            _ = GeneratedAnkyStore.mergeCompleted(remoteItems)
        } catch {
            // Keep the local gallery as the fallback source of truth.
        }

        myGallery = merged
        ImagePrefetcher.prefetch(urls: myGallery.prefix(12).compactMap(\.remoteImageURL))
    }

    private func resumePendingGenerations() {
        syncPendingGenerations()
        let pendingIDs = pendingGenerationIDs
        guard !pendingIDs.isEmpty else { return }

        statusTone = .neutral
        statusMessage = "checking pending ankys..."

        for id in pendingIDs {
            startPolling(id, silent: true)
        }
    }

    private func normalizedPrompt(from prompt: String) -> String {
        if prompt.range(of: "anky", options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return prompt
        }
        return "anky \(prompt)"
    }

    private func startPolling(_ id: String, silent: Bool) {
        guard pollTasks[id] == nil else { return }

        pollTasks[id] = Task { [weak self] in
            guard let self else { return }
            await self.pollForGeneratedAnky(id: id, silent: silent)
            self.pollTasks[id] = nil
        }
    }

    private func pollForGeneratedAnky(id: String, silent: Bool) async {
        for attempt in 0..<60 {
            guard !Task.isCancelled else { return }

            do {
                let anky = try await AnkyAPI.shared.getGeneratedAnky(id: id)
                let status = anky.status?.lowercased() ?? ""
                let isReady = ["complete", "completed", "ready", "generated", "done"].contains(status)
                let isFailed = ["failed", "error", "cancelled", "canceled"].contains(status)

                if isReady, anky.remoteImageURL != nil {
                    _ = GeneratedAnkyStore.upsertCompleted(anky)
                    forgetPendingGeneration(id: id)
                    myGallery = dedupe([anky] + myGallery)
                    publicGallery = dedupe([anky] + publicGallery)
                    ImagePrefetcher.prefetch(urls: [anky.remoteImageURL].compactMap { $0 })

                    if !silent {
                        statusTone = .success
                        statusMessage = "your anky is ready."
                    }

                    return
                }

                if isFailed {
                    forgetPendingGeneration(id: id)
                    if !silent {
                        statusTone = .error
                        statusMessage = "generation failed. try again in a minute."
                    }
                    return
                }
            } catch {
                // Keep polling. The backend can lag behind queue creation.
            }

            if attempt < 59 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }

        if !silent {
            statusTone = .neutral
            statusMessage = "still generating. come back in a moment."
        }
    }

    private func dedupe(_ items: [GeneratedAnky]) -> [GeneratedAnky] {
        var seen = Set<String>()
        return items
            .filter { item in
                seen.insert(item.id).inserted
            }
            .sorted { ($0.createdAtDate ?? .distantPast) > ($1.createdAtDate ?? .distantPast) }
    }

    private func syncPendingGenerations() {
        pendingGenerationIDs = GeneratedAnkyStore.loadPendingGenerationIDs()
        if pendingGenerationIDs.isEmpty {
            latestPendingPrompt = nil
        }
    }

    private func rememberPendingGeneration(id: String, promptPreview: String?) {
        GeneratedAnkyStore.rememberPendingGeneration(id: id)
        syncPendingGenerations()

        if let promptPreview {
            let trimmed = promptPreview.trimmingCharacters(in: .whitespacesAndNewlines)
            latestPendingPrompt = trimmed.isEmpty ? nil : trimmed
        }
    }

    private func forgetPendingGeneration(id: String) {
        GeneratedAnkyStore.forgetPendingGeneration(id: id)
        syncPendingGenerations()
    }
}

struct GenerateView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = GenerateViewModel()
    @FocusState private var isPromptFocused: Bool

    private let collageColumns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
    ]

    private var publicGalleryWithoutMine: [GeneratedAnky] {
        let myIDs = Set(viewModel.myGallery.map(\.id))
        return viewModel.publicGallery.filter { !myIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header
                promptComposer

                if viewModel.showsGenerationActivity {
                    generationActivitySection
                }

                if let statusMessage = viewModel.statusMessage {
                    statusCard(statusMessage)
                }

                if !viewModel.myGallery.isEmpty {
                    gallerySection(
                        title: "Yours",
                        subtitle: "ankys born from this side of the bridge",
                        items: viewModel.myGallery
                    )
                }

                gallerySection(
                    title: "Gallery",
                    subtitle: "a running collage of generated ankys",
                    items: publicGalleryWithoutMine,
                    showEmptyState: !viewModel.isLoading
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(Color.ankyVoid.ignoresSafeArea())
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(item: $viewModel.selectedAnky) { anky in
            GeneratedAnkyDetailView(anky: anky)
                .sheetStyleBackground(Color.ankyVoid)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text("generate")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.94))

                Text("native flux generation and anky collage")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.42))
            }

            Spacer(minLength: 0)
        }
    }

    private var promptComposer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Prompt")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.62))

            ZStack(alignment: .topLeading) {
                if viewModel.prompt.isEmpty {
                    Text("describe where anky is, what anky feels, or what anky becomes...")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.white.opacity(0.24))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                }

                TextEditor(text: $viewModel.prompt)
                    .focused($isPromptFocused)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(minHeight: 124)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.clear)
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(hex: "141416"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("Aspect Ratio")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.62))

                HStack(spacing: 10) {
                    ForEach(["1:1", "16:9", "9:16"], id: \.self) { ratio in
                        Button {
                            viewModel.selectedAspectRatio = ratio
                        } label: {
                            Text(ratio)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(
                                    viewModel.selectedAspectRatio == ratio
                                    ? Color.black.opacity(0.82)
                                    : Color.white.opacity(0.86)
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(
                                    Capsule()
                                        .fill(
                                            viewModel.selectedAspectRatio == ratio
                                            ? Color(hex: "f0b35a")
                                            : Color.white.opacity(0.06)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                Task { await viewModel.generate() }
            } label: {
                HStack(spacing: 10) {
                    if viewModel.isGenerating {
                        ProgressView()
                            .tint(Color.black.opacity(0.78))
                    }

                    Text(viewModel.isGenerating ? "generating..." : "generate with flux")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(Color.black.opacity(0.82))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(hex: "f0b35a"))
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isGenerating)
            .opacity(viewModel.isGenerating ? 0.82 : 1)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
        )
    }

    private var generationActivitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                ProgressView()
                    .tint(Color(hex: "f0b35a"))
                    .scaleEffect(1.15)

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.activityHeadline)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.94))

                    Text(viewModel.activityBody)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineSpacing(3)
                }
            }

            if let prompt = viewModel.activityPromptPreview {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Latest Prompt")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "f0b35a"))

                    Text(prompt)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.84))
                        .lineLimit(3)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                }
            }

            LazyVGrid(columns: collageColumns, spacing: 6) {
                ForEach(0..<viewModel.generationPlaceholderCount, id: \.self) { _ in
                    PendingGeneratedAnkyCell()
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(hex: "15110d"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(hex: "f0b35a").opacity(0.28), lineWidth: 1)
        )
    }

    private func statusCard(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 14, weight: .medium))
            .lineSpacing(4)
            .foregroundStyle(viewModel.statusTone.foregroundColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(viewModel.statusTone.backgroundColor)
            )
    }

    private func gallerySection(
        title: String,
        subtitle: String,
        items: [GeneratedAnky],
        showEmptyState: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.4))
            }

            if items.isEmpty {
                if showEmptyState {
                    Text("nothing here yet.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .padding(.top, 4)
                } else {
                    collageLoadingGrid
                }
            } else {
                LazyVGrid(columns: collageColumns, spacing: 6) {
                    ForEach(items) { anky in
                        Button {
                            viewModel.selectedAnky = anky
                        } label: {
                            GeneratedAnkyCollageCell(anky: anky)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var collageLoadingGrid: some View {
        LazyVGrid(columns: collageColumns, spacing: 6) {
            ForEach(0..<9, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.04), lineWidth: 1)
                    )
            }
        }
    }
}

private struct PendingGeneratedAnkyCell: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))

            VStack(spacing: 10) {
                ProgressView()
                    .tint(Color(hex: "f0b35a"))

                Text("Generating")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct GeneratedAnkyCollageCell: View {
    let anky: GeneratedAnky

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(Color.white.opacity(0.05))

            if let remoteImageURL = anky.remoteImageURL {
                AsyncImage(url: remoteImageURL, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                    }
                }
            }

            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.7)],
                startPoint: .center,
                endPoint: .bottom
            )

            Text(anky.displayTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(2)
                .padding(8)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct GeneratedAnkyDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let initialAnky: GeneratedAnky
    @State private var anky: GeneratedAnky
    @State private var isLoading = false
    @State private var isSavingToPhotos = false
    @State private var saveMessage: String?
    @State private var saveTone: GenerateViewModel.StatusTone = .neutral

    init(anky: GeneratedAnky) {
        self.initialAnky = anky
        _anky = State(initialValue: anky)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }

                if let remoteImageURL = anky.remoteImageURL {
                    AsyncImage(url: remoteImageURL, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            Rectangle()
                                .fill(Color.white.opacity(0.05))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                }

                if anky.remoteImageURL != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            Task {
                                await saveImageToPhotos()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                if isSavingToPhotos {
                                    ProgressView()
                                        .tint(Color.black.opacity(0.82))
                                } else {
                                    Image(systemName: "arrow.down.to.line.compact")
                                        .font(.system(size: 15, weight: .semibold))
                                }

                                Text(isSavingToPhotos ? "saving to photos..." : "save to photos")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(Color.black.opacity(0.82))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(hex: "f0b35a"))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isSavingToPhotos)
                        .opacity(isSavingToPhotos ? 0.84 : 1)

                        if let saveMessage {
                            Text(saveMessage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(saveTone.foregroundColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(saveTone.backgroundColor)
                                )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(anky.displayTitle)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.94))

                    HStack(spacing: 8) {
                        Text(anky.origin ?? "generated")
                        Text("•")
                        Text(anky.createdAtLabel)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.42))
                }

                if let prompt = anky.displayPrompt {
                    detailBlock(title: "Prompt", body: prompt)
                }

                if let reflection = anky.reflection?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !reflection.isEmpty {
                    detailBlock(title: "Reflection", body: reflection)
                }

                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(Color(hex: "f0b35a"))
                        Text("loading full anky...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(Color.ankyVoid.ignoresSafeArea())
        .task {
            await refresh()
        }
    }

    private func detailBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "f0b35a"))

            Text(body)
                .font(.system(size: 16, weight: .regular))
                .lineSpacing(6)
                .foregroundStyle(Color.white.opacity(0.88))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            anky = try await AnkyAPI.shared.getGeneratedAnky(id: initialAnky.id)
        } catch {
            // Keep showing the initial payload if detail fetch fails.
        }
    }

    private func saveImageToPhotos() async {
        guard let remoteImageURL = anky.remoteImageURL else {
            saveTone = .error
            saveMessage = "there is no image to save yet."
            return
        }

        isSavingToPhotos = true
        defer { isSavingToPhotos = false }

        do {
            try await GeneratedAnkyPhotoLibrary.saveImage(from: remoteImageURL)
            saveTone = .success
            saveMessage = "saved to your photos."
        } catch let error as LocalizedError {
            saveTone = .error
            saveMessage = error.errorDescription ?? "could not save the image."
        } catch {
            saveTone = .error
            saveMessage = error.localizedDescription
        }
    }
}

private enum GeneratedAnkyPhotoLibrary {
    static func saveImage(from remoteImageURL: URL) async throws {
        let (data, response) = try await URLSession.shared.data(from: remoteImageURL)

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw GeneratedAnkyPhotoSaveError.downloadFailed
        }

        guard !data.isEmpty, UIImage(data: data) != nil else {
            throw GeneratedAnkyPhotoSaveError.invalidImage
        }

        let authorization = await requestAddOnlyAuthorization()
        guard authorization == .authorized || authorization == .limited else {
            throw GeneratedAnkyPhotoSaveError.permissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: GeneratedAnkyPhotoSaveError.saveFailed)
                }
            }
        }
    }

    private static func requestAddOnlyAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}

private enum GeneratedAnkyPhotoSaveError: LocalizedError {
    case permissionDenied
    case downloadFailed
    case invalidImage
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "allow photo access to save generated ankys to your device."
        case .downloadFailed:
            return "the image could not be downloaded right now."
        case .invalidImage:
            return "the generated file was not a valid image."
        case .saveFailed:
            return "the image could not be saved to photos."
        }
    }
}
