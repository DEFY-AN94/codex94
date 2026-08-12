import SwiftUI

struct QuotaBarView: View {
    let remainingPercent: Int
    let color: Color

    private let segmentCount = 20

    var body: some View {
        let filledCount = min(segmentCount, max(0, Int(round(Double(remainingPercent) / 5.0))))
        let emptyCount = segmentCount - filledCount

        (Text(String(repeating: "█", count: filledCount)).foregroundStyle(color)
         + Text(String(repeating: "░", count: emptyCount)).foregroundStyle(.secondary.opacity(0.46)))
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .frame(width: 170, alignment: .leading)
            .accessibilityLabel("\(remainingPercent) percent remaining")
    }
}

struct RingGaugeView: View {
    let remainingPercent: Int?
    let color: Color
    var lineWidth: CGFloat = 2.4

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.28), lineWidth: lineWidth)
            if let remainingPercent {
                Circle()
                    .trim(from: 0, to: CGFloat(min(100, max(0, remainingPercent))) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .accessibilityHidden(true)
    }
}

