import SwiftUI

enum ProviderQuotaDisplayStyle: Equatable {
    case card, terminal
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
                sourceMode: store.sourceMode,
                oauthIssue: store.oauthIssue,
                oauthIdentityIssue: store.oauthIdentityIssue,
                identityConfidence: store.identityConfidence,
                oauthIdentityPending: store.oauthIdentityPending,
                isUsingOAuthFallback: store.isUsingOAuthFallback,
                oauthIsCached: store.oauthIsCached,
                nextAutomaticRefreshAt: store.nextAutomaticRefreshAt,
                oauthRetryAllowedAt: store.oauthRetryAllowedAt
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
    var sourceMode: ClaudeQuotaSourceMode = .statuslineOnly
    var oauthIssue: ClaudeOAuthIssue? = nil
    var oauthIdentityIssue: ClaudeOAuthIssue? = nil
    var identityConfidence: ClaudeQuotaIdentityConfidence = .unknown
    var oauthIdentityPending = false
    var isUsingOAuthFallback = false
    var oauthIsCached = false
    var nextAutomaticRefreshAt: Date? = nil
    var oauthRetryAllowedAt: Date? = nil

    // Preserve older pure-content CLI fixtures; the production wrapper always
    // passes the store's explicit source mode and consistent compatibility flag.
    private var usesCLI: Bool { sourceMode == .legacyCLI || (sourceMode == .statuslineOnly && isCLIUsageEnabled) }
    private var usesOAuth: Bool { sourceMode == .oauthPreferred }

    var badge: ConnectionBadge {
        guard isEnabled else { return .none }
        if (usesCLI || usesOAuth) && isRefreshing { return .refreshing }
        if usesOAuth {
            if oauthIsCached || isUsingOAuthFallback || needsSourceConfirmation { return .stale }
            if oauthIssue != nil || visibleIssue != nil { return snapshot == nil ? .unavailable : .stale }
            return .none
        }
        if needsSourceConfirmation || issue == .staleData || passiveWindowsExpired { return .stale }
        if visibleIssue != nil { return snapshot == nil ? .unavailable : .stale }
        return .none
    }

    private var needsSourceConfirmation: Bool {
        !usesCLI && (passiveReportNeedsConfirmation || issue == .sourceChanged)
    }

    private var passiveWindowsExpired: Bool {
        !usesCLI && source == .statusline && reportedAt != nil
            && snapshot == nil && issue == .noData
    }

    private var visibleIssue: ClaudeQuotaIssue? {
        guard isEnabled, let issue else { return nil }
        if !usesCLI && !usesOAuth {
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
        if (usesCLI || usesOAuth) && isRefreshing { return "claude.refreshing" }
        if usesOAuth, let oauthIssue { return oauthIssue.quotaIssue.localizationKey }
        if needsSourceConfirmation { return "claude.issue.sourceChanged" }
        if let issue = visibleIssue {
            // The empty-state line already describes a missing report.
            return issue == .noData ? nil : issue.localizationKey
        }
        return nil
    }

    var sourceTitleKey: String {
        if usesOAuth && isUsingOAuthFallback { return "claude.oauth.fallback.source" }
        if let source { return source.localizationKey }
        if usesOAuth { return "claude.source.oauth" }
        return usesCLI ? "claude.source.waiting" : "claude.source.statusline"
    }

    var refreshTitleKey: String {
        if usesOAuth { return "claude.oauth.refresh" }
        return usesCLI ? "claude.refresh" : "claude.passive.reread"
    }

    var emptyStateKey: String {
        guard isEnabled else { return "claude.monitoring.off" }
        if needsSourceConfirmation { return "claude.passive.confirmationRequired" }
        if usesOAuth {
            if let oauthIssue { return oauthIssue.quotaIssue.localizationKey }
            if let issue { return issue.localizationKey }
            if let cooldownDeadline, cooldownDeadline > now { return "claude.oauth.rateLimited" }
            return isRefreshing ? "claude.refreshing" : "claude.oauth.notConnected"
        }
        if !usesCLI {
            if issue == .staleData || passiveWindowsExpired { return "claude.passive.expiredEmpty" }
            if style == .terminal { return "claude.passive.waitingShort" }
            return statuslineSetupState == .notInstalled
                ? "claude.passive.notConfigured" : "claude.passive.waiting"
        }
        return "claude.quota.empty"
    }

    private var statusText: Text? {
        statusKey.map { Text(LocalizedStringKey($0)) }
    }

    var usesCachedData: Bool {
        guard snapshot != nil else { return false }
        return usesOAuth ? oauthIsCached : badge == .stale
    }

    var canRefresh: Bool {
        guard isEnabled, !isRefreshing else { return false }
        if usesOAuth, let cooldownDeadline, cooldownDeadline > now { return false }
        return true
    }

    private var cooldownDeadline: Date? {
        let issueDates = [oauthIssue, oauthIdentityIssue].compactMap { issue -> Date? in
            if case let .rateLimited(date) = issue { return date }
            return nil
        }
        return (issueDates + [oauthRetryAllowedAt].compactMap { $0 }).max()
    }

    var sourceDetails: [String] {
        guard isEnabled, usesOAuth else { return [] }
        func localized(_ key: String) -> String {
            StatusAccessibilityString.localized(key, language: language, bundle: .main)
        }
        var details: [String] = []
        if source == .oauth, snapshot != nil,
           oauthIdentityPending || identityConfidence != .verifiedOAuth || oauthIdentityIssue != nil {
            let reason = oauthIdentityIssue.map { localized($0.quotaIssue.localizationKey) }
            details.append(localized("claude.oauth.identity.pending") + (reason.map { " · " + $0 } ?? ""))
        }
        if passiveReportNeedsConfirmation { details.append(localized("claude.oauth.fallback.pending")) }
        if isUsingOAuthFallback { details.append(localized("claude.oauth.unverifiedNotifications")) }
        if oauthIssue != nil || cooldownDeadline != nil {
            let next: Date?
            if let retryNotBefore = cooldownDeadline {
                next = max(retryNotBefore, nextAutomaticRefreshAt ?? retryNotBefore)
            } else { next = nextAutomaticRefreshAt }
            if let text = ConnectionRecoveryText.nextAttempt(at: next, language: language) { details.append(text) }
        }
        return details
    }

    var body: some View {
        ProviderQuotaCardContent(
            provider: .claude, title: "Claude", sourceTitle: LocalizedStringKey(sourceTitleKey),
            windows: snapshot?.defaultBucket?.windows ?? [], badge: badge,
            usesCachedData: usesCachedData,
            statusText: statusText, sourceTimeText: sourceTimeText,
            emptyText: LocalizedStringKey(emptyStateKey),
            refreshLabel: LocalizedStringKey(refreshTitleKey), detailsLabel: "claude.openSetup",
            canRefresh: canRefresh, showsDetails: snapshot == nil || issue != nil || !sourceDetails.isEmpty,
            language: language, now: now, palette: palette,
            refresh: refresh, openDetails: openSetup, timeZone: timeZone, compact: compact,
            style: style, explainsPassiveSource: !usesCLI && !usesOAuth,
            sourceDetails: sourceDetails
        )
    }

    var sourceTimeText: String {
        guard let reportedAt, let timestamp = QuotaFormatting.absoluteReset(
            to: reportedAt, locale: language.locale,
            calendar: Calendar(identifier: .gregorian), timeZone: timeZone
        ) else {
            return StatusAccessibilityString.localized(usesOAuth && source != .statusline
                ? "claude.oauth.queryTime.unavailable" : "claude.sourceTime.unavailable", language: language, bundle: .main)
        }
        let key = source == .oauth ? "claude.oauth.queryTime %@"
            : source == .statusline ? "claude.localReportTime %@" : "claude.sourceTime %@"
        return StatusAccessibilityString.localized(
            key,
            arguments: [timestamp], language: language, bundle: .main
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
    var sourceDetails: [String] = []

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
                    .help(Text(refreshLabel)).accessibilityLabel(Text(refreshLabel))
                    .accessibilityIdentifier(provider == .claude ? "claude-refresh" : "provider-codex-refresh")
            }

            if windows.isEmpty {
                Text(emptyText).font(.callout).foregroundStyle(.secondary)
                    .lineLimit(isTerminal || compact ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(provider.rawValue + "-quota-empty")
            } else if isTerminal {
                VStack(spacing: 11) {
                    ForEach(windows.sorted { $0.kind.sortOrder < $1.kind.sortOrder }) { window in
                        QuotaWindowRowContent(
                            window: window, palette: palette, reset: resetPresentation(window),
                            accessibilityIdentifier: windowIdentifier(window), language: language
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

            if provider == .claude && windows.isEmpty {
                if explainsPassiveSource && !isTerminal {
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
                    .lineLimit(isTerminal || compact ? 1 : nil)
                    .help(Text(verbatim: sourceTimeText))
                    .accessibilityIdentifier(provider.rawValue + "-source-time")
                ForEach(Array(sourceDetails.enumerated()), id: \.offset) { index, detail in
                    Text(verbatim: detail).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(provider.rawValue + "-source-detail-" + String(index))
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
}
