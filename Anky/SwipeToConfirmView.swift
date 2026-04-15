import SwiftUI
import UIKit

struct SwipeToConfirmView: View {
    let label: String
    let onComplete: () -> Void

    @State private var offsetX: CGFloat = 0
    @State private var completed = false
    @State private var showCheckmark = false
    @State private var borderGreen = false
    @State private var shimmerOffset: CGFloat = -1

    private let thumbSize: CGFloat = 56
    private let trackPadding: CGFloat = 4
    private let threshold: CGFloat = 0.85

    // Track which haptic marks have fired during this drag
    @State private var firedMarks: Set<Int> = []

    var body: some View {
        GeometryReader { geo in
            let trackWidth = geo.size.width
            let maxOffset = trackWidth - thumbSize - trackPadding * 2
            let progress = maxOffset > 0 ? offsetX / maxOffset : 0

            ZStack {
                // Track background
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        // Shimmer
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        Color.white.opacity(0.08),
                                        .clear
                                    ],
                                    startPoint: UnitPoint(x: shimmerOffset, y: 0.5),
                                    endPoint: UnitPoint(x: shimmerOffset + 0.3, y: 0.5)
                                )
                            )
                            .opacity(completed ? 0 : 1)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                borderGreen ? Color.green : Color.clear,
                                lineWidth: 2
                            )
                    )

                // Label
                Text(label)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .opacity(completed ? 0 : Double(max(0, 1 - progress * 1.8)))

                // Checkmark on completion
                if showCheckmark {
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.green)
                        .transition(.scale.combined(with: .opacity))
                }

                // Thumb
                if !completed {
                    HStack {
                        Circle()
                            .fill(Color.ankyGold)
                            .frame(width: thumbSize, height: thumbSize)
                            .overlay(
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(Color.ankyVoid)
                            )
                            .offset(x: offsetX)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let newOffset = min(max(0, value.translation.width), maxOffset)
                                        offsetX = newOffset
                                        let currentProgress = newOffset / maxOffset

                                        // Fire haptics at 20% marks
                                        let marks = [20, 40, 60, 80]
                                        for mark in marks {
                                            let markProgress = CGFloat(mark) / 100.0
                                            if currentProgress >= markProgress && !firedMarks.contains(mark) {
                                                firedMarks.insert(mark)
                                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                            }
                                        }

                                        // Fire medium haptic at threshold crossing
                                        if currentProgress >= threshold && !firedMarks.contains(85) {
                                            firedMarks.insert(85)
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        }
                                    }
                                    .onEnded { _ in
                                        let currentProgress = offsetX / maxOffset
                                        if currentProgress >= threshold {
                                            // Snap to end and complete
                                            withAnimation(.easeOut(duration: 0.15)) {
                                                offsetX = maxOffset
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                    completed = true
                                                    showCheckmark = true
                                                    borderGreen = true
                                                }
                                                // Remove green border after a moment
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                                    withAnimation(.easeOut(duration: 0.3)) {
                                                        borderGreen = false
                                                    }
                                                }
                                                onComplete()
                                            }
                                        } else {
                                            // Spring back
                                            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                                            withAnimation(.bouncy) {
                                                offsetX = 0
                                            }
                                        }
                                        firedMarks.removeAll()
                                    }
                            )
                        Spacer()
                    }
                    .padding(.horizontal, trackPadding)
                }
            }
            .frame(height: thumbSize + trackPadding * 2)
        }
        .frame(height: thumbSize + trackPadding * 2 + 8)
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                shimmerOffset = 1.3
            }
        }
    }
}

