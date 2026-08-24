import SwiftUI

struct MenuBarStatusView: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let palette = Codex94Palette.resolve(store.preferences.theme, scheme: colorScheme)
        let resolvedQuota = store.menuBarQuota
        let window = resolvedQuota?.window
        let presentation = store.menuBarStatusPresentation
        let color = palette.quotaColor(for: presentation.quotaLevel)

        return HStack(spacing: 4) {
            RingGaugeView(
                remainingPercent: window?.remainingPercent,
                color: color,
                lineWidth: 2.2
            )
            .frame(width: 16, height: 16)
            .overlay(alignment: .topTrailing) {
                ConnectionBadgeView(
                    badge: presentation.connectionBadge,
                    color: palette.connectionAccent,
                    size: 7
                )
                .offset(x: 3, y: -3)
                .accessibilityHidden(true)
            }

            Text(QuotaFormatting.percent(window?.remainingPercent))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .frame(width: 30, alignment: .leading)
        }
        .frame(width: 52, height: 22)
        .contentShape(Rectangle())
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(
            resolvedQuota: resolvedQuota,
            presentation: presentation,
            now: now
        ))
    }

    private func accessibilityLabel(
        resolvedQuota: ResolvedQuotaWindow?,
        presentation: StatusPresentation,
        now: Date
    ) -> Text {
        let bucketName: String
        if let snapshot = store.snapshot, let bucket = resolvedQuota?.bucket {
            bucketName = snapshot.displayName(for: bucket)
        } else {
            bucketName = "Codex"
        }

        var label = Text(verbatim: bucketName)
        if let window = resolvedQuota?.window {
            label = label
                + Text(verbatim: ", ")
                + StatusAccessibilityText.quotaWindow(window.kind.localizedKey)
                + Text(verbatim: ", ")
                + StatusAccessibilityText.remainingPercent(
                    QuotaFormatting.percent(window.remainingPercent)
                )
        } else {
            label = label
                + Text(verbatim: ", ")
                + StatusAccessibilityText.unavailableQuota
        }

        label = label
            + Text(verbatim: ", ")
            + StatusAccessibilityText.connectionContext(presentation)

        if presentation.usesCachedData, let lastSuccess = presentation.lastSuccess {
            label = label
                + Text(verbatim: ", ")
                + StatusAccessibilityText.cachedAge(
                    QuotaFormatting.staleAge(since: lastSuccess, now: now)
                )
        }
        return label
    }
}
