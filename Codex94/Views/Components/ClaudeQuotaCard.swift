import SwiftUI

/// Observes Claude's own state. Reading/rendering this view never refreshes it.
struct ClaudeQuotaCard: View {
    @ObservedObject var store: ClaudeQuotaStore
    let language: LanguagePreference
    let openSetup: () -> Void
    var referenceDate: Date? = nil
    var accentOverrides = StatusAccentOverrides()
    var compact = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ClaudeQuotaCardContent(
                snapshot: store.snapshot,
                source: store.source,
                reportedAt: store.reportedAt,
                issue: store.lastIssue,
                isRefreshing: store.isRefreshing,
                isEnabled: store.isEnabled,
                language: language,
                now: referenceDate ?? context.date,
                palette: .resolve(.system, scheme: colorScheme, overrides: accentOverrides),
                refresh: { store.refresh(trigger: .manual) },
                openSetup: openSetup,
                compact: compact,
                isCLIUsageEnabled: store.isCLIUsageEnabled,
                statuslineSetupState: store.statuslineSetupState,
                passiveReportNeedsConfirmation: store.passiveReportNeedsConfirmation
            )
        }
    }
}

/// Value-only content keeps synthetic rendering independent of Claude files,
/// executable discovery, timers, or settings writes.
struct ClaudeQuotaCardContent: View {
    let snapshot: QuotaSnapshot?
    let source: ClaudeQuotaSource?
    let reportedAt: Date?
    let issue: ClaudeQuotaIssue?
    let isRefreshing: Bool
    let isEnabled: Bool
    let language: LanguagePreference
    let now: Date
    let palette: Codex94Palette
    let refresh: () -> Void
    let openSetup: () -> Void
    var timeZone: TimeZone = .autoupdatingCurrent

    var compact = false
    var isCLIUsageEnabled = false
    var statuslineSetupState: ClaudeStatuslineSetupState = .notInstalled
    var passiveReportNeedsConfirmation = false

    var badge: ConnectionBadge {
        guard isEnabled else { return .none }
        if isCLIUsageEnabled && isRefreshing { return .refreshing }
        if needsSourceConfirmation || issue == .staleData || passiveWindowsExpired { return .stale }
        if visibleIssue != nil { return snapshot == nil ? .unavailable : .stale }
        return .none
    }

    private var needsSourceConfirmation: Bool {
        !isCLIUsageEnabled && (passiveReportNeedsConfirmation || issue == .sourceChanged)
    }

    private var passiveWindowsExpired: Bool {
        !isCLIUsageEnabled && source == .statusline && reportedAt != nil
            && snapshot == nil && issue == .noData
    }

    private var visibleIssue: ClaudeQuotaIssue? {
        guard isEnabled, let issue else { return nil }
        if !isCLIUsageEnabled {
            switch issue {
            case .setupRequired, .noData, .cliUnavailable, .loginRequired, .timedOut:
                // Waiting for a local report is not a login or network failure.
                return nil
            default: break
            }
        }
        return issue
    }

    var statusKey: String? {
        guard isEnabled else { return nil }
        if isCLIUsageEnabled && isRefreshing { return "claude.refreshing" }
        if needsSourceConfirmation { return "claude.issue.sourceChanged" }
        if let issue = visibleIssue {
            // The empty-state line already describes a missing report.
            return issue == .noData ? nil : issue.localizationKey
        }
        return nil
    }

    var sourceTitleKey: String {
        if let source { return source.localizationKey }
        return isCLIUsageEnabled ? "claude.source.waiting" : "claude.source.statusline"
    }

    var refreshTitleKey: String {
        isCLIUsageEnabled ? "claude.refresh" : "claude.passive.reread"
    }

    var emptyStateKey: String {
        guard isEnabled else { return "claude.monitoring.off" }
        if needsSourceConfirmation { return "claude.passive.confirmationRequired" }
        if !isCLIUsageEnabled {
            if issue == .staleData || passiveWindowsExpired { return "claude.passive.expiredEmpty" }
            return statuslineSetupState == .notInstalled
                ? "claude.passive.notConfigured" : "claude.passive.waiting"
        }
        return "claude.quota.empty"
    }

    private var statusText: Text? {
        statusKey.map { Text(LocalizedStringKey($0)) }
    }

    var body: some View {
        ProviderQuotaCardContent(
            provider: .claude, title: "Claude", sourceTitle: LocalizedStringKey(sourceTitleKey),
            windows: snapshot?.defaultBucket?.windows ?? [], badge: badge,
            usesCachedData: snapshot != nil && badge == .stale,
            statusText: statusText, sourceTimeText: sourceTimeText,
            emptyText: LocalizedStringKey(emptyStateKey),
            refreshLabel: LocalizedStringKey(refreshTitleKey), detailsLabel: "claude.openSetup",
            canRefresh: isEnabled && !isRefreshing, showsDetails: snapshot == nil || issue != nil,
            language: language, now: now, palette: palette,
            refresh: refresh, openDetails: openSetup, timeZone: timeZone, compact: compact
        )
    }

    var sourceTimeText: String {
        guard let reportedAt, let timestamp = QuotaFormatting.absoluteReset(
            to: reportedAt, locale: language.locale,
            calendar: Calendar(identifier: .gregorian), timeZone: timeZone
        ) else {
            return StatusAccessibilityString.localized("claude.sourceTime.unavailable", language: language, bundle: .main)
        }
        return StatusAccessibilityString.localized(
            source == .statusline ? "claude.localReportTime %@" : "claude.sourceTime %@",
            arguments: [timestamp], language: language, bundle: .main
        )
    }

}

/// Shared quota geometry for the two compact summaries. Codex's detailed,
/// single-provider interface stays separate and unchanged.
struct ProviderQuotaCardContent: View {
    let provider: QuotaProviderID
    let title: String
    let sourceTitle: LocalizedStringKey
    let windows: [QuotaWindowSnapshot]
    let badge: ConnectionBadge
    let usesCachedData: Bool
    let statusText: Text?
    let sourceTimeText: String
    let emptyText: LocalizedStringKey
    let refreshLabel: LocalizedStringKey
    let detailsLabel: LocalizedStringKey
    let canRefresh: Bool
    let showsDetails: Bool
    let language: LanguagePreference
    let now: Date
    let palette: Codex94Palette
    let refresh: () -> Void
    let openDetails: () -> Void
    var timeZone: TimeZone = .autoupdatingCurrent
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 9 : 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: provider.systemImageName)
                    .font(.system(size: compact ? 19 : 21, weight: .medium))
                    .foregroundStyle(provider == .claude ? Color.orange : palette.connectionAccent)
                    .frame(width: 26, height: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).font(.headline).lineLimit(1).help(Text(verbatim: title))
                    Text(sourceTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if badge != .none {
                    ConnectionBadgeView(badge: badge, color: palette.connectionBadgeColor(for: badge), size: 11)
                        .accessibilityHidden(true)
                }
                if compact {
                    Button(action: openDetails) { Image(systemName: "info.circle") }
                        .buttonStyle(.borderless)
                        .help(Text(detailsLabel)).accessibilityLabel(Text(detailsLabel))
                        .accessibilityIdentifier(provider == .claude ? "claude-open-setup" : "provider-codex-open-details")
                }
                Button(action: refresh) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(!canRefresh)
                    .help(Text(refreshLabel)).accessibilityLabel(Text(refreshLabel))
                    .accessibilityIdentifier(provider == .claude ? "claude-refresh" : "provider-codex-refresh")
            }

            if windows.isEmpty {
                Text(emptyText).font(.callout).foregroundStyle(.secondary)
                    .lineLimit(compact ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(provider.rawValue + "-quota-empty")
            } else {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(windows.sorted { $0.kind.sortOrder < $1.kind.sortOrder }) { window in
                        windowContent(window)
                    }
                }
            }

            VStack(alignment: .leading, spacing: compact ? 3 : 5) {
                if let statusText {
                    (usesCachedData ? Text("status.cached") + Text(verbatim: " · ") + statusText : statusText)
                        .foregroundStyle(badge == .refreshing ? palette.connectionAccent
                            : badge == .unavailable ? palette.errorColor : palette.staleAccent)
                        .lineLimit(compact ? 1 : nil)
                        .help(statusText)
                        .accessibilityIdentifier(provider.rawValue + "-issue")
                } else if usesCachedData {
                    Text("status.cached").foregroundStyle(palette.staleAccent)
                }
                Text(verbatim: sourceTimeText).foregroundStyle(.secondary)
                    .lineLimit(compact ? 1 : nil)
                    .help(Text(verbatim: sourceTimeText))
                    .accessibilityIdentifier(provider.rawValue + "-source-time")
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)

            if !compact && showsDetails {
                Button(detailsLabel, action: openDetails).controlSize(.small)
                    .accessibilityIdentifier(provider == .claude ? "claude-open-setup" : "provider-codex-open-details")
            }
        }
        .padding(compact ? 14 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.elevated, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(provider == .claude ? "claude-quota-section" : "codex-quota-section")
    }

    private func windowContent(_ window: QuotaWindowSnapshot) -> some View {
        let percent = QuotaFormatting.percent(precise: window.preciseRemainingPercent, language: language)
        let color = palette.quotaColor(for: QuotaLevel(preciseRemainingPercent: window.preciseRemainingPercent))
        let reset = QuotaResetPresentation(
            resetsAt: window.resetsAt, now: now, language: language, timeZone: timeZone
        )
        return VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            Text(window.kind.localizedKey).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(verbatim: percent)
                    .font(.system(size: compact ? 23 : 25, weight: .semibold, design: .rounded))
                    .monospacedDigit().foregroundStyle(color)
                Text("floating.remaining").font(.caption2).foregroundStyle(.secondary)
            }
            ProgressView(value: window.preciseRemainingPercent, total: 100)
                .tint(color).controlSize(.small).accessibilityHidden(true)
            (Text("quota.resets") + Text(verbatim: " " + reset.countdown))
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).help(Text(verbatim: reset.absolute))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            StatusAccessibilityText.quotaWindow(window.kind)
                + Text(verbatim: ", ") + StatusAccessibilityText.remainingPercent(percent)
                + Text(verbatim: ", " + reset.accessibilityLabel)
        )
        .accessibilityIdentifier(provider == .claude ? "claude-quota-" + window.kind.rawValue
            : "provider-codex-quota-" + window.kind.rawValue)
    }
}
