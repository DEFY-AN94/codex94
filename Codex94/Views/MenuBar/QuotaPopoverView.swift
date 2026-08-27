import AppKit
import SwiftUI

enum QuotaPopoverLayout {
    static let contentWidth: CGFloat = 500

    @MainActor
    static func install<Content: View>(
        _ contentViewController: NSHostingController<Content>,
        in popover: NSPopover
    ) {
        popover.contentViewController = contentViewController
        contentViewController.view.layoutSubtreeIfNeeded()
        resize(popover, toHeight: contentViewController.view.fittingSize.height)
    }

    @MainActor
    static func resize(_ popover: NSPopover, toHeight measuredHeight: CGFloat) {
        guard measuredHeight.isFinite, measuredHeight > 0 else { return }
        let contentSize = NSSize(width: contentWidth, height: ceil(measuredHeight))
        guard popover.contentSize != contentSize else { return }
        popover.contentSize = contentSize
    }
}

@MainActor
final class QuotaPopoverHostingController<Content: View>: NSHostingController<Content> {
    private weak var popover: NSPopover?
    private var resizeScheduled = false

    func install(in popover: NSPopover) {
        self.popover = popover
        popover.contentViewController = self
        view.layoutSubtreeIfNeeded()
        synchronizeSize()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        scheduleSizeSynchronization()
    }

    func synchronizeSize() {
        guard let popover else { return }
        let idealSize = sizeThatFits(in: NSSize(
            width: QuotaPopoverLayout.contentWidth,
            height: .greatestFiniteMagnitude
        ))
        QuotaPopoverLayout.resize(popover, toHeight: idealSize.height)
    }

    private func scheduleSizeSynchronization() {
        guard popover != nil, !resizeScheduled else { return }
        resizeScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            resizeScheduled = false
            synchronizeSize()
        }
    }
}

struct QuotaPopoverView: View {
    @ObservedObject var store: AppStore
    let openDashboard: () -> Void
    let quit: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if store.preferences.hasChosenIdentityMode {
                quotaContent
            } else {
                IdentityChoiceView(store: store)
            }
        }
        .frame(width: QuotaPopoverLayout.contentWidth, alignment: .top)
        .fixedSize(horizontal: true, vertical: true)
        .background(palette.background)
        .codex94Environment(store.preferences)
    }

    private var palette: Codex94Palette {
        Codex94Palette.resolve(store.preferences.theme, scheme: colorScheme)
    }

    private var quotaContent: some View {
        VStack(spacing: 0) {
            header
            if (store.snapshot?.displayableBuckets.count ?? 0) > 1 {
                Divider()
                modelPicker
            }
            Divider()
            quotaRows

            stateBanner

            Divider()
            menuBarQuotaPicker
            Divider()
            commandRows
        }
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let presentation = store.viewedStatusPresentation

            HStack(spacing: 12) {
                RingGaugeView(
                    remainingPercent: store.viewedWindow?.remainingPercent,
                    color: palette.quotaColor(for: presentation.quotaLevel),
                    lineWidth: 3
                )
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(QuotaFormatting.popoverTitle(
                        bucketName: viewedBucketName,
                        planType: store.viewedBucket?.planType,
                        remainingPercent: store.viewedWindow?.remainingPercent,
                        language: store.preferences.language
                    ))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        ConnectionBadgeView(
                            badge: presentation.connectionBadge,
                            color: palette.connectionAccent,
                            size: 9
                        )
                        .accessibilityHidden(true)

                        StatusVisibleText.context(presentation, now: context.date)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(headerAccessibilityLabel(
                presentation: presentation,
                now: context.date
            ))
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var viewedBucketName: String {
        guard let snapshot = store.snapshot, let bucket = store.viewedBucket else {
            return "Codex"
        }
        return snapshot.displayName(for: bucket)
    }

    private func headerAccessibilityLabel(
        presentation: StatusPresentation,
        now: Date
    ) -> Text {
        var label = Text(verbatim: viewedBucketName)
        if let window = store.viewedWindow {
            label = label
                + Text(verbatim: ", ")
                + StatusAccessibilityText.quotaWindow(window.kind)
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
            + StatusAccessibilityText.statusContext(presentation, now: now)
        return label
    }

    private var modelPicker: some View {
        HStack(spacing: 12) {
            Text("quota.model")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Picker("quota.model", selection: Binding(
                get: { store.viewedBucket?.limitID ?? store.snapshot?.defaultLimitID ?? "" },
                set: { store.setViewedBucket($0) }
            )) {
                ForEach(store.snapshot?.displayableBuckets ?? []) { bucket in
                    Text(verbatim: QuotaFormatting.shortBucketName(
                        store.snapshot?.displayName(for: bucket) ?? bucket.limitID
                    ))
                    .tag(bucket.limitID)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 300)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private var quotaRows: some View {
        VStack(spacing: 14) {
            if let fiveHour = store.viewedBucket?.window(.fiveHour) {
                QuotaWindowRow(
                    window: fiveHour,
                    palette: palette,
                    language: store.preferences.language
                )
            }
            if let weekly = store.viewedBucket?.window(.weekly) {
                QuotaWindowRow(
                    window: weekly,
                    palette: palette,
                    language: store.preferences.language
                )
            }
            if store.viewedBucket?.windows.isEmpty != false {
                HStack(spacing: 12) {
                    Text("--")
                        .frame(width: 58, alignment: .leading)
                    Text(String(repeating: "░", count: 20))
                        .foregroundStyle(.secondary.opacity(0.45))
                        .lineLimit(1)
                        .frame(width: 170, alignment: .leading)
                    Text("--")
                        .frame(width: 54, alignment: .trailing)
                    Spacer()
                }
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var stateBanner: some View {
        let presentation = store.viewedStatusPresentation

        if presentation.usesCachedData {
            Divider()
            StatusBanner(
                badge: .stale,
                color: palette.connectionAccent,
                text: cachedBannerText(presentation: presentation),
                accessibilityText: cachedBannerText(presentation: presentation)
            )
        } else if presentation.connectionBadge == .unavailable {
            Divider()
            StatusBanner(
                badge: .unavailable,
                color: palette.connectionAccent,
                text: issueText(for: presentation),
                accessibilityText: issueText(for: presentation)
            )
        }
    }

    private func issueText(for presentation: StatusPresentation) -> Text {
        Text(presentation.issue?.localizedKey ?? "error.connectionFailed")
    }

    private func cachedBannerText(
        presentation: StatusPresentation
    ) -> Text {
        let issue = presentation.issue?.localizedKey ?? "error.connectionFailed"
        return Text("status.cached")
            + Text(verbatim: " · ")
            + Text(issue)
    }

    private var menuBarQuotaPicker: some View {
        HStack(spacing: 12) {
            Text("display.label")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            MenuBarQuotaPicker(store: store)
                .frame(maxWidth: 300)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var commandRows: some View {
        VStack(spacing: 2) {
            CommandRow(
                title: Text("command.refresh"),
                systemImage: "arrow.clockwise",
                shortcut: "⌘R",
                action: { store.refresh(trigger: .manual) }
            )
            .keyboardShortcut("r", modifiers: .command)

            CommandRow(
                title: Text("command.dashboard"),
                systemImage: "slider.horizontal.3",
                shortcut: "⌘,",
                action: openDashboard
            )
            .keyboardShortcut(",", modifiers: .command)

            Divider().padding(.vertical, 5)

            CommandRow(
                title: Text("command.quit"),
                systemImage: "power",
                shortcut: "⌘Q",
                action: quit
            )
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

struct MenuBarQuotaPicker: View {
    @ObservedObject var store: AppStore

    var body: some View {
        HStack(spacing: 8) {
            Picker("display.label", selection: Binding(
                get: { store.preferences.menuBarQuotaSelection },
                set: { store.setMenuBarQuotaSelection($0) }
            )) {
                ForEach(store.menuBarQuotaOptions) { option in
                    optionLabel(option)
                        .tag(option.selection)
                        .disabled(!option.isAvailable)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if store.menuBarSelectionUsesFallback {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("display.selectionUnavailable")
                    .accessibilityLabel(Text("display.selectionUnavailable"))
            }
        }
    }

    private func optionLabel(_ option: MenuBarQuotaOption) -> Text {
        guard option.selection != .automatic, let kind = option.kind else {
            return Text("display.auto")
        }

        let bucket: Text
        if let bucketName = option.bucketName {
            bucket = Text(verbatim: QuotaFormatting.shortBucketName(bucketName))
        } else {
            bucket = Text("display.savedQuota")
        }

        let label = bucket + Text(verbatim: " · ") + Text(kind.localizedKey)
        if option.isAvailable {
            return label
        }
        return label + Text(verbatim: " · ") + Text("status.unavailable")
    }
}

private struct QuotaWindowRow: View {
    let window: QuotaWindowSnapshot
    let palette: Codex94Palette
    let language: LanguagePreference

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let countdown = QuotaLocalizedString.resetCountdown(
                QuotaFormatting.resetCountdown(to: window.resetsAt, now: context.date),
                language: language
            )
            let accessibilityCountdown = QuotaLocalizedString.accessibilityResetCountdown(
                QuotaFormatting.resetCountdown(to: window.resetsAt, now: context.date),
                language: language
            )
            HStack(spacing: 12) {
                Text(window.kind.localizedKey)
                    .foregroundStyle(palette.quotaColor(
                        for: QuotaLevel(remainingPercent: window.remainingPercent)
                    ))
                    .frame(width: 58, alignment: .leading)

                QuotaBarView(
                    remainingPercent: window.remainingPercent,
                    color: palette.quotaColor(
                        for: QuotaLevel(remainingPercent: window.remainingPercent)
                    )
                )

                Text(QuotaFormatting.percent(window.remainingPercent))
                    .monospacedDigit()
                    .foregroundStyle(palette.quotaColor(
                        for: QuotaLevel(remainingPercent: window.remainingPercent)
                    ))
                    .frame(width: 54, alignment: .trailing)

                (Text("quota.resets")
                 + Text(verbatim: " \(countdown)"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(resetCountdown: accessibilityCountdown))
        }
    }

    private func accessibilityLabel(resetCountdown: String?) -> Text {
        var label = StatusAccessibilityText.quotaWindow(window.kind)
            + Text(verbatim: ", ")
            + StatusAccessibilityText.remainingPercent(
                QuotaFormatting.percent(window.remainingPercent)
            )
        if let resetCountdown {
            label = label
                + Text(verbatim: ", ")
                + StatusAccessibilityText.resets(resetCountdown)
        }
        return label
    }
}

private struct StatusBanner: View {
    let badge: ConnectionBadge
    let color: Color
    let text: Text
    let accessibilityText: Text

    var body: some View {
        HStack(spacing: 9) {
            ConnectionBadgeView(badge: badge, color: color, size: 11)
                .accessibilityHidden(true)
            text
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

private struct CommandRow: View {
    let title: Text
    let systemImage: String
    let shortcut: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                title
                Spacer()
                Text(shortcut)
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 9)
            .frame(height: 34)
            .contentShape(Rectangle())
            .background(hovering ? Color.accentColor.opacity(0.13) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct IdentityChoiceView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "circle.dotted.circle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("identity.title")
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    Text("identity.subtitle")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)

            Divider()

            IdentityOption(
                icon: "person.crop.circle.badge.checkmark",
                title: Text("identity.account"),
                detail: Text("identity.account.detail"),
                highlighted: true,
                action: { store.chooseIdentityMode(.quotaAndAccount) }
            )
            IdentityOption(
                icon: "gauge.with.dots.needle.50percent",
                title: Text("identity.quotaOnly"),
                detail: Text("identity.quotaOnly.detail"),
                highlighted: false,
                action: { store.chooseIdentityMode(.quotaOnly) }
            )
        }
        .padding(.bottom, 10)
    }
}

private struct IdentityOption: View {
    let icon: String
    let title: Text
    let detail: Text
    let highlighted: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(highlighted ? Color.accentColor : Color.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    title.font(.system(size: 13, weight: .semibold))
                    detail
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 56)
            .contentShape(Rectangle())
            .background(
                hovering || highlighted
                    ? Color.accentColor.opacity(highlighted ? 0.12 : 0.08)
                    : .clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }
}
