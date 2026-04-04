import SwiftUI

struct BottomActionBar: View {
    let phase: SessionPhase
    let isExternalApp: Bool
    let hasPendingFormatted: Bool
    @Binding var showSymbols: Bool
    let onKeyPress: (String) -> Void
    let onFormatAndReplace: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            // Symbols / ABC toggle
            KeyButton(
                label: showSymbols ? "ABC" : "123",
                phase: phase,
                isModifier: true,
                onPress: { showSymbols.toggle() }
            )
            .frame(width: 50)

            // Comma
            KeyButton(label: ",", phase: phase, onPress: { onKeyPress(",") })
                .frame(width: 40)

            // Space bar
            Button(action: { onKeyPress(" ") }) {
                Text(spaceLabel)
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(phaseTextColor(phase).opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.12))
                    )
            }
            .buttonStyle(PlainButtonStyle())

            // Period
            KeyButton(label: ".", phase: phase, onPress: { onKeyPress(".") })
                .frame(width: 40)

            // Post button or return key
            if isExternalApp && hasPendingFormatted {
                Button(action: onFormatAndReplace) {
                    Text("✦ post")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.black)
                        .frame(width: 64)
                        .frame(height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(phaseAccentColor(.transcendent))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                KeyButton(
                    label: "↵",
                    phase: phase,
                    isModifier: true,
                    onPress: { onKeyPress("\n") }
                )
                .frame(width: 44)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    var spaceLabel: String {
        switch phase {
        case .idle:          return "anky"
        case .warming:       return "begin"
        case .flow:          return "flow"
        case .transcendent:  return "∞"
        case .broken:        return "again"
        }
    }
}
