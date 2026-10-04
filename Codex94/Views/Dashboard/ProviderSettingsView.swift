import SwiftUI

struct ProviderSettingsView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        SettingsPage(title: "dashboard.providers") {
            SettingsRow("providers.monitoring") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("providers.monitorCodex", isOn: monitoring(.codex))
                        .accessibilityIdentifier("provider-codex-enabled")
                    Toggle("providers.monitorClaude", isOn: monitoring(.claude))
                        .accessibilityIdentifier("provider-claude-enabled")
                    Text("providers.monitoring.help")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            SettingsDivider()
            SettingsRow("providers.menuBar") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("providers.menuBar", selection: Binding(
                        get: { store.preferences.menuBarServiceMode },
                        set: { store.preferences.menuBarServiceMode = $0 }
                    )) {
                        Text("providers.menuBar.single").tag(MenuBarServiceMode.single)
                        Text("providers.menuBar.compactBoth").tag(MenuBarServiceMode.compactBoth)
                        Text("providers.menuBar.both").tag(MenuBarServiceMode.both)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 440)
                    .accessibilityIdentifier("provider-menu-bar-mode")
                    Text("providers.menuBar.help")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if store.preferences.menuBarServiceMode == .compactBoth {
                        Text("providers.menuBar.compactBoth.help")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            SettingsDivider()
            SettingsRow("providers.primary") {
                providerPicker(
                    selection: Binding(
                        get: { store.preferences.resolvedPrimaryProvider ?? store.preferences.primaryProvider },
                        set: { store.preferences.primaryProvider = $0 }
                    ), identifier: "provider-primary"
                )
            }
            SettingsDivider()
            SettingsRow("providers.floating") {
                providerPicker(
                    selection: Binding(
                        get: { store.preferences.resolvedFloatingProvider ?? store.preferences.floatingProvider },
                        set: { store.preferences.floatingProvider = $0 }
                    ), identifier: "provider-floating"
                )
            }
            SettingsDivider()
            SettingsRow("claude.sources.title") {
                ClaudeSourcesSummaryView(store: store.claudeStore, language: store.preferences.language)
            }
            SettingsDivider()
            SettingsRow("claude.passive.title") {
                ClaudeStatuslineSetupView(store: store.claudeStore)
            }
            SettingsDivider()
            SettingsRow("claude.cliUsage.title") {
                ClaudeCLIUsageSettingsView(store: store)
            }
            if store.preferences.claudeMonitoringEnabled && store.preferences.claudeCLIUsageEnabled {
                SettingsDivider()
                SettingsRow("claude.refreshInterval") {
                    Picker("claude.refreshInterval", selection: Binding(
                        get: { store.preferences.claudeRefreshInterval },
                        set: { store.setClaudeRefreshInterval($0) }
                    )) {
                        ForEach(RefreshInterval.allCases) { interval in
                            (Text(verbatim: "\(interval.rawValue) ") + Text("settings.minutesShort"))
                                .tag(interval)
                        }
                    }
                    .labelsHidden().frame(width: 180)
                    .accessibilityIdentifier("claude-refresh-interval")
                }
            }
            if store.preferences.claudeMonitoringEnabled {
                SettingsDivider()
                SettingsRow("claude.menuBarQuota") {
                    if store.preferences.usesDualWindowMenuBarSelection {
                        MenuBarBucketPicker(store: store, provider: .claude)
                    } else {
                        MenuBarQuotaPicker(store: store, provider: .claude)
                    }
                }
                SettingsDivider()
                NotificationSettingsView(store: store, provider: .claude)
            }
        }
        .accessibilityIdentifier("provider-settings-page")
    }

    private func monitoring(_ provider: QuotaProviderID) -> Binding<Bool> {
        Binding(
            get: { store.preferences.isMonitoringEnabled(for: provider) },
            set: { store.setMonitoringEnabled($0, for: provider) }
        )
    }

    @ViewBuilder
    private func providerPicker(selection: Binding<QuotaProviderID>, identifier: String) -> some View {
        if store.preferences.enabledProviders.isEmpty {
            Text("providers.noneEnabled").foregroundStyle(.secondary)
        } else {
            Picker("providers.service", selection: selection) {
                ForEach(store.preferences.enabledProviders) { provider in
                    Text(verbatim: provider.displayName).tag(provider)
                }
            }
            .labelsHidden().frame(maxWidth: 260)
            .accessibilityIdentifier(identifier)
        }
    }
}

/// Read-only explanation of the three Claude sources and which one is shown.
/// Rendering this view never reads a file or starts a request.
struct ClaudeSourcesSummaryView: View {
    @ObservedObject var store: ClaudeQuotaStore
    let language: LanguagePreference

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("claude.sources.help")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: currentSourceText)
                .font(.caption)
                .accessibilityIdentifier("claude-sources-current")
            if store.isEnabled {
                // The cache is examined only while monitoring is on.
                Text(verbatim: localCacheText)
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("claude-sources-local-cache")
            }
        }
    }

    private func localized(_ key: String, arguments: [CVarArg] = []) -> String {
        StatusAccessibilityString.localized(key, arguments: arguments, language: language, bundle: .main)
    }

    private var currentSourceText: String {
        guard store.isEnabled else { return localized("claude.monitoring.off") }
        let name = store.source.map { localized($0.localizationKey) } ?? localized("claude.sources.none")
        return localized("claude.sources.current %@", arguments: [name])
    }

    private var localCacheText: String {
        localized("claude.localCache.status." + store.localCacheState.rawValue)
    }
}

/// The optional CLI reader: an automatic switch, its quota warning, and one
/// explicit read that works regardless of the switch.
struct ClaudeCLIUsageSettingsView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("claude.cliUsage.enable", isOn: Binding(
                get: { store.preferences.claudeCLIUsageEnabled },
                set: { store.setClaudeCLIUsageEnabled($0) }
            ))
            .accessibilityIdentifier("claude-cli-usage-enabled")
            Text("claude.cliUsage.help")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("claude.cliUsage.warning", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("claude-cli-usage-warning")
            HStack(spacing: 10) {
                Button("claude.cliUsage.readOnce") { store.readClaudeOnceWithCLI() }
                    .disabled(!store.preferences.claudeMonitoringEnabled || !store.claudeStore.canReadOnceWithCLI)
                    .accessibilityIdentifier("claude-cli-read-once")
                if store.claudeStore.isRefreshing {
                    ProgressView().controlSize(.small)
                    Text("claude.refreshing").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("claude.cliUsage.readOnce.help")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let issue = store.claudeStore.lastCLIReadIssue {
                Text(issue == .noData ? LocalizedStringKey("claude.cliUsage.readOnce.noData") : issue.localizedKey)
                    .font(.caption).foregroundStyle(issue == .noData ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("claude-cli-read-once-issue")
            } else if let readAt = store.claudeStore.lastCLIReadAt,
                      let time = QuotaFormatting.automaticRefreshTime(at: readAt) {
                Text(verbatim: StatusAccessibilityString.localized(
                    "claude.cliUsage.lastRead %@", arguments: [time],
                    language: store.preferences.language, bundle: .main
                ))
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("claude-cli-last-read")
            }
        }
    }
}

struct ProvidersDisabledView: View {
    let openSettings: () -> Void
    var titleKey: LocalizedStringKey = "providers.noneEnabled"

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "pause.circle").font(.system(size: 28)).foregroundStyle(.secondary)
            Text(titleKey).font(.headline)
            Button("providers.openSettings", action: openSettings)
                .accessibilityIdentifier("providers-open-settings")
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("providers-disabled")
    }
}
