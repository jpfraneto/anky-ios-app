//
//  QRSealAuthView.swift
//  Anky
//

import SwiftUI

struct QRSealAuthView: View {
    @EnvironmentObject private var appState: AppState

    let challenge: QRSealChallenge

    @State private var phase: Phase = .ready
    @State private var errorMessage: String?

    private let gold = Color(hex: "E8B84B")

    enum Phase {
        case ready
        case submitting
        case sealed
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(hex: "04040D")
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 90)

                heroImage
                    .padding(.horizontal, 34)

                Text(titleText)
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .foregroundStyle(phase == .sealed ? gold : Color.white.opacity(0.9))
                    .padding(.top, 28)

                if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.54))
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                        .padding(.horizontal, 28)
                }

                Spacer()

                VStack(spacing: 16) {
                    switch phase {
                    case .ready:
                        SealView(label: "seal to connect") {
                            submitSeal()
                        }
                    case .submitting:
                        VStack(spacing: 14) {
                            ProgressView()
                                .tint(gold)

                            Text("connecting your browser...")
                                .font(.system(size: 14, weight: .medium, design: .serif))
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 84)
                    case .sealed:
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 42, weight: .bold))
                                .foregroundStyle(gold)

                            Text("sealed")
                                .font(.system(size: 18, weight: .bold, design: .serif))
                                .foregroundStyle(Color.white.opacity(0.86))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 84)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 96)
            }

            closeButton
        }
    }

    private var heroImage: some View {
        AsyncImage(url: URL(string: "https://anky.app/image.png")) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
            case .failure:
                Image("anky-face")
                    .resizable()
                    .scaledToFit()
            case .empty:
                ProgressView()
                    .tint(gold)
                    .frame(maxWidth: .infinity, minHeight: 220)
            @unknown default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .shadow(color: gold.opacity(0.18), radius: 22)
    }

    private var titleText: String {
        switch phase {
        case .ready:
            return "seal to connect"
        case .submitting:
            return "sealing"
        case .sealed:
            return "connected"
        }
    }

    private var closeButton: some View {
        Button {
            appState.dismissQRSealChallenge()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.72))
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 18)
        .padding(.trailing, 18)
    }

    private func submitSeal() {
        phase = .submitting
        errorMessage = nil

        Task {
            do {
                let signature = try SeedIdentityManager.shared.sign(message: Data(challenge.token.utf8))
                let solanaAddress = try SeedIdentityManager.shared.solanaAddress()

                _ = try await AnkyAPI.shared.sealQRChallenge(
                    token: challenge.token,
                    signature: Base58.encode(signature),
                    solanaAddress: solanaAddress
                )

                phase = .sealed

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    appState.dismissQRSealChallenge()
                }
            } catch {
                phase = .ready
                errorMessage = error.localizedDescription
            }
        }
    }
}
