import SwiftUI

struct CommandCenterBar: View {
    let phase: SessionPhase
    let streakSeconds: Double
    let totalDuration: Double
    let keystrokeCount: Int

    @State private var breathScale: CGFloat = 1.0

    var streakProgress: Double {
        max(0, 1.0 - (streakSeconds / 8.0))
    }

    var formattedDuration: String {
        let mins = Int(totalDuration) / 60
        let secs = Int(totalDuration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(phaseAccentColor(phase))
                .frame(width: 8, height: 8)
                .scaleEffect(breathScale)
                .onAppear {
                    withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                        breathScale = 1.6
                    }
                }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 3)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(streakBarColor)
                        .frame(width: geo.size.width * streakProgress, height: 3)
                        .animation(.linear(duration: 0.1), value: streakProgress)
                }
            }
            .frame(height: 3)

            Text(phase == .idle ? "anky" : formattedDuration)
                .font(.system(size: 11, weight: .light, design: .monospaced))
                .foregroundColor(phaseTextColor(phase).opacity(0.6))
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.3))
    }

    var streakBarColor: Color {
        if streakSeconds > 6 { return Color(sharedHex: "ff4400") }
        if streakSeconds > 4 { return Color(sharedHex: "ffaa00") }
        return phaseAccentColor(phase)
    }
}
