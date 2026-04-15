//
//  AnkyKingdom.swift
//  Anky
//

import SwiftUI

/// Kingdom classification for individual writing sessions.
/// Distinct from the user's wallet-derived Kingdom in AnkyTheme.swift —
/// this represents the energy assigned to a specific anky by the backend.
enum AnkyKingdom: String, CaseIterable, Codable {
    case primordia, emblazion, chryseos, eleasis, voxlumis, insightia, claridium, poiesis

    /// Display color — exact hex values from the kingdoms spec.
    /// Do NOT use ankyPurple from AnkyTheme (it's incorrectly green #4a8a4a).
    var color: Color {
        switch self {
        case .primordia:  return Color(hex: "dc2626")
        case .emblazion:  return Color(hex: "ea580c")
        case .chryseos:   return Color(hex: "ca8a04")
        case .eleasis:    return Color(hex: "16a34a")
        case .voxlumis:   return Color(hex: "2563eb")
        case .insightia:  return Color(hex: "4f46e5")
        case .claridium:  return Color(hex: "7c3aed")
        case .poiesis:    return Color(hex: "b45309")
        }
    }

    var displayName: String {
        rawValue
    }

    var lesson: String {
        switch self {
        case .primordia:  return "You are here. You are alive. Start there."
        case .emblazion:  return "What do you want so badly it terrifies you?"
        case .chryseos:   return "You are not waiting for permission."
        case .eleasis:    return "The wall around your heart is made of the same material as the prison."
        case .voxlumis:   return "Say the thing you're afraid to say."
        case .insightia:  return "You already know. You've always known."
        case .claridium:  return "Who is the one asking 'who am I?'"
        case .poiesis:    return "You are not the creator. You are the channel."
        }
    }

    /// Neutral grey for sessions without a classified kingdom
    static let unclassifiedColor = Color(hex: "333333")
}
