//
//  NowRoomView.swift
//  Anky
//
//  Collaborative writing sessions anchored to QR codes.
//  Create mode (slug == nil): prompt input → POST → show QR
//  Join mode (slug != nil): load room → show prompt/image/presence → write
//

import Combine
import CoreImage.CIFilterBuiltins
import CoreLocation
import SwiftUI

// MARK: - ViewModel

@MainActor
final class NowRoomViewModel: ObservableObject {
    @Published var room: NowRoom?
    @Published var isLoading = false
    @Published var error: String?
    @Published var presenceCount = 0

    // Create flow
    @Published var promptInput = ""
    @Published var selectedMode: NowMode = .sticker
    @Published var includeLocation = false
    @Published var createdSlug: String?
    @Published var qrURL: String?

    // Countdown (live mode)
    @Published var countdownRemaining: TimeInterval = 0
    @Published var isCountdownActive = false

    private var heartbeatTimer: Timer?
    private var countdownTimer: Timer?
    private let locationManager = CLLocationManager()

    func createRoom() async {
        let trimmed = promptInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        error = nil

        var latitude: Double?
        var longitude: Double?
        if includeLocation {
            locationManager.requestWhenInUseAuthorization()
            let loc = locationManager.location
            latitude = loc?.coordinate.latitude
            longitude = loc?.coordinate.longitude
        }

        do {
            let response = try await AnkyAPI.shared.createNow(
                CreateNowRequest(
                    prompt: trimmed,
                    mode: selectedMode,
                    latitude: latitude,
                    longitude: longitude
                )
            )
            createdSlug = response.slug
            qrURL = response.qrUrl
            // Load the room state
            await loadRoom(slug: response.slug)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func loadRoom(slug: String) async {
        isLoading = room == nil
        error = nil

        do {
            let loaded = try await AnkyAPI.shared.getNowRoom(slug: slug)
            room = loaded
            presenceCount = loaded.presenceCount ?? 0

            // Join automatically
            let joinResponse = try await AnkyAPI.shared.joinNow(slug: slug)
            presenceCount = joinResponse.presenceCount ?? presenceCount

            // Start heartbeat
            startHeartbeat(slug: slug)

            // If live mode with countdown, start tracking
            if loaded.mode == .live, let startsAt = loaded.startsAt {
                startCountdown(to: startsAt)
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func startLiveSession(slug: String) async {
        do {
            let response = try await AnkyAPI.shared.startNow(slug: slug)
            if let startsAt = response.startsAt {
                startCountdown(to: startsAt)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func startHeartbeat(slug: String) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let response = try? await AnkyAPI.shared.heartbeatNow(slug: slug) {
                    self.presenceCount = response.presenceCount ?? self.presenceCount
                }
            }
        }
    }

    func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func startCountdown(to isoString: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let target = formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString) else { return }

        isCountdownActive = true
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else { timer.invalidate(); return }
                let remaining = target.timeIntervalSinceNow
                if remaining <= 0 {
                    self.countdownRemaining = 0
                    self.isCountdownActive = false
                    timer.invalidate()
                } else {
                    self.countdownRemaining = remaining
                }
            }
        }
    }
}

// MARK: - View

struct NowRoomView: View {
    let slug: String?
    let onStartWriting: (String) -> Void

    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = NowRoomViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isLoading && viewModel.room == nil && viewModel.createdSlug == nil {
                ProgressView()
                    .tint(.white)
            } else if let room = viewModel.room {
                roomView(room)
            } else if slug == nil {
                createView
            } else if let error = viewModel.error {
                errorView(error)
            }
        }
        .onAppear {
            if let slug {
                Task { await viewModel.loadRoom(slug: slug) }
            }
        }
        .onDisappear {
            viewModel.stopHeartbeat()
        }
    }

    // MARK: - Create Flow

    private var createView: some View {
        VStack(spacing: 24) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                Spacer()
                Text("create a now")
                    .font(.custom("Georgia", size: 18))
                    .foregroundStyle(Color.white.opacity(0.88))
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 12) {
                Text("prompt")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))

                TextField("what should people write about?", text: $viewModel.promptInput, axis: .vertical)
                    .font(.custom("Georgia", size: 17))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(2...5)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                    )
            }
            .padding(.horizontal, 20)

            // Mode picker
            VStack(alignment: .leading, spacing: 12) {
                Text("mode")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))

                HStack(spacing: 12) {
                    modeButton(.sticker, label: "sticker", icon: "note.text", description: "async — scan anytime")
                    modeButton(.live, label: "live", icon: "person.3.fill", description: "gather & write together")
                }
            }
            .padding(.horizontal, 20)

            // Location toggle
            Toggle(isOn: $viewModel.includeLocation) {
                HStack(spacing: 10) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "f0b35a"))
                    Text("anchor to this place")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.82))
                }
            }
            .tint(Color(hex: "f0b35a"))
            .padding(.horizontal, 20)

            Spacer()

            // Create button
            Button {
                Task { await viewModel.createRoom() }
            } label: {
                Group {
                    if viewModel.isLoading {
                        ProgressView().tint(.black)
                    } else {
                        Text("create")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(hex: "f0b35a"))
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.promptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
            .opacity(viewModel.promptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            .padding(.horizontal, 20)
            .padding(.bottom, 34)
        }
    }

    private func modeButton(_ mode: NowMode, label: String, icon: String, description: String) -> some View {
        Button {
            viewModel.selectedMode = mode
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .foregroundStyle(viewModel.selectedMode == mode ? Color(hex: "f0b35a") : Color.white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(viewModel.selectedMode == mode ? Color(hex: "f0b35a").opacity(0.12) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        viewModel.selectedMode == mode ? Color(hex: "f0b35a").opacity(0.4) : Color.white.opacity(0.06),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Room View

    /// Whether it's time to write: sticker mode always, live mode after countdown.
    private var isWritePhase: Bool {
        guard let room = viewModel.room else { return false }
        if room.mode == .sticker { return true }
        // Live mode: write phase starts when countdown is done
        return !viewModel.isCountdownActive && viewModel.countdownRemaining <= 0 && (room.started == true || viewModel.createdSlug != nil)
    }

    private func roomView(_ room: NowRoom) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)

                Spacer()

                // Presence count (visible before write phase)
                if !isWritePhase {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green.opacity(0.8))
                            .frame(width: 8, height: 8)
                        Text("\(viewModel.presenceCount)")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.72))
                    }
                }

                Spacer()

                // Share button
                if let slug = viewModel.createdSlug ?? slug {
                    ShareLink(item: URL(string: "https://anky.app/n/\(slug)")!) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            if isWritePhase {
                // WRITE PHASE: show prompt, image, previous writings, write button
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        Text(room.prompt)
                            .font(.custom("Georgia", size: 22))
                            .lineSpacing(8)
                            .foregroundStyle(Color.white.opacity(0.92))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 12)

                        promptImage(room)

                        if let sessions = room.sessions, !sessions.isEmpty {
                            writingsSection(sessions)
                        }
                    }
                    .padding(.bottom, 120)
                }

                Spacer(minLength: 0)

                writeButton(room)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 34)
            } else {
                // WAITING PHASE: countdown, QR, presence — prompt hidden
                Spacer()

                if viewModel.isCountdownActive {
                    countdownView
                }

                if let activeSlug = viewModel.createdSlug ?? slug {
                    qrCodeView(slug: activeSlug)
                }

                Spacer()

                // Start countdown button (live mode, creator only, not yet started)
                if room.mode == .live && viewModel.createdSlug != nil && room.started != true && !viewModel.isCountdownActive {
                    Button {
                        Task { await viewModel.startLiveSession(slug: viewModel.createdSlug ?? slug ?? room.slug) }
                    } label: {
                        Text("start countdown")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(hex: "f0b35a"))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 34)
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isWritePhase)
    }

    @ViewBuilder
    private func promptImage(_ room: NowRoom) -> some View {
        if let imageUrl = room.promptImageUrl, let url = URL(string: imageUrl) {
            AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                default:
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .frame(height: 200)
                        .overlay(ProgressView().tint(.white.opacity(0.3)))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
        } else if room.promptImageStatus != "ready" {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .frame(height: 200)
                .overlay(
                    VStack(spacing: 8) {
                        ProgressView().tint(.white.opacity(0.3))
                        Text("generating image...")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                )
                .padding(.horizontal, 20)
        }
    }

    private func qrCodeView(slug: String) -> some View {
        VStack(spacing: 12) {
            if let qrImage = generateQRCode(from: "https://anky.app/n/\(slug)") {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Text("scan to join")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.42))
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
        )
    }

    private var countdownView: some View {
        VStack(spacing: 6) {
            Text("starting in")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.5))

            let seconds = max(Int(viewModel.countdownRemaining.rounded(.up)), 0)
            Text("\(seconds)")
                .font(.system(size: 64, weight: .thin, design: .monospaced))
                .foregroundStyle(Color(hex: "f0b35a"))
                .contentTransition(.numericText())
                .animation(.linear(duration: 0.1), value: seconds)
        }
        .padding(.vertical, 20)
    }

    private func writingsSection(_ sessions: [NowSession]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(sessions.count) writing\(sessions.count == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.horizontal, 20)

            ForEach(sessions, id: \.stableId) { session in
                VStack(alignment: .leading, spacing: 6) {
                    if let name = session.displayName {
                        Text(name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    if let preview = session.preview {
                        Text(preview)
                            .font(.system(size: 15))
                            .lineLimit(3)
                            .foregroundStyle(Color.white.opacity(0.82))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .padding(.horizontal, 20)
            }
        }
    }

    private func writeButton(_ room: NowRoom) -> some View {
        let activeSlug = viewModel.createdSlug ?? slug ?? room.slug

        return Button {
            onStartWriting(activeSlug)
        } label: {
            Text("write")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(hex: "f0b35a"))
                )
        }
        .buttonStyle(.plain)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text("something went wrong")
                .font(.custom("Georgia", size: 18))
                .foregroundStyle(Color.white.opacity(0.82))
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.5))
                .multilineTextAlignment(.center)
            Button { dismiss() } label: {
                Text("close")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }

    // MARK: - QR Code Generator

    private func generateQRCode(from string: String) -> UIImage? {
        guard let data = string.data(using: .ascii) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaled = output.transformed(by: transform)
        return UIImage(ciImage: scaled)
    }
}
