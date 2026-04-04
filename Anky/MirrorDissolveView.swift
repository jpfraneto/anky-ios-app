//
//  MirrorDissolveView.swift
//  Anky
//
//  The mirror dissolve animation + reflection card + swipe-to-seal.
//  Plays once after the first completed session.
//

import SwiftUI
import UIKit

// MARK: - Crack Canvas (extracted for type-checker)

private struct CrackCanvas: View {
    let opacity: Double

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let maxDim = max(geo.size.width, geo.size.height)

            Canvas { context, _ in
                for i in 0..<12 {
                    let angle = Double(i) * (.pi / 6)
                    let length = opacity * maxDim * 0.6

                    // Primary crack
                    var primary = Path()
                    primary.move(to: center)
                    let endPoint = CGPoint(
                        x: center.x + cos(angle) * length,
                        y: center.y + sin(angle) * length
                    )
                    primary.addLine(to: endPoint)
                    context.stroke(primary, with: .color(.white.opacity(opacity * 0.8)), lineWidth: 1.5)

                    // Secondary branch cracks
                    if opacity > 0.3 {
                        let branchAngle = angle + .pi / 12
                        let branchStart = CGPoint(
                            x: center.x + cos(angle) * length * 0.4,
                            y: center.y + sin(angle) * length * 0.4
                        )
                        var branch = Path()
                        branch.move(to: branchStart)
                        branch.addLine(to: CGPoint(
                            x: branchStart.x + cos(branchAngle) * length * 0.3,
                            y: branchStart.y + sin(branchAngle) * length * 0.3
                        ))
                        context.stroke(branch, with: .color(.white.opacity(opacity * 0.5)), lineWidth: 0.8)
                    }
                }
            }
        }
    }
}

// MARK: - Collapsing Word

private struct CollapsingWord: View {
    let word: String
    let index: Int
    let total: Int
    let progress: Double
    let centerX: CGFloat
    let centerY: CGFloat

    var body: some View {
        let angle = Double(index) * (2 * .pi / Double(max(total, 1)))
        let radius: CGFloat = 200 * CGFloat(1 - progress)
        let offsetX = cos(angle) * Double(radius)
        let offsetY = sin(angle) * Double(radius)
        let fontSize: CGFloat = max(14 - CGFloat(progress) * 8, 4)
        let wordOpacity = max(0.7 - progress * 0.5, 0.1)

        Text(word)
            .font(.system(size: fontSize, weight: .light, design: .monospaced))
            .foregroundStyle(Color.white.opacity(wordOpacity))
            .offset(x: CGFloat(offsetX), y: CGFloat(offsetY))
    }
}

// MARK: - Mirror Dissolve View (State 3 → 4 → 5)

struct MirrorDissolveView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let capture: LocalWritingCapture
    let sessionText: String

    @State private var phase: DissolvePhase = .textCollapse
    @State private var collapseProgress: Double = 0
    @State private var crackOpacity: Double = 0
    @State private var showReflection = false
    @State private var showSeal = false

    enum DissolvePhase {
        case textCollapse
        case cracking
        case collapse
        case darkness
        case reflection
    }

    private var collapseWords: [String] {
        sessionText.split(separator: " ").prefix(40).map(String.init)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch phase {
            case .textCollapse:
                textCollapseView
            case .cracking:
                crackingView
            case .collapse, .darkness:
                Color.black.ignoresSafeArea()
            case .reflection:
                reflectionView
            }
        }
        .statusBarHidden(true)
        .onAppear {
            runDissolveSequence()
        }
    }

    // MARK: - Text Collapse

    private var textCollapseView: some View {
        ZStack {
            ForEach(Array(collapseWords.enumerated()), id: \.offset) { index, word in
                CollapsingWord(
                    word: word,
                    index: index,
                    total: collapseWords.count,
                    progress: collapseProgress,
                    centerX: 0,
                    centerY: 0
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Cracking

    private var crackingView: some View {
        ZStack {
            Color.black
            CrackCanvas(opacity: crackOpacity)
        }
    }

    // MARK: - Reflection

    private var reflectionView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer(minLength: 80)
                reflectionCard
                reflectionStats
                Spacer().frame(height: 48)
                sealSection
                Spacer(minLength: 60)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var reflectionCard: some View {
        let kingdomName = appState.kingdom.name
        let gradientColors = appState.kingdom.gradientColors

        return RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(height: 200)
            .overlay(
                VStack(spacing: 8) {
                    Text("your first anky")
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.6))

                    Text(kingdomName)
                        .font(.system(size: 28, weight: .light, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.9))

                    Text("kingdom")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .textCase(.uppercase)
                        .kerning(2)
                }
            )
            .padding(.horizontal, 24)
            .opacity(showReflection ? 1 : 0)
            .scaleEffect(showReflection ? 1 : 0.95)
            .animation(.easeOut(duration: 0.8), value: showReflection)
    }

    private var reflectionStats: some View {
        let timestamp = formatTimestamp(capture.finishedAt)
        let words = "\(capture.wordCount) words"
        let kingdom = "\(appState.kingdom.name) kingdom"
        let kingdomColor = appState.kingdom.color

        return VStack(spacing: 4) {
            Text(timestamp)
                .font(.system(size: 13, weight: .light, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.35))

            Text(words)
                .font(.system(size: 13, weight: .light, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.35))

            Text(kingdom)
                .font(.system(size: 13, weight: .light, design: .monospaced))
                .foregroundStyle(kingdomColor.opacity(0.6))
        }
        .padding(.top, 24)
        .opacity(showReflection ? 1 : 0)
        .animation(.easeOut(duration: 0.8).delay(0.3), value: showReflection)
    }

    @ViewBuilder
    private var sealSection: some View {
        if showSeal {
            SwipeToSealView(
                kingdom: appState.kingdom,
                sessionId: capture.sessionId,
                onSealed: { handleSealed() },
                onKeepPrivate: { handleKeepPrivate() }
            )
            .padding(.horizontal, 24)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: - Dissolve Sequence

    private func runDissolveSequence() {
        phase = .textCollapse
        withAnimation(.easeIn(duration: 1.5)) {
            collapseProgress = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            phase = .cracking
            withAnimation(.easeIn(duration: 1.5)) {
                crackOpacity = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            phase = .collapse
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            phase = .darkness
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) {
            phase = .reflection
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showReflection = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showSeal = true
                }
            }
        }
    }

    // MARK: - Actions

    private func handleSealed() {
        appState.setMirrorState(.firstMintComplete)
        appState.markFirstMintComplete()
        appState.markUnlockedPublic()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            appState.route = .unlocked
            dismiss()
        }
    }

    private func handleKeepPrivate() {
        appState.setMirrorState(.firstMintComplete)
        appState.markUnlockedPublic()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            appState.route = .unlocked
            dismiss()
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        return formatter.string(from: date)
    }
}
