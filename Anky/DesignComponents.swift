//
//  DesignComponents.swift
//  Anky
//
//  Reusable design system components per the Anky design specification.
//

import SwiftUI

// MARK: - iOS 16.4+ Presentation Helpers

extension View {
    @ViewBuilder
    func sheetStyle(cornerRadius: CGFloat = 24, material: Bool = false) -> some View {
        if #available(iOS 16.4, *) {
            if material {
                self.presentationCornerRadius(cornerRadius)
                    .presentationBackground(.ultraThinMaterial)
            } else {
                self.presentationCornerRadius(cornerRadius)
                    .presentationBackground(.regularMaterial)
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func sheetStyleBackground(_ color: Color) -> some View {
        if #available(iOS 16.4, *) {
            self.presentationBackground(color)
        } else {
            self
        }
    }
}

// MARK: - Anky Mark (Three Concentric Circles)

struct AnkyMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: size, height: size)

            Circle()
                .stroke(Color.white, lineWidth: 1.2)
                .frame(width: size * 0.6, height: size * 0.6)

            Circle()
                .fill(Color.white)
                .frame(width: size * 0.18, height: size * 0.18)
        }
    }
}

// MARK: - Bottom Navigation Bar

struct BottomNav: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            // Stories
            navItem(tab: .stories, icon: "book.fill", label: "historias")

            // Anky (center mark)
            Button {
                appState.currentTab = .write
            } label: {
                VStack(spacing: 5) {
                    AnkyMark(size: 24)
                        .opacity(appState.currentTab == .write ? 1 : 0.35)

                    Text("anky")
                        .font(.ankyLabel(10, weight: .medium))
                        .foregroundStyle(appState.currentTab == .write ? Color.white : Color.white.opacity(0.35))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.plain)

            // You
            navItem(tab: .you, icon: "person.fill", label: "tú")
        }
        .padding(.top, 8)
        .padding(.bottom, AnkyTheme.navBarBottomPadding)
        .background(
            Color.ankyVoid.opacity(0.95)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        )
        .frame(height: AnkyTheme.navBarHeight)
    }

    private func navItem(tab: AppState.Tab, icon: String, label: String) -> some View {
        Button {
            appState.currentTab = tab
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))

                Text(label)
                    .font(.ankyLabel(10, weight: .medium))
            }
            .foregroundStyle(appState.currentTab == tab ? Color.white : Color.white.opacity(0.35))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Phase Background

struct PhaseBackgroundView: View {
    let phase: WritingSessionPhase

    var body: some View {
        phase.background
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.8), value: phase.background)
    }
}

// MARK: - Idle Drain Bar (top of writing session)

struct IdleDrainBar: View {
    let idleElapsed: TimeInterval
    let idleLimit: TimeInterval
    let idleWarningStart: TimeInterval
    let phase: WritingSessionPhase

    private var drainProgress: Double {
        guard idleElapsed >= idleWarningStart else { return 0 }
        let span = max(idleLimit - idleWarningStart, 0.01)
        return min(max((idleElapsed - idleWarningStart) / span, 0), 1)
    }

    private var barColor: Color {
        if drainProgress > 0.7 { return Color(hex: "ff3333") }
        if drainProgress > 0.3 { return Color(hex: "ff9933") }
        return Color(hex: "EF9F27")
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.04))

                if drainProgress > 0 {
                    Rectangle()
                        .fill(barColor.opacity(0.8))
                        .frame(width: proxy.size.width * (1.0 - drainProgress))
                        .animation(.linear(duration: 0.1), value: drainProgress)
                } else {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                }
            }
        }
        .frame(height: 3)
    }
}

// MARK: - Chakra Progress Bar (8-minute journey, red → white)

struct ChakraProgressBar: View {
    let progress: Double // 0-1 over 8 minutes

    private static let colors: [Color] = [
        Color(hex: "ff0000"), // root — red
        Color(hex: "ff6600"), // sacral — orange
        Color(hex: "ffcc00"), // solar plexus — yellow
        Color(hex: "33cc33"), // heart — green
        Color(hex: "3399ff"), // throat — blue
        Color(hex: "6633cc"), // third eye — indigo
        Color(hex: "9933ff"), // crown — violet
        Color(hex: "ffffff"), // transcendent — white
    ]

    private var currentColor: Color {
        let step = min(Int(progress * 8), 7)
        return Self.colors[step]
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.04))

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: Array(Self.colors.prefix(max(Int(progress * 8) + 1, 1))),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * min(progress, 1))
                    .animation(.easeOut(duration: 0.3), value: progress)
            }
        }
        .frame(height: 3)
    }
}

// MARK: - Writing Bottom Bar (checkpoint glow + countdown/countup timer)

struct WritingBottomBar: View {
    let sessionElapsed: TimeInterval
    let lastCheckpointAge: TimeInterval
    let qualifiesForAnky: Bool
    var onSend: (() -> Void)?

    private let sessionGoal: TimeInterval = AnkyContract.Qualification.minimumDurationSeconds

    /// Countdown from 8:00 to 0:00, then count up from 8:00
    private var timerLabel: String {
        let total = max(Int(sessionElapsed), 0)
        if sessionElapsed < sessionGoal {
            // Counting down: remaining time
            let remaining = Int(sessionGoal) - total
            let m = remaining / 60
            let s = remaining % 60
            return String(format: "%d:%02d", m, s)
        } else {
            // Count up from 8:00
            let m = total / 60
            let s = total % 60
            return String(format: "%d:%02d", m, s)
        }
    }

    /// Show "saved" glow for 2 seconds after each checkpoint
    private var showCheckpointGlow: Bool {
        lastCheckpointAge >= 0 && lastCheckpointAge < 2.0
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: checkpoint indicator
            HStack(spacing: 6) {
                if showCheckpointGlow {
                    Circle()
                        .fill(Color(hex: "4a8a4a"))
                        .frame(width: 5, height: 5)
                        .transition(.opacity)

                    Text(WritingExperienceStrings.current[.writingSafeTitle].components(separatedBy: " ").first ?? "saved")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(Color(hex: "4a8a4a").opacity(0.7))
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.4), value: showCheckpointGlow)

            // Center: send button (when qualified)
            if qualifiesForAnky, let onSend {
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }

            // Right: timer
            Text(timerLabel)
                .font(.system(size: 14, weight: .light, design: .monospaced))
                .foregroundStyle(
                    sessionElapsed >= sessionGoal
                        ? Color(hex: "EF9F27").opacity(0.8)
                        : Color.white.opacity(0.35)
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .frame(height: 40)
        .animation(.easeOut(duration: 0.3), value: qualifiesForAnky)
    }
}

// MARK: - Command Center Bar (legacy, kept for compatibility)

struct CommandCenterBarView: View {
    let phase: WritingSessionPhase
    let streakSeconds: Double
    let totalDuration: TimeInterval
    var livesRemaining: Int = 2
    var totalLives: Int = 2
    var idleDrainProgress: Double = 0
    var qualifiesForAnky: Bool = false
    var onSend: (() -> Void)?

    var body: some View {
        // Delegate to new components
        VStack(spacing: 0) {
            WritingBottomBar(
                sessionElapsed: totalDuration,
                lastCheckpointAge: -1, // No checkpoint tracking in legacy
                qualifiesForAnky: qualifiesForAnky,
                onSend: onSend
            )
        }
    }
}

// MARK: - Ghost Key

struct GhostKeyView: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Color.white.opacity(0.02))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            )
            .frame(width: width, height: height)
    }
}

// MARK: - Key Button

struct KeyButtonView: View {
    let label: String
    let phase: WritingSessionPhase
    let isGhost: Bool
    let width: CGFloat
    let height: CGFloat
    let onTap: () -> Void

    init(
        label: String,
        phase: WritingSessionPhase = .idle,
        isGhost: Bool = false,
        width: CGFloat = 32,
        height: CGFloat = 38,
        onTap: @escaping () -> Void = {}
    ) {
        self.label = label
        self.phase = phase
        self.isGhost = isGhost
        self.width = width
        self.height = height
        self.onTap = onTap
    }

    var body: some View {
        if isGhost {
            GhostKeyView(width: width, height: height)
        } else {
            Button(action: onTap) {
                Text(label)
                    .font(.ankyLabel(13, weight: .regular))
                    .foregroundStyle(phase.keyText)
                    .frame(width: width, height: height)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(phase.keyBackground)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Story Card (Historias list)

struct StoryCardView: View {
    let story: Cuentacuentos
    let downloadState: DownloadState
    let onPlay: () -> Void

    enum DownloadState {
        case notDownloaded
        case downloaded
        case generating
    }

    private var coverImageUrl: URL? {
        story.guidancePhases.first.flatMap { phase in
            phase.imageUrl.flatMap { URL(string: $0) }
        }
    }

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                // Thumbnail
                Group {
                    if downloadState == .generating {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.04))
                            Image(systemName: "clock")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.white.opacity(0.3))
                        }
                    } else if let url = coverImageUrl {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                gradientPlaceholder
                            }
                        }
                    } else {
                        gradientPlaceholder
                    }
                }
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    if downloadState == .generating {
                        Text("generando...")
                            .font(.ankyLabel(12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.3))
                        Text("hace un momento")
                            .font(.ankyBody(10))
                            .foregroundStyle(Color.white.opacity(0.35))
                    } else {
                        Text(story.title)
                            .font(.ankyLabel(12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.88))
                            .lineLimit(2)

                        HStack(spacing: 6) {
                            // Child avatar dot placeholder
                            Circle()
                                .fill(Color(hex: "4a8a4a"))
                                .frame(width: 8, height: 8)

                            Text("8 min")
                                .font(.ankyBody(10))
                                .foregroundStyle(Color.white.opacity(0.35))
                        }
                    }
                }

                Spacer()

                // Download indicator
                if downloadState == .downloaded {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "4a8a4a").opacity(0.6))
                } else if downloadState == .notDownloaded {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.25))
                }
            }
        }
        .buttonStyle(.plain)
        .frame(height: 76)
    }

    private var gradientPlaceholder: some View {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.75, blue: 0.35),
                Color(red: 0.92, green: 0.55, blue: 0.22)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Child Pill (filter chip)

struct ChildPill: View {
    let child: ChildProfile
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Gradient avatar dot
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.orange, .pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 14, height: 14)

            Text(child.name)
                .font(.ankyBody(12))
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.08),
                            lineWidth: 0.5
                        )
                )
        )
    }
}

// MARK: - Rhythm Visualization (Session Summary)

struct RhythmVisualization: View {
    let keystrokeDeltas: [Double]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            let bars = normalizedBars
            ForEach(Array(bars.enumerated()), id: \.offset) { index, height in
                let progress = Double(index) / max(Double(bars.count - 1), 1)
                let opacity = 0.12 + progress * 0.33

                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(opacity))
                    .frame(width: nil, height: max(height * 32, 2))
            }
        }
        .frame(height: 32)
    }

    private var normalizedBars: [Double] {
        guard !keystrokeDeltas.isEmpty else { return [] }
        let targetCount = 40
        let stride = max(keystrokeDeltas.count / targetCount, 1)
        var bars: [Double] = []
        var i = 0
        while i < keystrokeDeltas.count && bars.count < targetCount {
            let end = min(i + stride, keystrokeDeltas.count)
            let slice = keystrokeDeltas[i..<end]
            let avg = slice.reduce(0, +) / Double(slice.count)
            bars.append(avg)
            i = end
        }
        guard let maxVal = bars.max(), maxVal > 0 else { return bars.map { _ in 0.5 } }
        return bars.map { min($0 / maxVal, 1) }
    }
}

// MARK: - Insight Block (Tú tab)

struct InsightBlock: View {
    let category: String
    let insight: String
    let customOpacity: Double?

    init(category: String, insight: String, customOpacity: Double? = nil) {
        self.category = category
        self.insight = insight
        self.customOpacity = customOpacity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category.uppercased())
                .font(.ankyLabel(9, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.35))
                .kerning(1)

            Text(insight)
                .font(.ankyBody(13))
                .foregroundStyle(Color.white.opacity(customOpacity ?? 0.8))
                .lineSpacing(4)
        }
        .padding(.leading, 14)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 1.5)
        }
    }
}

// MARK: - Kingdom Item Card

struct KingdomItemCard: View {
    let item: KingdomItem

    private var itemKingdom: Kingdom {
        Kingdom.from(name: item.kingdom) ?? .primordia
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.name)
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundStyle(Color.white.opacity(0.8))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(item.material)
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(Color.white.opacity(0.3))
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(item.chakra)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(itemKingdom.color.opacity(0.5))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 90)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(itemKingdom.color.opacity(0.12), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Kingdom Item Detail Sheet

struct KingdomItemDetailSheet: View {
    let item: KingdomItem

    private var itemKingdom: Kingdom {
        Kingdom.from(name: item.kingdom) ?? .primordia
    }

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.15))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 24)

            // Kingdom color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(itemKingdom.color)
                .frame(height: 3)
                .padding(.horizontal, 40)

            Spacer().frame(height: 24)

            // Item name
            Text(item.name)
                .font(.system(size: 22, weight: .light, design: .serif))
                .foregroundStyle(Color.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer().frame(height: 12)

            // Material
            Text(item.material)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(Color.white.opacity(0.4))

            Spacer().frame(height: 24)

            // Description
            Text(item.description)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .foregroundStyle(Color.white.opacity(0.7))
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer().frame(height: 32)

            // Kingdom info
            HStack(spacing: 12) {
                Circle()
                    .fill(itemKingdom.color.opacity(0.3))
                    .frame(width: 8, height: 8)

                Text("\(item.kingdom) · \(item.chakra)")
                    .font(.system(size: 12, weight: .light, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.35))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(hex: "07070d").ignoresSafeArea())
    }
}

// MARK: - Share Sheet

struct AnkyShareSheet: View {
    let story: Cuentacuentos
    @Environment(\.dismiss) private var dismiss

    private var storySlug: String {
        story.title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0 == "-" || $0.isNumber }
    }

    private var deepLink: String {
        "anky.app/story/\(storySlug)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.15))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 16)

            // Story preview
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [.orange, .yellow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(story.title)
                        .font(.ankyLabel(13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .lineLimit(1)

                    Text("anky")
                        .font(.ankyBody(11))
                        .foregroundStyle(Color.white.opacity(0.35))
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)

            // Deep link
            HStack {
                Text(deepLink)
                    .font(.ankyMono(12))
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer()
            }
            .padding(16)
            .padding(.horizontal, 4)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)

            // Share targets
            HStack(spacing: 20) {
                shareTarget(icon: "message.fill", label: "mensaje")
                shareTarget(icon: "ellipsis.circle.fill", label: "más")
                shareTarget(icon: "doc.on.doc.fill", label: "copiar") {
                    UIPasteboard.general.string = deepLink
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(Color.ankyVoid.ignoresSafeArea())
    }

    private func shareTarget(icon: String, label: String, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                    )

                Text(label)
                    .font(.ankyBody(10))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
    }
}
