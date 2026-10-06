import SwiftUI

enum ProviderQuotaDisplayStyle: Equatable {
    case card, terminal
}

/// A model-scoped weekly limit shown beneath the shared windows.
struct ProviderScopedLimit: Identifiable, Equatable {
    let id: String
    let name: String
    let window: QuotaWindowSnapshot

    /// Every displayable bucket beside the default one carries exactly the
    /// weekly window of one model.
    static func limits(in snapshot: QuotaSnapshot?) -> [ProviderScopedLimit] {
        guard let snapshot else { return [] }
        return snapshot.displayableBuckets.compactMap { bucket in
            guard bucket.limitID != snapshot.defaultLimitID, let window = bucket.window(.weekly) else { return nil }
            return ProviderScopedLimit(id: bucket.limitID, name: snapshot.displayName(for: bucket), window: window)
        }
    }
}

/// Observes Claude's own state. Reading/rendering this view never refreshes it.
struct ClaudeQuotaCard: View {
    @ObservedObject var store: ClaudeQuotaStore
    let language: LanguagePreference
    let openSetup: () -> Void
    var referenceDate: Date? = nil
    var accentOverrides = StatusAccentOverrides()
    var compact = false
    var style: ProviderQuotaDisplayStyle = .card
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
                passiveReportNeedsConfirmation: store.passiveReportNeedsConfirmation,
                style: style,
                localCacheState: store.localCacheState,
                historicalReport: store.historicalReport
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
    var style: ProviderQuotaDisplayStyle = .card
    var localCacheState: ClaudeLocalUsageCacheState = .absent
    var historicalReport: ClaudeQuotaHistoryPresentation? = nil

    /// History is a separate surface, never a replacement for an active window.
    var displayedHistory: ClaudeQuotaHistoryPresentation? {
        isEnabled && snapshot == nil ? historicalReport : nil
    }

    private var displayedSource: ClaudeQuotaSource? { displayedHistory?.source ?? source }

    var badge: ConnectionBadge {
        guard isEnabled else { return .none }
        if isRefreshing { return .refreshing }
        if displayedHistory != nil || needsSourceConfirmation || hasStaleReport || passiveWindowsExpired { return .stale }
        if visibleIssue != nil { return snapshot == nil ? .unavailable : .stale }
        return .none
    }

    /// Confirmation concerns the card only while the pending statusline report
    /// is what would be shown; another selected source keeps presenting its data.
    private var needsSourceConfirmation: Bool {
        issue == .sourceChanged || (passiveReportNeedsConfirmation && (source == nil || source == .statusline))
    }

    private var isPassiveSource: Bool {
        source == .localCache || source == .statusline
    }

    private var passiveWindowsExpired: Bool {
        isPassiveSource && reportedAt != nil && snapshot == nil && issue == .noData
    }

    private var hasStaleReport: Bool {
        issue == .staleData && (snapshot != nil || displayedHistory != nil || reportedAt != nil)
    }

    private var visibleIssue: ClaudeQuotaIssue? {
        guard isEnabled, let issue else { return nil }
        // An expired, unaccepted candidate does not establish a previous report.
        if issue == .staleData && !hasStaleReport { return nil }
        if !isCLIUsageEnabled {
            switch issue {
            case .setupRequired, .noData, .cliUnavailable, .loginRequired, .timedOut:
                // Waiting for a local report is not a login or network failure.
                // A failed one-time CLI read is reported beside its button instead.
                return nil
            default: break
            }
        }
        // With the option on, the store projects a CLI failure onto passive data
        // only while that data is out of date; it is shown as the reason.
        return issue
    }

    var statusKey: String? {
        guard isEnabled else { return nil }
        if isRefreshing { return "claude.refreshing" }
        if needsSourceConfirmation { return "claude.issue.sourceChanged" }
        if displayedHistory != nil && (issue == .staleData || issue == .noData) { return nil }
        if let issue = visibleIssue {
            // The empty-state line already describes a missing or unreadable report.
            return issue == .noData || (issue == .localCacheUnreadable && displayedHistory == nil)
                ? nil : issue.localizationKey
        }
        return nil
    }

    var sourceTitleKey: String {
        if let displayedSource { return displayedSource.localizationKey }
        return isCLIUsageEnabled ? "claude.source.waiting" : "claude.source.passive"
    }

    var refreshTitleKey: String {
        isCLIUsageEnabled ? "claude.refresh" : "claude.passive.reread"
    }

    var refreshHelpKey: String {
        isCLIUsageEnabled ? "claude.cliUsage.regularRefresh.help" : "claude.passive.reread.help"
    }

    var sourceTimeHelpKey: String? {
        displayedSource == .localCache ? "claude.localCacheTime.help" : nil
    }

    var emptyStateKey: String {
        guard isEnabled else { return "claude.monitoring.off" }
        if needsSourceConfirmation { return "claude.passive.confirmationRequired" }
        if hasStaleReport || passiveWindowsExpired { return "claude.passive.expiredEmpty" }
        if localCacheState == .unreadable { return "claude.localCache.unreadable" }
        if isCLIUsageEnabled, source == nil { return "claude.quota.empty" }
        if style == .terminal { return "claude.passive.waitingShort" }
        // A state file without usage data needs the same /usage instruction as a missing file.
        if localCacheState == .absent || localCacheState == .invalid, statuslineSetupState == .notInstalled {
            return "claude.localCache.absent"
        }
        return "claude.passive.waiting"
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
            refresh: refresh, openDetails: openSetup, timeZone: timeZone, compact: compact,
            style: style, explainsPassiveSource: displayedSource != .cliUsage,
            scopedLimits: ProviderScopedLimit.limits(in: snapshot),
            refreshHelp: LocalizedStringKey(refreshHelpKey),
            sourceTimeHelp: sourceTimeHelpKey.map { LocalizedStringKey($0) },
            historicalReport: displayedHistory,
            sourceAgeText: reportAgeText
        )
    }

    var sourceTimeText: String {
        if style != .terminal, let displayedHistory {
            return ClaudeQuotaHistoryFormatting.reportTime(
                displayedHistory, now: now, language: language, timeZone: timeZone
            )
        }
        return ClaudeQuotaHistoryFormatting.sourceTime(
            source: displayedSource, reportedAt: displayedHistory?.reportedAt ?? reportedAt,
            language: language, timeZone: timeZone
        )
    }

    var reportAgeText: String? {
        guard style == .terminal, let date = displayedHistory?.reportedAt ?? reportedAt else { return nil }
        return StatusAccessibilityString.localized(
            "claude.reportAge %@", arguments: [ClaudeQuotaHistoryFormatting.relativeAge(
                since: date, now: now, language: language
            )], language: language, bundle: .main
        )
    }

}

/// Shared metadata and actions with roomy Dashboard cards or terminal rows in
/// the menu popover. Changing presentation never changes a provider's source.
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
    var style: ProviderQuotaDisplayStyle = .card
    var explainsPassiveSource = false
    var detailSubtitle: String? = nil
    var windowIdentifierPrefix: String? = nil
    var resetLocale: Locale? = nil
    var resetCalendar = Calendar(identifier: .gregorian)
    var scopedLimits: [ProviderScopedLimit] = []
    var refreshHelp: LocalizedStringKey? = nil
    var sourceTimeHelp: LocalizedStringKey? = nil
    var historicalReport: ClaudeQuotaHistoryPresentation? = nil
    var sourceAgeText: String? = nil

    private var isTerminal: Bool { style == .terminal }

    var body: some View {
        VStack(alignment: .leading, spacing: isTerminal ? 8 : compact ? 9 : 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: provider.systemImageName)
                    .font(.system(size: isTerminal ? 14 : compact ? 19 : 21, weight: .medium))
                    .foregroundStyle(provider == .claude ? Color.orange : palette.connectionAccent)
                    .frame(width: isTerminal ? 18 : 26, height: isTerminal ? 20 : 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(isTerminal ? .system(size: 13, weight: .semibold, design: .monospaced) : .headline)
                        .lineLimit(1).help(Text(verbatim: title))
                    Text(sourceTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .help(Text(sourceTitle))
                    if let detailSubtitle {
                        Text(verbatim: detailSubtitle).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).help(Text(verbatim: detailSubtitle))
                    }
                }
                Spacer(minLength: 8)
                if badge != .none {
                    ConnectionBadgeView(badge: badge, color: palette.connectionBadgeColor(for: badge), size: 11)
                        .accessibilityHidden(true)
                }
                if compact || isTerminal {
                    Button(action: openDetails) { Image(systemName: "info.circle") }
                        .buttonStyle(.borderless)
                        .help(Text(detailsLabel)).accessibilityLabel(Text(detailsLabel))
                        .accessibilityIdentifier(provider == .claude ? "claude-open-setup" : "provider-codex-open-details")
                }
                Button(action: refresh) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(!canRefresh)
                    .help(Text(refreshHelp ?? refreshLabel)).accessibilityLabel(Text(refreshLabel))
                    .accessibilityIdentifier(provider == .claude ? "claude-refresh" : "provider-codex-refresh")
            }

            if provider == .claude, windows.isEmpty, let historicalReport {
                ClaudeQuotaHistoryView(report: historicalReport, language: language, palette: palette, style: style)
            } else if windows.isEmpty {
                Text(emptyText).font(.callout).foregroundStyle(.secondary)
                    .lineLimit(isTerminal || compact ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(provider.rawValue + "-quota-empty")
            } else if isTerminal {
                VStack(spacing: 11) {
                    ForEach(windows.sorted { $0.kind.sortOrder < $1.kind.sortOrder }) { window in
                        QuotaWindowRowContent(
                            window: window, palette: palette, reset: resetPresentation(window),
                            accessibilityIdentifier: windowIdentifier(window), language: language,
                            showsResetCountdown: !(provider == .claude && window.kind == .fiveHour)
                        )
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(windows.sorted { $0.kind.sortOrder < $1.kind.sortOrder }) { window in
                        windowContent(window)
                    }
                }
            }

            if !windows.isEmpty, !scopedLimits.isEmpty {
                VStack(alignment: .leading, spacing: isTerminal ? 4 : 6) {
                    Text("claude.modelLimits.title")
                        .font(isTerminal ? .system(size: 11, design: .monospaced) : .caption)
                        .foregroundStyle(.secondary)
                    ForEach(scopedLimits) { limit in
                        scopedLimitRow(limit)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(provider.rawValue + "-model-limits")
            }

            if provider == .claude && windows.isEmpty {
                if explainsPassiveSource && !isTerminal && historicalReport == nil {
                    Text("claude.passive.codeRequired")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Link("claude.officialUsage", destination: Self.officialClaudeUsageURL)
                    .font(.caption)
                    .accessibilityIdentifier("claude-official-usage")
            }

            VStack(alignment: .leading, spacing: compact ? 3 : 5) {
                if let statusText {
                    (usesCachedData ? Text("status.cached") + Text(verbatim: " · ") + statusText : statusText)
                        .foregroundStyle(badge == .refreshing ? palette.connectionAccent
                            : badge == .unavailable ? palette.errorColor : palette.staleAccent)
                        .lineLimit(isTerminal || compact ? 1 : nil)
                        .help(statusText)
                        .accessibilityIdentifier(provider.rawValue + "-issue")
                } else if usesCachedData {
                    Text("status.cached").foregroundStyle(palette.staleAccent)
                }
                Text(verbatim: sourceTimeText).foregroundStyle(.secondary)
                    .lineLimit(historicalReport != nil ? nil : isTerminal || compact ? 1 : nil)
                    .help(sourceTimeTooltip)
                    .accessibilityIdentifier(provider.rawValue + "-source-time")
                if let sourceAgeText {
                    Text(verbatim: sourceAgeText).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(provider.rawValue + "-source-age")
                }
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)

            if !compact && !isTerminal && showsDetails {
                Button(detailsLabel, action: openDetails).controlSize(.small)
                    .accessibilityIdentifier(provider == .claude ? "claude-open-setup" : "provider-codex-open-details")
            }
        }
        .padding(isTerminal ? 0 : compact ? 14 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if !isTerminal { RoundedRectangle(cornerRadius: 12).fill(palette.elevated) }
        }
        .overlay {
            if !isTerminal { RoundedRectangle(cornerRadius: 12).stroke(palette.border, lineWidth: 1) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(provider == .claude ? "claude-quota-section" : "codex-quota-section")
    }

    static let officialClaudeUsageURL = URL(string: "https://claude.ai/settings/usage")!

    private var sourceTimeTooltip: Text {
        let time = Text(verbatim: sourceTimeText)
        guard let sourceTimeHelp else { return time }
        return time + Text(verbatim: "\n") + Text(sourceTimeHelp)
    }

    private func windowIdentifier(_ window: QuotaWindowSnapshot) -> String {
        (windowIdentifierPrefix ?? (provider == .claude ? "claude-quota" : "provider-codex-quota"))
            + "-" + window.kind.rawValue
    }

    private func resetPresentation(_ window: QuotaWindowSnapshot) -> QuotaResetPresentation {
        QuotaResetPresentation(resetsAt: window.resetsAt, now: now, language: language,
                               locale: resetLocale, calendar: resetCalendar, timeZone: timeZone)
    }

    private func windowContent(_ window: QuotaWindowSnapshot) -> some View {
        let percent = QuotaFormatting.percent(precise: window.preciseRemainingPercent, language: language)
        let color = palette.quotaColor(for: QuotaLevel(preciseRemainingPercent: window.preciseRemainingPercent))
        let reset = resetPresentation(window)
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
            Text(verbatim: reset.absolute)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            StatusAccessibilityText.quotaWindow(window.kind)
                + Text(verbatim: ", ") + StatusAccessibilityText.remainingPercent(percent)
                + Text(verbatim: ", " + reset.accessibilityLabel)
        )
        .accessibilityIdentifier(windowIdentifier(window))
    }

    /// One compact line per model: name, remaining share and reset countdown.
    private func scopedLimitRow(_ limit: ProviderScopedLimit) -> some View {
        let percent = QuotaFormatting.percent(precise: limit.window.preciseRemainingPercent, language: language)
        let color = palette.quotaColor(for: QuotaLevel(preciseRemainingPercent: limit.window.preciseRemainingPercent))
        let reset = resetPresentation(limit.window)
        return HStack(spacing: 8) {
            Text(verbatim: limit.name).fontWeight(.medium).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: 180, alignment: .leading)
            Text(verbatim: percent).monospacedDigit().foregroundStyle(color)
                .fixedSize(horizontal: true, vertical: false).layoutPriority(2)
            Text("floating.remaining").foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false).layoutPriority(2)
            (Text("quota.resets") + Text(verbatim: " " + reset.countdown))
                .foregroundStyle(.secondary).lineLimit(1).layoutPriority(1)
            Spacer(minLength: 0)
        }
        .font(isTerminal ? .system(size: 12, design: .monospaced) : .caption)
        .help(Text(verbatim: reset.absolute))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(verbatim: limit.name + ", ")
                + StatusAccessibilityText.remainingPercent(percent)
                + Text(verbatim: ", " + reset.accessibilityLabel)
        )
        .accessibilityIdentifier(provider.rawValue + "-model-limit-" + limit.id)
    }
}
