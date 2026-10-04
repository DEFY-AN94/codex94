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
            SettingsRow("claude.passive.title") {
                ClaudeStatuslineSetupView(store: store.claudeStore)
            }
            SettingsDivider()
            SettingsRow("claude.cliUsage.title") {
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
                }
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
