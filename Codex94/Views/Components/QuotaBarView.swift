import SwiftUI

/// Shared meter geometry for current quotas and explicitly labelled history.
/// Callers retain ownership of source/time semantics and accessibility text.
struct QuotaMeterRow<Trailing: View>: View {
    let title: Text
    let remainingPercent: Int
    let percentageText: String
    let color: Color
    let trailing: Trailing
    var titleLineLimit: Int? = nil

    var body: some View {
        HStack(spacing: 12) {
            title.foregroundStyle(color)
                .lineLimit(titleLineLimit).truncationMode(.tail)
                .frame(width: 58, alignment: .leading)
            QuotaBarView(remainingPercent: remainingPercent, color: color)
            Text(verbatim: percentageText)
                .monospacedDigit().foregroundStyle(color)
                .frame(width: 54, alignment: .trailing)
            trailing.frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 14, weight: .medium, design: .monospaced))
    }
}

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
            .minimumScaleFactor(0.75)
            .frame(width: 170, alignment: .leading)
            .accessibilityLabel(
                StatusAccessibilityText.remainingPercent(
                    QuotaFormatting.percent(remainingPercent)
                )
            )
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
