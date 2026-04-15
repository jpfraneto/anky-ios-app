//
//  AnkyTheme.swift
//  Anky
//

import SwiftUI

// MARK: - Theme Constants

enum AnkyTheme {
    static let transition = Animation.easeInOut(duration: 0.5)
    static let shortTransition = Animation.easeInOut(duration: 0.4)

    // The base dark — near-black with blue-black tint, never pure black
    static let void = Color(hex: "07070d")

    // Nav bar
    static let navBarHeight: CGFloat = 72
    static let navBarBottomPadding: CGFloat = 12
}

// MARK: - Kingdom (Chakra)

enum Kingdom: Int, CaseIterable, Codable {
    case primordia = 0    // Root
    case emblazion = 1    // Sacral
    case chryseos = 2     // Solar Plexus
    case eleutheria = 3   // Heart
    case voxlumis = 4     // Throat
    case insightia = 5    // Third Eye
    case claridium = 6    // Crown
    case poiesis = 7      // Transcendent

    var name: String {
        switch self {
        case .primordia:  return "Primordia"
        case .emblazion:  return "Emblazion"
        case .chryseos:   return "Chryseos"
        case .eleutheria: return "Eleutheria"
        case .voxlumis:   return "Voxlumis"
        case .insightia:  return "Insightia"
        case .claridium:  return "Claridium"
        case .poiesis:    return "Poiesis"
        }
    }

    var chakra: String {
        switch self {
        case .primordia:  return "Root"
        case .emblazion:  return "Sacral"
        case .chryseos:   return "Solar Plexus"
        case .eleutheria: return "Heart"
        case .voxlumis:   return "Throat"
        case .insightia:  return "Third Eye"
        case .claridium:  return "Crown"
        case .poiesis:    return "Transcendent"
        }
    }

    /// Match kingdom from backend name string
    static func from(name: String) -> Kingdom? {
        allCases.first { $0.name.lowercased() == name.lowercased() }
    }

    /// Primary accent color — used for seal track, card borders, subtle glows
    var color: Color {
        switch self {
        case .primordia: return Color(hex: "8b2500") // deep red-earth
        case .emblazion: return Color(hex: "c45a2e") // burnt orange
        case .chryseos:  return Color(hex: "c4a63a") // dark gold
        case .eleutheria: return Color(hex: "2e6e4e") // deep forest green
        case .voxlumis:  return Color(hex: "2e5e8b") // deep sky blue
        case .insightia: return Color(hex: "4e3a8b") // indigo
        case .claridium: return Color(hex: "6e3a7a") // deep violet
        case .poiesis:   return Color(hex: "c4845a") // warm amber
        }
    }

    /// Gradient colors for reflection card backgrounds
    var gradientColors: [Color] {
        switch self {
        case .primordia: return [Color(hex: "8b2500"), Color(hex: "3a1200")]
        case .emblazion: return [Color(hex: "c45a2e"), Color(hex: "5a2010")]
        case .chryseos:  return [Color(hex: "c4a63a"), Color(hex: "5a4a10")]
        case .eleutheria:   return [Color(hex: "2e6e4e"), Color(hex: "0e3020")]
        case .voxlumis:  return [Color(hex: "2e5e8b"), Color(hex: "102840")]
        case .insightia: return [Color(hex: "4e3a8b"), Color(hex: "1a1040")]
        case .claridium: return [Color(hex: "6e3a7a"), Color(hex: "2a1030")]
        case .poiesis:   return [Color(hex: "c4845a"), Color(hex: "5a3a20")]
        }
    }

    /// Derive kingdom deterministically from a wallet address (Solana base58 or hex).
    static func from(walletAddress: String) -> Kingdom {
        // Decode base58 Solana address to bytes, take first 8 bytes mod 8
        if let decoded = Base58.decode(walletAddress), decoded.count >= 8 {
            var value: UInt64 = 0
            for i in 0..<8 {
                value = (value << 8) | UInt64(decoded[i])
            }
            let index = Int(value % 8)
            return Kingdom(rawValue: index) ?? .primordia
        }
        // Fallback for hex addresses (legacy)
        let hex = walletAddress.hasPrefix("0x") || walletAddress.hasPrefix("0X")
            ? String(walletAddress.dropFirst(2))
            : walletAddress
        let prefix = String(hex.prefix(16))
        let value = UInt64(prefix, radix: 16) ?? 0
        let index = Int(value % 8)
        return Kingdom(rawValue: index) ?? .primordia
    }

    /// Fixed Ankyverse epoch for sojourn 9: April 6, 2026 12:00 UTC
    static let ankyverseEpoch: TimeInterval = 1775476800

    /// Sojourn number at epoch
    static let ankyverseEpochSojourn = 9

    /// Total cycle per sojourn: 96 days = 12 waves × 8 days
    static let ankyverseTotalDays = 96
    static let ankyverseWaveCount = 12
    static let ankyverseDaysPerWave = 8

    /// Days elapsed since epoch (can exceed 96 for multi-sojourn). Returns nil if before epoch.
    static func ankyverseDaysSinceEpoch(for date: Date = .now) -> Int? {
        let elapsed = date.timeIntervalSince1970 - ankyverseEpoch
        guard elapsed >= 0 else { return nil }
        return Int(elapsed / 86400)
    }

    /// Current sojourn number (9 = first sojourn at epoch)
    static func ankyverseSojourn(for date: Date = .now) -> Int? {
        guard let totalDays = ankyverseDaysSinceEpoch(for: date) else { return nil }
        return ankyverseEpochSojourn + (totalDays / ankyverseTotalDays)
    }

    /// Day within current sojourn (0-95)
    static func ankyverseDayNumber(for date: Date = .now) -> Int? {
        guard let totalDays = ankyverseDaysSinceEpoch(for: date) else { return nil }
        return totalDays % ankyverseTotalDays
    }

    /// Current wave number within sojourn (0-based, 0-11)
    static func ankyverseWave(for date: Date = .now) -> Int? {
        guard let day = ankyverseDayNumber(for: date) else { return nil }
        return day / ankyverseDaysPerWave
    }

    /// Kingdom for a given ankyverse day
    static func kingdom(forAnkyverseDay day: Int) -> Kingdom {
        let index = day % allCases.count
        return allCases[index]
    }

    /// Derive the kingdom of the day from the fixed Ankyverse calendar.
    static func ankyverseDay(for date: Date = .now, calendar: Calendar = .current) -> Kingdom {
        if let day = ankyverseDayNumber(for: date) {
            return kingdom(forAnkyverseDay: day)
        }
        // Fallback before epoch: use day-of-year
        let dayOfYear = max((calendar.ordinality(of: .day, in: .year, for: date) ?? 1) - 1, 0)
        let index = dayOfYear % allCases.count
        return allCases[index]
    }

    /// Formatted ankyverse time string: "sojourn 9 · day 1 · primordia"
    static func ankyverseTimeLabel(for date: Date = .now) -> String {
        let sojourn = ankyverseSojourn(for: date) ?? ankyverseEpochSojourn
        let day = (ankyverseDayNumber(for: date) ?? 0) + 1 // 1-based for display
        let kingdom = ankyverseDay(for: date)
        return "sojourn \(sojourn) · day \(day) · \(kingdom.name.lowercased())"
    }
}

// MARK: - Mirror State

enum MirrorState: Int, Codable {
    case virgin = 0              // Never opened — show mirror
    case seedRevealed = 1        // Seed shown, not confirmed
    case seedConfirmed = 2       // Seed stored, first session not started
    case firstSessionInProgress = 3 // Writing through the mirror
    case mirrorDissolved = 4     // First session complete, reveal
    case firstMintComplete = 5   // First NFT minted or queued
    case returningUser = 6       // Regular app experience
}

// MARK: - Session Phase

enum WritingSessionPhase {
    case idle
    case warming
    case flow
    case transcendent
    case broken

    var background: Color {
        switch self {
        case .idle:          return Color(hex: "07070d")
        case .warming:       return Color(hex: "0d1a0d")
        case .flow:          return Color(hex: "0d1a0d")
        case .transcendent:  return Color(hex: "1a0e06")
        case .broken:        return Color(hex: "0a0a0f")
        }
    }

    var accent: Color {
        switch self {
        case .idle:          return Color.white.opacity(0.08)
        case .warming:       return Color(hex: "4a8a4a")
        case .flow:          return Color(hex: "4a8a4a")
        case .transcendent:  return Color(hex: "c4845a")
        case .broken:        return Color(hex: "8b0000")
        }
    }

    var spaceBarLabel: String {
        switch self {
        case .idle:          return "anky"
        case .warming:       return "begin"
        case .flow:          return "flow"
        case .transcendent:  return "∞"
        case .broken:        return "otra vez"
        }
    }

    var keyBackground: Color {
        switch self {
        case .transcendent:  return Color(red: 1, green: 0.71, blue: 0.31).opacity(0.10)
        default:             return Color.white.opacity(0.08)
        }
    }

    var keyText: Color {
        switch self {
        case .transcendent:  return Color(red: 1, green: 0.86, blue: 0.63).opacity(0.75)
        default:             return Color.white.opacity(0.8)
        }
    }
}

// MARK: - Fonts

extension Font {
    static func anky(_ size: CGFloat) -> Font {
        .custom("Righteous-Regular", size: size)
    }

    static func ankyBody(_ size: CGFloat) -> Font {
        .custom("Righteous-Regular", size: size)
    }

    static func ankyLabel(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Righteous-Regular", size: size)
    }

    static func ankyMono(_ size: CGFloat) -> Font {
        .custom("Righteous-Regular", size: size)
    }

    static func ankyDisplay(_ size: CGFloat) -> Font {
        .custom("Righteous-Regular", size: size)
    }
}

extension Kingdom {
    var sealingDisplayName: String {
        switch self {
        case .eleutheria:
            return "Eleasis"
        default:
            return name
        }
    }

    var sealingSlug: String {
        sealingDisplayName.lowercased()
    }

    var sealingColorHex: String {
        switch self {
        case .primordia: return "dc2626"
        case .emblazion: return "ea580c"
        case .chryseos: return "ca8a04"
        case .eleutheria: return "16a34a"
        case .voxlumis: return "2563eb"
        case .insightia: return "4f46e5"
        case .claridium: return "7c3aed"
        case .poiesis: return "b45309"
        }
    }

    var sealingColor: Color {
        Color(hex: sealingColorHex)
    }

    var sealingElement: String {
        switch self {
        case .primordia: return "Earth"
        case .emblazion: return "Water"
        case .chryseos: return "Fire"
        case .eleutheria: return "Air"
        case .voxlumis: return "Ether"
        case .insightia: return "Light"
        case .claridium: return "Consciousness"
        case .poiesis: return "Void"
        }
    }
}

// MARK: - Colors

extension Color {
    // Primary
    static let ankyVoid = Color(hex: "07070d")
    static let ankyBg = Color(hex: "08080e")
    static let ankyCardBg = Color(hex: "14141f")
    static let ankyBorder = Color(hex: "1c1c2a")
    static let ankyTextPrimary = Color(hex: "eeeeee")
    static let ankyTextSecondary = Color(hex: "666666")
    static let ankyTextMuted = Color(hex: "3a3a3a")
    static let ankyTextDim = Color(hex: "2a2a2a")
    static let ankyDivider = Color.white.opacity(0.024)

    // Legacy aliases (keep for compatibility with non-redesigned code)
    static let ankyBlack = Color(hex: "07070d")
    static let ankyCanvas = Color(hex: "07070d")
    static let ankyPanel = Color(hex: "07070d")
    static let ankyPanelRaised = Color.white.opacity(0.04)
    static let ankyInk = Color.white
    static let ankyMuted = Color.white.opacity(0.35)
    static let ankyGold = Color(hex: "c4845a")
    static let ankyAmber = Color(hex: "c4845a")
    static let ankyPurple = Color(hex: "4a8a4a")
    static let ankyPurpleSoft = Color(hex: "4a8a4a")

    // Auth
    static let ankyAuthSurface = Color(hex: "07070d")
    static let ankyAuthSurfaceRaised = Color.white.opacity(0.04)
    static let ankyAuthText = Color.white.opacity(0.80)
    static let ankyAuthMuted = Color.white.opacity(0.35)
    static let ankyAuthAccent = Color.white.opacity(0.85)
    static let ankyAuthAccentSoft = Color.white.opacity(0.55)
    static let ankyAuthError = Color(hex: "8b0000")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension LinearGradient {
    static let ankyBackground = LinearGradient(
        colors: [.ankyVoid, .ankyVoid],
        startPoint: .top,
        endPoint: .bottom
    )

    static let ankyWarmGlow = LinearGradient(
        colors: [Color(hex: "c4845a"), Color(hex: "4a8a4a")],
        startPoint: .leading,
        endPoint: .trailing
    )
}
