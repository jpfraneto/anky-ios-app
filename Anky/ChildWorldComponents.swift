import SwiftUI

enum ChildEmojiPalette {
    static let all = [
        "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍒", "🍑", "🥭", "🍍", "🥥", "🥝",
        "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🦁", "🐯", "🐮", "🐷", "🐸", "🐵", "🐙", "🦋", "🐞", "🐢", "🐬", "🐳", "🦄",
        "🌸", "🌼", "🌻", "🌷", "🌺", "🍀", "🌿", "🌵", "🌈", "☀️", "⭐️", "🌙", "☁️", "⛅️", "🌧️", "⛈️", "❄️", "⚡️", "🌊"
    ]
}

struct EmojiSelectionGrid: View {
    let emojis: [String]
    let onSelect: (String) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 56, maximum: 70), spacing: 14)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(emojis, id: \.self) { emoji in
                    Button {
                        onSelect(emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 30))
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white.opacity(0.14))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
        }
    }
}

struct PatternSlotsView: View {
    let pattern: [String]
    let revealsEmoji: Bool
    let totalSlots: Int

    init(pattern: [String], revealsEmoji: Bool = false, totalSlots: Int = 12) {
        self.pattern = pattern
        self.revealsEmoji = revealsEmoji
        self.totalSlots = totalSlots
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSlots, id: \.self) { index in
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(pattern.indices.contains(index) ? 0.18 : 0.07))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )

                    if pattern.indices.contains(index) {
                        if revealsEmoji {
                            Text(pattern[index])
                                .font(.system(size: 20))
                        } else {
                            Circle()
                                .fill(Color.ankyGold)
                                .frame(width: 12, height: 12)
                        }
                    }
                }
                .frame(width: 24, height: 24)
            }
        }
    }
}

struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 10
    var shakesPerUnit = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(
                translationX: amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)),
                y: 0
            )
        )
    }
}
