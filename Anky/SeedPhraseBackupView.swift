//
//  SeedPhraseBackupView.swift
//  Anky
//

import SwiftUI
import UIKit

struct SeedPhraseBackupView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var phase: BackupPhase = .intro
    @State private var pulseOpacity: Double = 0.03
    @State private var wordsVisible: [Bool] = Array(repeating: false, count: 12)

    private enum BackupPhase {
        case intro, reveal, confirm, done
    }

    private var words: [String] {
        (appState.pendingMnemonic ?? "").split(separator: " ").map(String.init)
    }

    private var glowTint: Color {
        phase == .done ? .green : .ankyGold
    }

    var body: some View {
        Group {
            switch phase {
            case .intro:    introPhase
            case .reveal:   revealPhase
            case .confirm:  confirmPhase
            case .done:     donePhase
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Color(hex: "0d0d10")

                // Ambient radial pulse
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [glowTint.opacity(pulseOpacity), .clear],
                            center: .center,
                            startRadius: 40,
                            endRadius: 320
                        )
                    )
                    .frame(width: 640, height: 640)
                    .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: pulseOpacity)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            pulseOpacity = 0.05
        }
    }

    // MARK: - Intro

    private var introPhase: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("twelve words, the key beneath the key")
                .font(.ankyDisplay(22))
                .italic()
                .foregroundStyle(Color.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 16) {
                Text("your key is encrypted in iCloud Keychain and syncs across your apple devices. these twelve words are for the day iCloud isn't enough — a lost account, a new device outside apple, or full ownership of your identity.")
                    .font(.ankyBody(15))
                    .lineSpacing(6)
                    .foregroundStyle(Color.ankyMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("write them on paper. never screenshot them.")
                    .font(.ankyBody(13))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                SwipeToConfirmView(label: "swipe to reveal your words") {
                    transition(to: .reveal)
                }

                Text("make sure no one is watching your screen")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.25))
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Reveal

    private var revealPhase: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                Spacer().frame(height: 40)

                Text("your recovery phrase")
                    .font(.ankyDisplay(18))
                    .foregroundStyle(Color.white.opacity(0.78))

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.ankyMono(12))
                                .foregroundStyle(Color.white.opacity(0.3))
                                .frame(width: 20, alignment: .trailing)

                            Text(word)
                                .font(.ankyMono(16))
                                .foregroundStyle(Color.white.opacity(0.92))

                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                        .opacity(wordsVisible[safe: index] == true ? 1 : 0)
                        .offset(y: wordsVisible[safe: index] == true ? 0 : 8)
                        .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.06), value: wordsVisible)
                    }
                }

                // Warning box
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ankyGold)

                    Text("write these 12 words in order on paper. they won't be shown again after you secure.")
                        .font(.ankyBody(13))
                        .lineSpacing(4)
                        .foregroundStyle(Color.ankyGold.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.ankyGold.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.ankyGold.opacity(0.18), lineWidth: 0.8)
                )

                SwipeToConfirmView(label: "i've written them down") {
                    transition(to: .confirm)
                }
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .onAppear {
            revealWords()
        }
    }

    // MARK: - Confirm

    private var confirmPhase: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(Color.ankyGold)

            Text("ready to secure?")
                .font(.ankyDisplay(22))
                .foregroundStyle(Color.white.opacity(0.88))

            Text("this will delete the phrase from this device and lock your key into iCloud Keychain. the words you wrote on paper become the key beneath the key.")
                .font(.ankyBody(15))
                .lineSpacing(6)
                .foregroundStyle(Color.ankyMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            VStack(spacing: 16) {
                SwipeToConfirmView(label: "secure to iCloud and delete") {
                    completeBackup()
                }

                Button {
                    wordsVisible = Array(repeating: false, count: 12)
                    transition(to: .reveal)
                } label: {
                    Text("show me the words again")
                        .font(.ankyBody(14))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    // MARK: - Done

    private var donePhase: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.green)

            Text("your identity is secured")
                .font(.ankyDisplay(22))
                .foregroundStyle(Color.white.opacity(0.88))

            Text("the recovery phrase has been deleted from this device. your key is encrypted in iCloud Keychain. the words on paper are the key beneath the key.")
                .font(.ankyBody(15))
                .lineSpacing(6)
                .foregroundStyle(Color.ankyMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("return to writing")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        }
    }

    // MARK: - Helpers

    private func transition(to newPhase: BackupPhase) {
        withAnimation(.easeInOut(duration: 0.4)) {
            phase = newPhase
        }
    }

    private func revealWords() {
        for i in 0..<12 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
                wordsVisible[i] = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func completeBackup() {
        SeedIdentityManager.shared.markBackupCompleted()
        appState.hasBackedUpPhrase = true
        appState.pendingMnemonic = nil
        transition(to: .done)
    }
}
