import SwiftUI

struct MenuBarStatusView: View {
    @ObservedObject var store: AppStore
    let layout: MenuBarLayout
    var onAccessibilityLabelChange: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme

    init(
        store: AppStore,
        layout: MenuBarLayout = .ringAndPercentage,
        onAccessibilityLabelChange: @escaping (String) -> Void = { _ in }
    ) {
        self.store = store
        self.layout = layout
        self.onAccessibilityLabelChange = onAccessibilityLabelChange
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let palette = Codex94Palette.resolve(
            store.preferences.theme,
            scheme: colorScheme,
            overrides: store.preferences.statusAccentOverrides
        )
        let resolvedQuota = store.menuBarQuota
        let window = resolvedQuota?.window
        let presentation = store.menuBarStatusPresentation
        let accessibilityLabel = Self.accessibilityLabel(
            store: store,
            resolvedQuota: resolvedQuota,
            presentation: presentation,
            now: now
        )

        return MenuBarStatusContent(
            layout: layout,
            remainingPercent: window?.remainingPercent,
            quotaLevel: presentation.quotaLevel,
            badge: presentation.connectionBadge,
            palette: palette
        )
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

/// Shared presentation-only input also permits a synthetic `100%+` stress case.
/// It does not create quota data or alter the model's percentage clamp.
struct MenuBarStatusContent: View {
    let layout: MenuBarLayout
    let remainingPercent: Int?
    let quotaLevel: QuotaLevel
    let badge: ConnectionBadge
    let palette: Codex94Palette

    var body: some View {
        let metrics = layout.metrics
        let color = palette.quotaColor(for: quotaLevel)
        let percentText = QuotaFormatting.percent(remainingPercent)

        ZStack(alignment: .topLeading) {
            if let ringFrame = metrics.ringFrame {
                RingGaugeView(
                    remainingPercent: remainingPercent,
                    color: color,
                    lineWidth: metrics.ringLineWidth
                )
                .frame(width: ringFrame.width, height: ringFrame.height)
                .position(x: ringFrame.midX, y: ringFrame.midY)
            }

            if let percentageFrame = metrics.percentageFrame {
                Text(percentText)
                    .font(.system(
                        size: metrics.percentageFontSize(for: percentText),
                        weight: .semibold,
                        design: .monospaced
                    ))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(
                        width: percentageFrame.width,
                        height: percentageFrame.height,
                        alignment: .leading
                    )
                    .position(x: percentageFrame.midX, y: percentageFrame.midY)
            }

            ConnectionBadgeView(
                badge: badge,
                color: palette.connectionBadgeColor(for: badge),
                size: metrics.badgeSymbolSize
            )
            .frame(width: metrics.badgeFrame.width, height: metrics.badgeFrame.height)
            .position(x: metrics.badgeFrame.midX, y: metrics.badgeFrame.midY)
            .accessibilityHidden(true)
        }
        .frame(width: metrics.contentSize.width, height: metrics.contentSize.height)
    }
}
