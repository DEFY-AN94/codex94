import SwiftUI

/// One explicit action shared by Services and the menu footer. It never changes
/// the regular CLI preference, and the store owns admission and process lifetime.
struct ClaudeReadOnceActionView: View {
    @ObservedObject var store: AppStore
    var compact = false

    var body: some View {
        ClaudeReadOnceActionContent(
            canRead: store.preferences.claudeMonitoringEnabled && store.claudeStore.canReadOnceWithCLI,
            isRefreshing: store.claudeStore.isRefreshing,
            isRetiringCLI: store.claudeStore.isRetiringCLI,
            regularCLIEnabled: store.preferences.claudeCLIUsageEnabled,
            issue: store.claudeStore.lastCLIReadIssue,
            lastReadAt: store.claudeStore.lastCLIReadAt,
            language: store.preferences.language,
            readOnce: { store.readClaudeOnceWithCLI() }, compact: compact
        )
    }
}

/// Explicit values allow busy, stopping and result states to render without
/// starting Claude Code or reading account files.
struct ClaudeReadOnceActionContent: View {
    let canRead: Bool
    let isRefreshing: Bool
    let isRetiringCLI: Bool
    let regularCLIEnabled: Bool
    let issue: ClaudeQuotaIssue?
    let lastReadAt: Date?
    let language: LanguagePreference
    let readOnce: () -> Void
    var compact = false
    var timeZone: TimeZone = .autoupdatingCurrent

    var isBusy: Bool { isRefreshing || isRetiringCLI }
    var canStartRead: Bool { canRead && !isBusy }
    var progressKey: String? {
        if isRetiringCLI { return "claude.cliUsage.stopping" }
        return isRefreshing ? "claude.refreshing" : nil
    }
    var resultIssueKey: String? {
        guard !isBusy, let issue else { return nil }
        return issue == .noData ? "claude.cliUsage.readOnce.noData" : issue.localizationKey
    }
    var lastReadText: String? {
        guard !isBusy, issue == nil, let lastReadAt,
              let time = QuotaFormatting.automaticRefreshTime(at: lastReadAt, timeZone: timeZone) else { return nil }
        return StatusAccessibilityString.localized(
            "claude.cliUsage.lastRead %@", arguments: [time], language: language, bundle: .main
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            HStack(spacing: 10) {
                Button(action: readOnce) {
                    Label(compact ? LocalizedStringKey("claude.cliUsage.readOnce.menu") : "claude.cliUsage.readOnce",
                          systemImage: "terminal")
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(!canStartRead)
                .help(Text("claude.cliUsage.readOnce.help"))
                .accessibilityIdentifier("claude-cli-read-once")
                if let progressKey {
                    ProgressView().controlSize(.small).accessibilityHidden(true)
                    Text(LocalizedStringKey(progressKey))
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("claude-cli-read-once-progress")
                }
                Spacer(minLength: 0)
            }
            Label(compact ? LocalizedStringKey("claude.cliUsage.readOnce.warning") : "claude.cliUsage.readOnce.help",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("claude-cli-read-once-warning")
            if regularCLIEnabled {
                Text("claude.cliUsage.backgroundEnabled")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("claude-cli-background-enabled")
            }
            if let resultIssueKey {
                Text(LocalizedStringKey(resultIssueKey))
                    .font(.caption).foregroundStyle(issue == .noData ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("claude-cli-read-once-issue")
            } else if let lastReadText {
                Text(verbatim: lastReadText)
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("claude-cli-last-read")
            }
        }
    }
}
