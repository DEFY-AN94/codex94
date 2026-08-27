import SwiftUI

struct MenuBarStatusView: View {
    @ObservedObject var store: AppStore
    var onAccessibilityLabelChange: (String) -> Void = { _ in }
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
        let accessibilityLabel = Self.accessibilityLabel(
            store: store,
            resolvedQuota: resolvedQuota,
            presentation: presentation,
            now: now
        )

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
        .accessibilityHidden(true)
        .onAppear {
            onAccessibilityLabelChange(accessibilityLabel)
        }
        .onChange(of: accessibilityLabel) { _, updatedLabel in
            onAccessibilityLabelChange(updatedLabel)
        }
    }

    static func accessibilityLabel(
        store: AppStore,
        resolvedQuota: ResolvedQuotaWindow?,
        presentation: StatusPresentation,
        now: Date
    ) -> String {
        let bucketName: String
        if let snapshot = store.snapshot, let bucket = resolvedQuota?.bucket {
            bucketName = snapshot.displayName(for: bucket)
        } else {
            bucketName = "Codex"
        }
        return StatusAccessibilityString.quotaSummary(
            bucketName: bucketName,
            window: resolvedQuota?.window,
            presentation: presentation,
            now: now,
            language: store.preferences.language
        )
    }
}
