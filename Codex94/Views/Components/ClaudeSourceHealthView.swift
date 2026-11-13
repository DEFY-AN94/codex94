import SwiftUI

/// A read-only description of accepted data and independent source checks.
/// Actions are supplied by the owner; constructing or rendering this view does
/// not reread files, adopt a report, or start a CLI session.
struct ClaudeSourceHealthView: View {
    let presentation: ClaudeSourceHealthPresentation
    let language: LanguagePreference
    let now: Date
    var timeZone: TimeZone = .autoupdatingCurrent
    var rereadLocalReports: (() -> Void)? = nil
    var reviewStatusline: (() -> Void)? = nil
    var reviewCLIOptions: (() -> Void)? = nil
    var openDiagnostics: (() -> Void)? = nil

    var dataStateKey: String {
        switch presentation.dataState {
        case .disabled: "claude.health.data.disabled"
        case .current: "claude.health.data.current"
        case .cached: "claude.health.data.cached"
        case .history: "claude.health.data.history"
        case .unavailable: "claude.health.data.unavailable"
        }
    }

    var currentSourceText: String {
        guard presentation.dataState != .disabled else { return localized("claude.monitoring.off") }
        let source = presentation.source.map { localized($0.localizationKey) }
            ?? localized("claude.sources.none")
        return localized("claude.sources.current %@", arguments: [source])
    }

    var reportTimeText: String? {
        guard let reportedAt = presentation.reportedAt else { return nil }
        return ClaudeQuotaHistoryFormatting.sourceTime(
            source: presentation.source, reportedAt: reportedAt, language: language, timeZone: timeZone
        )
    }

    var reportAgeText: String? {
        presentation.reportedAt.map {
            ClaudeQuotaHistoryFormatting.relativeAge(since: $0, now: now, language: language)
        }
    }

    var operationKey: String? {
        switch presentation.operationState {
        case .idle: nil
        case .reading: "claude.health.operation.reading"
        case .retiring: "claude.health.operation.retiring"
        }
    }

    var statuslineKey: String {
        switch presentation.statuslineSetupState {
        case .notInstalled: "claude.health.statusline.notInstalled"
        case .installed: "claude.health.statusline.installed"
        case .conflict: "claude.setup.conflict"
        case .differentConfiguration: "claude.setup.differentConfiguration"
        }
    }

    var cacheHelpKey: String? {
        switch presentation.localCacheState {
        case .absent: "claude.health.cache.absentHelp"
        case .unreadable: "claude.health.cache.unreadableHelp"
        case .invalid: "claude.health.cache.invalidHelp"
        case .valid, nil: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Label(localized(dataStateKey), systemImage: dataSymbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(dataColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("claude-health-data-state")
                Text(verbatim: currentSourceText)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("claude-sources-current")
                if let reportTimeText {
                    Text(verbatim: reportTimeText)
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("claude-health-report-time")
                }
                if let reportAgeText {
                    Text(verbatim: reportAgeText)
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("claude-health-report-age")
                }
            }

            if presentation.dataState != .disabled {
                sourceChecks
                if let operationKey {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).accessibilityHidden(true)
                        Text(verbatim: localized(operationKey)).font(.caption)
                    }
                    .accessibilityIdentifier("claude-health-operation")
                }
                if let issue = presentation.lastReadIssue {
                    Text(verbatim: localized("claude.health.lastAttemptIssue %@",
                                             arguments: [localized(issue.localizationKey)]))
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("claude-health-cli-issue")
                }
                if let record = presentation.lastDiagnostic {
                    ClaudeCLIDiagnosticSummaryView(record: record, language: language,
                                                   timeZone: timeZone, compact: true)
                }
                actions
                Text(verbatim: localized("claude.passive.reread.help"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("claude-local-reread-help")
            } else {
                Text(verbatim: localized("claude.health.disabledHelp"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("claude-source-health")
    }

    private var sourceChecks: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let cache = presentation.localCacheState {
                Text(verbatim: localized("claude.localCache.status." + cache.rawValue))
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("claude-sources-local-cache")
                if let cacheHelpKey {
                    Text(verbatim: localized(cacheHelpKey))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("claude-health-cache-help")
                }
            }
            Text(verbatim: localized(statuslineKey))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("claude-health-statusline")
            if presentation.needsSourceConfirmation {
                Text(verbatim: localized("claude.health.pendingSource"))
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("claude-health-pending-source")
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { rereadButton; diagnosticsButton }
                VStack(alignment: .leading, spacing: 8) { rereadButton; diagnosticsButton }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { statuslineButton; cliOptionsButton }
                VStack(alignment: .leading, spacing: 8) { statuslineButton; cliOptionsButton }
            }
        }
    }

    @ViewBuilder private var rereadButton: some View {
        if let rereadLocalReports, presentation.actions.contains(.rereadLocalReports) {
            Button(action: rereadLocalReports) {
                Label(localized("claude.health.rereadLocal"), systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .help(Text(verbatim: localized("claude.passive.reread.help")))
            .accessibilityIdentifier("claude-reread-local")
        }
    }

    @ViewBuilder private var diagnosticsButton: some View {
        if let openDiagnostics, presentation.actions.contains(.openDiagnostics) {
            Button(localized("claude.health.openDiagnostics"), action: openDiagnostics)
                .controlSize(.small)
                .accessibilityIdentifier("claude-health-open-diagnostics")
        }
    }

    @ViewBuilder private var statuslineButton: some View {
        if let reviewStatusline, presentation.actions.contains(.reviewStatusline) {
            Button(localized("claude.health.reviewStatusline"), action: reviewStatusline)
                .controlSize(.small)
                .accessibilityIdentifier("claude-health-review-statusline")
        }
    }

    @ViewBuilder private var cliOptionsButton: some View {
        if let reviewCLIOptions, presentation.actions.contains(.readOnceWithCLI) {
            Button(localized("claude.health.reviewCLI"), action: reviewCLIOptions)
                .controlSize(.small)
                .accessibilityIdentifier("claude-health-review-cli")
        }
    }

    private var dataSymbol: String {
        switch presentation.dataState {
        case .current: "checkmark.circle"
        case .cached, .history: "clock"
        case .disabled: "pause.circle"
        case .unavailable: "questionmark.circle"
        }
    }

    private var dataColor: Color {
        switch presentation.dataState {
        case .current: .primary
        case .cached, .history: .orange
        case .disabled, .unavailable: .secondary
        }
    }

    private func localized(_ key: String, arguments: [CVarArg] = []) -> String {
        StatusAccessibilityString.localized(key, arguments: arguments, language: language, bundle: .main)
    }
}

/// A completed attempt, not a claim about the current source or live progress.
struct ClaudeCLIDiagnosticSummaryView: View {
    let record: ClaudeCLIReadDiagnosticRecord
    let language: LanguagePreference
    var timeZone: TimeZone = .autoupdatingCurrent
    var compact = false
    var identifier = "claude-health-diagnostic"

    var phaseText: String { localized("claude.health.phase." + record.diagnostic.phase.rawValue) }
    var resultText: String { localized("claude.health.result." + record.diagnostic.result.rawValue) }
    var completedAtText: String {
        QuotaFormatting.absoluteReset(to: record.completedAt, locale: language.locale,
                                      calendar: Calendar(identifier: .gregorian), timeZone: timeZone)
            ?? localized("claude.sourceTime.unavailable")
    }
    var durationText: String {
        localized("claude.health.duration %@", arguments: [String(record.diagnostic.durationMilliseconds)])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: localized("claude.health.lastAttempt %@", arguments: [resultText]))
                .font(compact ? .caption.weight(.medium) : .callout.weight(.semibold))
                .accessibilityIdentifier(identifier + "-result")
            Text(verbatim: phaseText + " · " + durationText)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier + "-phase")
            if !compact {
                Text(verbatim: localized("claude.health.completedAt %@", arguments: [completedAtText]))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(identifier + "-completed-at")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func localized(_ key: String, arguments: [CVarArg] = []) -> String {
        StatusAccessibilityString.localized(key, arguments: arguments, language: language, bundle: .main)
    }
}
