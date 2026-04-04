//
//  PixelHeartView.swift
//  Anky
//
//  Pixel-art hearts that deplete from top to bottom.
//  Each heart is an 8x7 grid of tiny squares forming the classic shape.
//

import SwiftUI

struct PixelHeartView: View {
    /// 1.0 = full heart, 0.0 = empty heart
    let fill: Double

    /// Size of each pixel block
    var pixelSize: CGFloat = 3

    /// Gap between pixels
    var gap: CGFloat = 0.5

    /// Color when filled
    var filledColor: Color = .white

    /// Color when empty
    var emptyColor: Color = Color.white.opacity(0.08)

    // The heart bitmap — 1 = pixel, 0 = empty space
    // 8 columns × 7 rows
    private static let bitmap: [[Int]] = [
        [0, 1, 1, 0, 0, 1, 1, 0],  // row 0 (top)
        [1, 1, 1, 1, 1, 1, 1, 1],  // row 1
        [1, 1, 1, 1, 1, 1, 1, 1],  // row 2
        [1, 1, 1, 1, 1, 1, 1, 1],  // row 3
        [0, 1, 1, 1, 1, 1, 1, 0],  // row 4
        [0, 0, 1, 1, 1, 1, 0, 0],  // row 5
        [0, 0, 0, 1, 1, 0, 0, 0],  // row 6 (bottom)
    ]

    private static let rows = 7
    private static let cols = 8

    // Total filled pixels in the heart shape
    private static let totalPixels: Int = {
        bitmap.flatMap { $0 }.reduce(0, +)
    }()

    var body: some View {
        Canvas { context, size in
            let step = pixelSize + gap
            let totalW = CGFloat(Self.cols) * step - gap
            let totalH = CGFloat(Self.rows) * step - gap
            let offsetX = (size.width - totalW) / 2
            let offsetY = (size.height - totalH) / 2

            // Depletion goes top → bottom
            // fill=1.0 means all pixels lit, fill=0.0 means none
            // We count pixels from bottom to top for fill order
            // (bottom pixels are the last to go)
            let pixelsToFill = Int(Double(Self.totalPixels) * max(min(fill, 1), 0))

            // Build an ordered list: bottom rows first (they stay filled longest)
            var pixelPositions: [(row: Int, col: Int)] = []
            for row in stride(from: Self.rows - 1, through: 0, by: -1) {
                for col in 0..<Self.cols {
                    if Self.bitmap[row][col] == 1 {
                        pixelPositions.append((row, col))
                    }
                }
            }

            // Set of filled positions
            let filledSet = Set(pixelPositions.prefix(pixelsToFill).map { "\($0.row),\($0.col)" })

            for row in 0..<Self.rows {
                for col in 0..<Self.cols {
                    guard Self.bitmap[row][col] == 1 else { continue }

                    let x = offsetX + CGFloat(col) * step
                    let y = offsetY + CGFloat(row) * step
                    let rect = CGRect(x: x, y: y, width: pixelSize, height: pixelSize)

                    let isFilled = filledSet.contains("\(row),\(col)")

                    if isFilled {
                        // Filled pixel — slight brightness variation by row for depth
                        let rowFraction = Double(row) / Double(Self.rows - 1)
                        let brightness = 0.7 + rowFraction * 0.3  // brighter at bottom
                        context.fill(
                            Path(rect),
                            with: .color(filledColor.opacity(brightness))
                        )
                    } else {
                        // Empty pixel — ghost outline
                        context.fill(
                            Path(rect),
                            with: .color(emptyColor)
                        )
                    }
                }
            }
        }
        .frame(
            width: CGFloat(Self.cols) * (pixelSize + gap) - gap + 2,
            height: CGFloat(Self.rows) * (pixelSize + gap) - gap + 2
        )
    }
}

// MARK: - Lives Display

struct PixelLivesView: View {
    let livesRemaining: Int
    let totalLives: Int
    let currentDrain: Double  // 0.0 = no drain, 1.0 = fully drained
    let phase: WritingSessionPhase

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalLives, id: \.self) { index in
                let fill: Double = {
                    if index >= livesRemaining { return 0 }
                    if index < livesRemaining - 1 { return 1 }
                    // Current (draining) heart
                    return max(1 - currentDrain, 0)
                }()

                PixelHeartView(
                    fill: fill,
                    pixelSize: 3,
                    gap: 0.5,
                    filledColor: heartColor(fill: fill),
                    emptyColor: Color.white.opacity(0.06)
                )
            }
        }
    }

    private func heartColor(fill: Double) -> Color {
        if fill <= 0 { return Color.white.opacity(0.06) }
        if fill < 0.3 { return Color(hex: "ff4400") }
        if fill < 0.6 { return Color(hex: "ffaa00") }
        return phase.accent == Color.white.opacity(0.08) ? .white : phase.accent
    }
}

struct PixelHeartView_Previews: PreviewProvider {
    static var previews: some View {
    ZStack {
        Color(hex: "07070d").ignoresSafeArea()

        VStack(spacing: 24) {
            Text("Full").font(.caption).foregroundStyle(.white.opacity(0.4))
            PixelHeartView(fill: 1.0, pixelSize: 4, gap: 1)

            Text("75%").font(.caption).foregroundStyle(.white.opacity(0.4))
            PixelHeartView(fill: 0.75, pixelSize: 4, gap: 1)

            Text("50%").font(.caption).foregroundStyle(.white.opacity(0.4))
            PixelHeartView(fill: 0.5, pixelSize: 4, gap: 1)

            Text("25%").font(.caption).foregroundStyle(.white.opacity(0.4))
            PixelHeartView(fill: 0.25, pixelSize: 4, gap: 1)

            Text("Empty").font(.caption).foregroundStyle(.white.opacity(0.4))
            PixelHeartView(fill: 0.0, pixelSize: 4, gap: 1)

            Divider()

            Text("Lives: 2/2, no drain").font(.caption).foregroundStyle(.white.opacity(0.4))
            PixelLivesView(livesRemaining: 2, totalLives: 2, currentDrain: 0, phase: .flow)

            Text("Lives: 2/2, 60% drain").font(.caption).foregroundStyle(.white.opacity(0.4))
            PixelLivesView(livesRemaining: 2, totalLives: 2, currentDrain: 0.6, phase: .flow)

            Text("Lives: 1/2, 80% drain").font(.caption).foregroundStyle(.white.opacity(0.4))
            PixelLivesView(livesRemaining: 1, totalLives: 2, currentDrain: 0.8, phase: .flow)
        }
    }
    }
}
