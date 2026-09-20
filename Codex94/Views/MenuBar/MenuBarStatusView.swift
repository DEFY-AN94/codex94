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
        let palette = Codex94Palette.resolve(
            store.preferences.theme,
            scheme: colorScheme,
            overrides: store.preferences.statusAccentOverrides
        )
        let resolvedQuota = store.menuBarQuota
        let window = resolvedQuota?.window
        let layout = store.preferences.menuBarLayout
        let dualWindowBucket = store.dualWindowBucket
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
            palette: palette,
            dualWindowBucket: dualWindowBucket
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
        if store.preferences.menuBarLayout == .dualWindow {
            let bucket = store.dualWindowBucket
            return dualWindowAccessibilityLabel(
                bucketName: bucket.flatMap { store.snapshot?.displayName(for: $0) } ?? "Codex",
                bucket: bucket,
                presentation: presentation,
                now: now,
                language: store.preferences.language
            )
        }
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

    static func dualWindowAccessibilityLabel(
        bucketName: String,
        bucket: QuotaBucketSnapshot?,
        presentation: StatusPresentation,
        now: Date,
        language: LanguagePreference,
        bundle: Bundle = .main
    ) -> String {
        func localized(_ key: String, arguments: [CVarArg] = []) -> String {
            StatusAccessibilityString.localized(
                key, arguments: arguments, language: language, bundle: bundle
            )
        }
        var components = [bucketName]
        for kind in [QuotaWindowKind.fiveHour, .weekly] {
            components.append(localized(kind == .fiveHour
                ? "accessibility.quotaWindow.fiveHour" : "accessibility.quotaWindow.weekly"))
            if let window = bucket?.window(kind) {
                components.append(localized(
                    "accessibility.remainingPercent %@",
                    arguments: [QuotaFormatting.percent(window.remainingPercent)]
                ))
                components.append(QuotaResetPresentation(
                    resetsAt: window.resetsAt, now: now, language: language, bundle: bundle
                ).accessibilityLabel)
            } else {
                components.append(localized("accessibility.unavailableQuota"))
            }
        }
        components.append(StatusAccessibilityString.statusContext(
            presentation, now: now, language: language, bundle: bundle
        ))
        return components.joined(separator: ", ")
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
    var dualWindowBucket: QuotaBucketSnapshot? = nil

    var body: some View {
        let metrics = layout.metrics
        let color = palette.quotaColor(for: quotaLevel)
        let percentText = QuotaFormatting.percent(remainingPercent)

        ZStack(alignment: .topLeading) {
            if let fiveHourFrame = metrics.fiveHourFrame,
               let weeklyFrame = metrics.weeklyFrame {
                DualWindowMenuBarColumn(
                    title: "display.dualWindow.fiveHourShort",
                    remainingPercent: dualWindowBucket?.window(.fiveHour)?.remainingPercent,
                    palette: palette
                )
                .frame(width: fiveHourFrame.width, height: fiveHourFrame.height)
                .position(x: fiveHourFrame.midX, y: fiveHourFrame.midY)

                Text(verbatim: "·")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .position(x: (fiveHourFrame.maxX + weeklyFrame.minX) / 2, y: 11)

                DualWindowMenuBarColumn(
                    title: "display.dualWindow.weeklyShort",
                    remainingPercent: dualWindowBucket?.window(.weekly)?.remainingPercent,
                    palette: palette
                )
                .frame(width: weeklyFrame.width, height: weeklyFrame.height)
                .position(x: weeklyFrame.midX, y: weeklyFrame.midY)
            }

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

private struct DualWindowMenuBarColumn: View {
    let title: LocalizedStringKey
    let remainingPercent: Int?
    let palette: Codex94Palette

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
            Text(QuotaFormatting.percent(remainingPercent))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        }
        .foregroundStyle(palette.quotaColor(for: QuotaLevel(remainingPercent: remainingPercent)))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}
