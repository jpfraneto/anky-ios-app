//
//  AnkyTheme.swift
//  Anky
//

import SwiftUI

enum AnkyTheme {
    static let transition = Animation.easeInOut(duration: 0.5)
    static let shortTransition = Animation.easeInOut(duration: 0.4)
}

extension Color {
    static let ankyBlack = Color(red: 0.02, green: 0.02, blue: 0.03)
    static let ankyCanvas = Color(red: 0.05, green: 0.04, blue: 0.03)
    static let ankyPanel = Color(red: 0.11, green: 0.08, blue: 0.05)
    static let ankyPanelRaised = Color(red: 0.16, green: 0.11, blue: 0.07)
    static let ankyInk = Color(red: 0.93, green: 0.88, blue: 0.77)
    static let ankyMuted = Color(red: 0.56, green: 0.53, blue: 0.49)
    static let ankyGold = Color(red: 0.86, green: 0.67, blue: 0.31)
    static let ankyAmber = Color(red: 0.77, green: 0.42, blue: 0.19)
    static let ankyPurple = Color(red: 0.54, green: 0.38, blue: 0.90)
    static let ankyPurpleSoft = Color(red: 0.74, green: 0.62, blue: 0.96)
    static let ankyAuthSurface = Color(red: 0.09, green: 0.09, blue: 0.12)
    static let ankyAuthSurfaceRaised = Color(red: 0.14, green: 0.13, blue: 0.19)
    static let ankyAuthText = Color(red: 0.80, green: 0.80, blue: 0.84)
    static let ankyAuthMuted = Color(red: 0.53, green: 0.53, blue: 0.60)
    static let ankyAuthAccent = Color(red: 0.46, green: 0.39, blue: 0.78)
    static let ankyAuthAccentSoft = Color(red: 0.65, green: 0.60, blue: 0.87)
    static let ankyAuthError = Color(red: 0.93, green: 0.55, blue: 0.76)
}

extension LinearGradient {
    static let ankyBackground = LinearGradient(
        colors: [.ankyBlack, .ankyCanvas, .ankyBlack],
        startPoint: .top,
        endPoint: .bottom
    )

    static let ankyWarmGlow = LinearGradient(
        colors: [.ankyAmber, .ankyGold, .ankyPurpleSoft],
        startPoint: .leading,
        endPoint: .trailing
    )
}
