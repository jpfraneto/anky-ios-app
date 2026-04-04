import SwiftUI

extension Color {
    // Re-declare hex init for shared target (keyboard extension)
    init(sharedHex hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

func phaseColor(_ phase: SessionPhase) -> Color {
    switch phase {
    case .idle:          return Color(sharedHex: "07070d")
    case .warming:       return Color(sharedHex: "0d1a0d")
    case .flow:          return Color(sharedHex: "0d1a0d")
    case .transcendent:  return Color(sharedHex: "1a0e06")
    case .broken:        return Color(sharedHex: "0a0a0f")
    }
}

func phaseAccentColor(_ phase: SessionPhase) -> Color {
    switch phase {
    case .idle:          return Color.white.opacity(0.08)
    case .warming:       return Color(sharedHex: "4a8a4a")
    case .flow:          return Color(sharedHex: "4a8a4a")
    case .transcendent:  return Color(sharedHex: "c4845a")
    case .broken:        return Color(sharedHex: "8b0000")
    }
}

func phaseTextColor(_ phase: SessionPhase) -> Color {
    switch phase {
    case .transcendent:  return Color(sharedHex: "f5e6c0")
    default:             return Color.white.opacity(0.85)
    }
}

func phaseKeyBackground(_ phase: SessionPhase) -> Color {
    switch phase {
    case .transcendent:  return Color(red: 1, green: 0.71, blue: 0.31).opacity(0.10)
    default:             return Color.white.opacity(0.08)
    }
}

func phaseKeyText(_ phase: SessionPhase) -> Color {
    switch phase {
    case .transcendent:  return Color(red: 1, green: 0.86, blue: 0.63).opacity(0.75)
    default:             return Color.white.opacity(0.8)
    }
}

func phaseSpaceBarLabel(_ phase: SessionPhase) -> String {
    switch phase {
    case .idle:          return "anky"
    case .warming:       return "begin"
    case .flow:          return "flow"
    case .transcendent:  return "∞"
    case .broken:        return "otra vez"
    }
}
