import SwiftUI

struct KeyButton: View {
    let label: String
    let phase: SessionPhase
    var isModifier: Bool = false
    var isDisabled: Bool = false
    let onPress: () -> Void

    @State private var isPressed: Bool = false
    @State private var justTapped: Bool = false
    @State private var shakeOffset: CGFloat = 0

    var keyBackground: Color {
        if isModifier {
            return phaseAccentColor(phase).opacity(0.3)
        }
        return Color.white.opacity(phase == .transcendent ? 0.25 : 0.15)
    }

    var activeBackground: Color {
        phaseAccentColor(phase).opacity(0.6)
    }

    var body: some View {
        Button(action: {
            if isDisabled {
                // Shake animation — the key exists but Anky won't let you use it.
                withAnimation(.interpolatingSpring(stiffness: 600, damping: 10)) {
                    shakeOffset = 6
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    withAnimation(.interpolatingSpring(stiffness: 600, damping: 10)) {
                        shakeOffset = -5
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.interpolatingSpring(stiffness: 600, damping: 10)) {
                        shakeOffset = 3
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.interpolatingSpring(stiffness: 600, damping: 10)) {
                        shakeOffset = 0
                    }
                }
                return
            }
            onPress()
            if !isModifier {
                triggerTapFlash()
            }
        }) {
            Text(label)
                .font(.system(size: isModifier ? 16 : 22, weight: .regular))
                .foregroundColor(isDisabled ? phaseTextColor(phase).opacity(0.2) : phaseTextColor(phase))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(justTapped ? activeBackground : keyBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    (isPressed || justTapped)
                                        ? phaseAccentColor(phase).opacity(0.8)
                                        : phaseAccentColor(phase).opacity(0.2),
                                    lineWidth: (isPressed || justTapped) ? 1.5 : 0.5
                                )
                        )
                        .shadow(
                            color: (isPressed || justTapped)
                                ? phaseAccentColor(phase).opacity(0.7)
                                : .clear,
                            radius: (isPressed || justTapped) ? 16 : 0
                        )
                )
                .scaleEffect(isPressed ? 0.94 : 1.0)
                .offset(x: shakeOffset)
        }
        .buttonStyle(PlainButtonStyle())
        ._onButtonGesture(pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.06)) {
                isPressed = pressing
            }
        }, perform: {})
    }

    private func triggerTapFlash() {
        withAnimation(.easeOut(duration: 0.04)) {
            justTapped = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeOut(duration: 0.15)) {
                justTapped = false
            }
        }
    }
}
