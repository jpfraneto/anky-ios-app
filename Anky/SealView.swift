//
//  SealView.swift
//  Anky
//

import Combine
import SwiftUI
import UIKit

@MainActor
private enum SealPalette {
    static let hexColors = [
        "CC2222", // Primordia
        "E87020", // Emblazion
        "D4A017", // Chryseos
        "2D9E2D", // Eleasis
        "3399FF", // Voxlumis
        "7744CC", // Insightia
        "B388FF", // Claridium
        "E0D8C8", // Poiesis
    ]

    static let colors = hexColors.map(Color.init(hex:))
    static let uiColors = hexColors.map(UIColor.init(hex:))

    static var finalColor: UIColor {
        uiColors.last ?? .white
    }

    static func color(at progress: Double) -> Color {
        Color(uiColor: uiColor(at: progress))
    }

    static func uiColor(at progress: Double) -> UIColor {
        let clamped = min(max(progress, 0), 1)
        guard uiColors.count > 1 else { return uiColors.first ?? .white }

        let scaled = clamped * Double(uiColors.count - 1)
        let lowerIndex = Int(floor(scaled))
        let upperIndex = min(lowerIndex + 1, uiColors.count - 1)
        let blend = scaled - Double(lowerIndex)

        return uiColors[lowerIndex].blended(with: uiColors[upperIndex], fraction: blend)
    }
}

@MainActor
private enum ScreenFlash {
    static func flash(color: UIColor, duration: TimeInterval = 0.42) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: \.isKeyWindow) else {
            return
        }

        let flashView = UIView(frame: window.bounds)
        flashView.backgroundColor = color
        flashView.alpha = 0
        flashView.isUserInteractionEnabled = false
        window.addSubview(flashView)

        UIView.animate(
            withDuration: duration * 0.22,
            delay: 0,
            options: [.curveEaseOut]
        ) {
            flashView.alpha = 0.9
        } completion: { _ in
            UIView.animate(
                withDuration: duration * 0.78,
                delay: 0,
                options: [.curveEaseIn]
            ) {
                flashView.alpha = 0
            } completion: { _ in
                flashView.removeFromSuperview()
            }
        }
    }
}

struct SealView: View {
    let label: String
    var isEnabled: Bool
    var onInteractionChanged: ((Bool) -> Void)?
    var onSeal: () -> Void

    @State private var dragProgress = 0.0
    @State private var visualProgress = 0.0
    @State private var dragStartedAt: Date?
    @State private var isDragging = false
    @State private var hasCompleted = false
    @State private var lastHapticColorIndex = -1

    private let minimumDuration: TimeInterval = 8
    private let knobSize: CGFloat = 42
    private let trackHeight: CGFloat = 46
    private let horizontalInset: CGFloat = 4
    private let timer = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect()

    init(
        label: String,
        isEnabled: Bool = true,
        onSeal: @escaping () -> Void,
        onInteractionChanged: ((Bool) -> Void)? = nil
    ) {
        self.label = label
        self.isEnabled = isEnabled
        self.onInteractionChanged = onInteractionChanged
        self.onSeal = onSeal
    }

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = proxy.size.width
            let maxTravel = max(trackWidth - knobSize - (horizontalInset * 2), 1)
            let knobOffset = CGFloat(visualProgress) * maxTravel
            let progressWidth = knobOffset + knobSize + horizontalInset
            let activeColor = SealPalette.color(at: visualProgress)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
                    .fill(Color.white.opacity(isEnabled ? 0.06 : 0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
                            .stroke(activeColor.opacity(isDragging || hasCompleted ? 0.32 : 0.12), lineWidth: 0.7)
                    )

                RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: SealPalette.colors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .mask(alignment: .leading) {
                        RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
                            .frame(width: progressWidth)
                    }
                    .opacity(isEnabled ? 0.82 : 0.22)

                Text(label)
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .foregroundStyle(Color.white.opacity(isEnabled ? 0.68 : 0.24))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 52)

                Circle()
                    .fill(activeColor)
                    .frame(width: knobSize, height: knobSize)
                    .overlay(
                        Image(systemName: hasCompleted ? "checkmark" : "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.78))
                    )
                    .shadow(color: activeColor.opacity(0.45), radius: 18, y: 0)
                    .offset(x: horizontalInset + knobOffset)
                    .gesture(dragGesture(maxTravel: maxTravel))
            }
            .animation(.linear(duration: 0.02), value: visualProgress)
        }
        .frame(height: trackHeight)
        .opacity(isEnabled ? 1 : 0.72)
        .onReceive(timer) { now in
            guard isDragging, let dragStartedAt else { return }
            syncVisualProgress(now: now, dragStartedAt: dragStartedAt)
        }
    }

    private func dragGesture(maxTravel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEnabled, !hasCompleted else { return }

                if !isDragging {
                    let now = Date()
                    dragStartedAt = now
                    isDragging = true
                    onInteractionChanged?(true)
                }

                dragProgress = min(max(Double(value.translation.width / maxTravel), 0), 1)
                syncVisualProgress(now: Date(), dragStartedAt: dragStartedAt ?? Date())
            }
            .onEnded { _ in
                guard !hasCompleted else { return }
                reset()
            }
    }

    private func syncVisualProgress(now: Date, dragStartedAt: Date) {
        let elapsedProgress = min(max(now.timeIntervalSince(dragStartedAt) / minimumDuration, 0), 1)
        visualProgress = min(dragProgress, elapsedProgress)

        // Haptic tick each time we cross into a new chakra color band
        let colorCount = SealPalette.colors.count
        let colorIndex = min(Int(visualProgress * Double(colorCount)), colorCount - 1)
        if colorIndex > lastHapticColorIndex && colorIndex > 0 {
            lastHapticColorIndex = colorIndex
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.3 + 0.1 * Double(colorIndex))
        }

        if dragProgress >= 0.999, elapsedProgress >= 0.999 {
            completeSeal()
        }
    }

    private func completeSeal() {
        guard !hasCompleted else { return }
        hasCompleted = true
        isDragging = false
        dragStartedAt = nil
        dragProgress = 1
        visualProgress = 1
        onInteractionChanged?(false)

        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        ScreenFlash.flash(color: SealPalette.finalColor)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            onSeal()
        }
    }

    private func reset() {
        dragStartedAt = nil
        isDragging = false
        lastHapticColorIndex = -1
        onInteractionChanged?(false)

        withAnimation(.easeOut(duration: 0.22)) {
            dragProgress = 0
            visualProgress = 0
        }
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    func blended(with color: UIColor, fraction: Double) -> UIColor {
        let fraction = min(max(fraction, 0), 1)

        var lhsRed: CGFloat = 0
        var lhsGreen: CGFloat = 0
        var lhsBlue: CGFloat = 0
        var lhsAlpha: CGFloat = 0
        var rhsRed: CGFloat = 0
        var rhsGreen: CGFloat = 0
        var rhsBlue: CGFloat = 0
        var rhsAlpha: CGFloat = 0

        getRed(&lhsRed, green: &lhsGreen, blue: &lhsBlue, alpha: &lhsAlpha)
        color.getRed(&rhsRed, green: &rhsGreen, blue: &rhsBlue, alpha: &rhsAlpha)

        return UIColor(
            red: lhsRed + ((rhsRed - lhsRed) * fraction),
            green: lhsGreen + ((rhsGreen - lhsGreen) * fraction),
            blue: lhsBlue + ((rhsBlue - lhsBlue) * fraction),
            alpha: lhsAlpha + ((rhsAlpha - lhsAlpha) * fraction)
        )
    }
}
