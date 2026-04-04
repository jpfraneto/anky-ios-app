//
//  MandalaGenerator.swift
//  Anky
//
//  Generates a mandala pattern from writing data using pure math.
//  No AI — just keystroke rhythm + character frequencies → geometry.
//

import SwiftUI

struct MandalaGenerator {

    /// Generate a mandala image from writing session data
    static func generate(
        text: String,
        keystrokeDeltas: [Double],
        size: CGFloat = 400,
        kingdom: Kingdom = .primordia
    ) -> some View {
        MandalaCanvas(
            params: computeParams(text: text, keystrokeDeltas: keystrokeDeltas, kingdom: kingdom),
            size: size
        )
    }

    /// Parameters derived from the writing
    struct Params {
        let petalCount: Int        // number of radial petals (6-24)
        let layerCount: Int        // concentric rings (3-8)
        let symmetry: Int          // rotational symmetry order
        let curvature: Double      // how curved the petals are (0-1)
        let density: Double        // how filled the pattern is (0-1)
        let rhythmWave: [Double]   // normalized rhythm pattern (0-1 values)
        let charFreqs: [Double]    // 26 letter frequencies normalized
        let primaryColor: Color
        let secondaryColor: Color
        let accentColor: Color
    }

    static func computeParams(text: String, keystrokeDeltas: [Double], kingdom: Kingdom) -> Params {
        // Character frequency analysis
        let lower = text.lowercased()
        var counts = [Double](repeating: 0, count: 26)
        for char in lower {
            if let ascii = char.asciiValue, ascii >= 97, ascii <= 122 {
                counts[Int(ascii - 97)] += 1
            }
        }
        let maxCount = counts.max() ?? 1
        let charFreqs = counts.map { $0 / max(maxCount, 1) }

        // Rhythm analysis from keystroke deltas
        let rhythm: [Double]
        if keystrokeDeltas.isEmpty {
            rhythm = [0.5]
        } else {
            let maxDelta = keystrokeDeltas.max() ?? 1
            rhythm = keystrokeDeltas.suffix(64).map { min($0 / max(maxDelta, 1), 1) }
        }

        // Derive structural parameters from the writing
        let totalChars = Double(text.count)
        let avgDelta = keystrokeDeltas.isEmpty ? 300.0 : keystrokeDeltas.reduce(0, +) / Double(keystrokeDeltas.count)

        // Hash the text for deterministic but varied values
        let textHash = abs(text.hashValue)

        let petalCount = 6 + (textHash % 19)  // 6-24
        let layerCount = 3 + Int(min(totalChars / 200, 5))  // 3-8
        let symmetry = [3, 4, 5, 6, 8, 10, 12][textHash % 7]
        let curvature = min(max(avgDelta / 500, 0.1), 1.0)
        let density = min(totalChars / 2000, 1.0)

        let colors = kingdom.gradientColors
        let primaryColor = colors.first ?? kingdom.color
        let secondaryColor = colors.last ?? kingdom.color.opacity(0.5)

        return Params(
            petalCount: petalCount,
            layerCount: layerCount,
            symmetry: symmetry,
            curvature: curvature,
            density: density,
            rhythmWave: rhythm,
            charFreqs: charFreqs,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
            accentColor: kingdom.color
        )
    }
}

// MARK: - Mandala Canvas

struct MandalaCanvas: View {
    let params: MandalaGenerator.Params
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let maxRadius = min(canvasSize.width, canvasSize.height) / 2 * 0.85

            // Draw concentric layers
            for layer in 0..<params.layerCount {
                let layerProgress = Double(layer + 1) / Double(params.layerCount)
                let radius = maxRadius * layerProgress
                let opacity = 0.15 + (1 - layerProgress) * 0.25

                drawLayer(
                    context: &context,
                    center: center,
                    radius: radius,
                    layer: layer,
                    opacity: opacity
                )
            }

            // Draw radial petals
            for i in 0..<params.petalCount {
                let angle = (Double(i) / Double(params.petalCount)) * 2 * .pi
                let rhythmIndex = i % max(params.rhythmWave.count, 1)
                let rhythmValue = params.rhythmWave.isEmpty ? 0.5 : params.rhythmWave[rhythmIndex]
                let petalLength = maxRadius * (0.3 + rhythmValue * 0.7)
                let opacity = 0.1 + rhythmValue * 0.3

                drawPetal(
                    context: &context,
                    center: center,
                    angle: angle,
                    length: petalLength,
                    width: 2 + params.curvature * 4,
                    opacity: opacity
                )
            }

            // Draw character frequency ring
            drawFrequencyRing(
                context: &context,
                center: center,
                radius: maxRadius * 0.5,
                frequencies: params.charFreqs
            )

            // Central dot
            let dotPath = Path(ellipseIn: CGRect(
                x: center.x - 4, y: center.y - 4,
                width: 8, height: 8
            ))
            context.fill(dotPath, with: .color(params.accentColor.opacity(0.6)))
        }
        .frame(width: size, height: size)
    }

    private func drawLayer(
        context: inout GraphicsContext,
        center: CGPoint,
        radius: Double,
        layer: Int,
        opacity: Double
    ) {
        // Each layer is a polygon with symmetry-sided shape, slightly deformed by rhythm
        var path = Path()
        let sides = params.symmetry
        for i in 0...sides {
            let angle = (Double(i) / Double(sides)) * 2 * .pi
            let rhythmIndex = (layer * sides + i) % max(params.rhythmWave.count, 1)
            let rhythmValue = params.rhythmWave.isEmpty ? 0.5 : params.rhythmWave[rhythmIndex]
            let r = radius * (0.9 + rhythmValue * 0.1)

            let point = CGPoint(
                x: center.x + cos(angle) * r,
                y: center.y + sin(angle) * r
            )

            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()

        let color = layer % 2 == 0 ? params.primaryColor : params.secondaryColor
        context.stroke(path, with: .color(color.opacity(opacity)), lineWidth: 0.8)
    }

    private func drawPetal(
        context: inout GraphicsContext,
        center: CGPoint,
        angle: Double,
        length: Double,
        width: Double,
        opacity: Double
    ) {
        let endPoint = CGPoint(
            x: center.x + cos(angle) * length,
            y: center.y + sin(angle) * length
        )

        // Bezier petal with curvature
        let controlOffset = length * params.curvature * 0.4
        let perpAngle = angle + .pi / 2

        let cp1 = CGPoint(
            x: center.x + cos(angle) * length * 0.5 + cos(perpAngle) * controlOffset,
            y: center.y + sin(angle) * length * 0.5 + sin(perpAngle) * controlOffset
        )

        var path = Path()
        path.move(to: center)
        path.addQuadCurve(to: endPoint, control: cp1)

        context.stroke(path, with: .color(params.accentColor.opacity(opacity)), lineWidth: width)
    }

    private func drawFrequencyRing(
        context: inout GraphicsContext,
        center: CGPoint,
        radius: Double,
        frequencies: [Double]
    ) {
        guard frequencies.count == 26 else { return }

        for i in 0..<26 {
            let angle = (Double(i) / 26.0) * 2 * .pi
            let freq = frequencies[i]
            guard freq > 0.05 else { continue }

            let barLength = radius * 0.15 * freq
            let innerR = radius - barLength / 2
            let outerR = radius + barLength / 2

            let innerPoint = CGPoint(
                x: center.x + cos(angle) * innerR,
                y: center.y + sin(angle) * innerR
            )
            let outerPoint = CGPoint(
                x: center.x + cos(angle) * outerR,
                y: center.y + sin(angle) * outerR
            )

            var path = Path()
            path.move(to: innerPoint)
            path.addLine(to: outerPoint)

            context.stroke(
                path,
                with: .color(params.accentColor.opacity(0.15 + freq * 0.25)),
                lineWidth: 2
            )
        }
    }
}
