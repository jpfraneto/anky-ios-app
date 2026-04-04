//
//  FlowScoreView.swift
//  Anky
//

import SwiftUI

struct FlowScoreView: View {
    let deltas: [Double]
    let windowSize: Int

    init(deltas: [Double], windowSize: Int = 30) {
        self.deltas = deltas
        self.windowSize = windowSize
    }

    private var recentDeltas: [Double] {
        Array(deltas.suffix(windowSize))
    }

    private var rollingAverages: [Double] {
        let recent = recentDeltas
        guard recent.count >= 2 else { return recent }

        var averages: [Double] = []
        let kernel = min(5, recent.count)
        for i in 0..<recent.count {
            let start = max(0, i - kernel + 1)
            let slice = recent[start...i]
            averages.append(slice.reduce(0, +) / Double(slice.count))
        }
        return averages
    }

    private var sessionMean: Double {
        guard !deltas.isEmpty else { return 300 }
        return deltas.reduce(0, +) / Double(deltas.count)
    }

    private var displayRange: (min: Double, max: Double) {
        let values = rollingAverages
        guard !values.isEmpty else { return (100, 500) }

        let lo = values.min() ?? 100
        let hi = values.max() ?? 500
        let mean = sessionMean
        let allMin = min(lo, mean) * 0.7
        let allMax = max(hi, mean) * 1.3
        let span = max(allMax - allMin, 80)
        return (allMin, allMin + span)
    }

    var body: some View {
        Canvas { context, size in
            let values = rollingAverages
            guard values.count >= 2 else { return }

            let range = displayRange
            let ySpan = range.max - range.min

            func xFor(_ index: Int) -> CGFloat {
                CGFloat(index) / CGFloat(max(values.count - 1, 1)) * size.width
            }

            func yFor(_ value: Double) -> CGFloat {
                let normalized = (value - range.min) / max(ySpan, 1)
                return size.height * (1 - CGFloat(normalized))
            }

            // Session mean reference line (dashed)
            let meanY = yFor(sessionMean)
            if meanY > 0 && meanY < size.height {
                var meanPath = Path()
                meanPath.move(to: CGPoint(x: 0, y: meanY))
                meanPath.addLine(to: CGPoint(x: size.width, y: meanY))
                context.stroke(
                    meanPath,
                    with: .color(Color.ankyGold.opacity(0.2)),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                )
            }

            // Rolling average bezier curve
            var curvePath = Path()
            let points = values.enumerated().map { (i, v) in
                CGPoint(x: xFor(i), y: yFor(v))
            }

            curvePath.move(to: points[0])
            for i in 1..<points.count {
                let prev = points[i - 1]
                let curr = points[i]
                let midX = (prev.x + curr.x) / 2
                curvePath.addCurve(
                    to: curr,
                    control1: CGPoint(x: midX, y: prev.y),
                    control2: CGPoint(x: midX, y: curr.y)
                )
            }

            context.stroke(
                curvePath,
                with: .color(Color.ankyGold.opacity(0.4)),
                lineWidth: 1.5
            )
        }
        .frame(height: 48)
        .animation(.easeInOut(duration: 0.3), value: deltas.count)
    }
}
