import SwiftUI

struct MenuBarStatusView: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Codex94Palette.resolve(store.preferences.theme, scheme: colorScheme)
        let window = store.displayedWindow
        let isStale = store.connectionState.isStale
        let color = palette.quotaColor(
            remainingPercent: window?.remainingPercent,
            stale: isStale
        )

        HStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                RingGaugeView(
                    remainingPercent: window?.remainingPercent,
                    color: color,
                    lineWidth: 2.2
                )
                .frame(width: 16, height: 16)

                if isStale {
                    Circle()
                        .fill(palette.terminalAmber)
                        .frame(width: 4, height: 4)
                        .offset(x: 1, y: -1)
                }
            }

            Text(QuotaFormatting.percent(window?.remainingPercent))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 30, alignment: .leading)
        }
        .frame(width: 52, height: 22)
        .contentShape(Rectangle())
        .allowsHitTesting(false)
        .accessibilityLabel("Codex94 \(QuotaFormatting.percent(window?.remainingPercent))")
    }
}

private extension ConnectionState {
    var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
}
