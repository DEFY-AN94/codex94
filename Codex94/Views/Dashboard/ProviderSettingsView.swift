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
            SettingsRow("claude.sourceMode.title") {
                Picker("claude.sourceMode.title", selection: sourceModeBinding) {
                    Text("claude.sourceMode.oauthPreferred").tag(ClaudeQuotaSourceMode.oauthPreferred)
                    Text("claude.sourceMode.statuslineOnly").tag(ClaudeQuotaSourceMode.statuslineOnly)
                    Text("claude.sourceMode.legacyCLI").tag(ClaudeQuotaSourceMode.legacyCLI)
                }
                .labelsHidden().frame(maxWidth: 360)
                .accessibilityIdentifier("claude-source-mode")
            }
            if store.claudeStore.sourceMode == .oauthPreferred {
                SettingsDivider()
                SettingsRow("claude.oauth.connection") { ClaudeOAuthConnectionNotice() }
                SettingsDivider()
                SettingsRow("claude.oauth.fallback.title") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("claude.oauth.fallback.enabled", isOn: fallbackBinding)
                            .accessibilityIdentifier("claude-statusline-fallback-enabled")
                        Text("claude.oauth.fallback.help")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if store.claudeStore.sourceMode == .legacyCLI {
                SettingsDivider()
                SettingsRow("claude.cliUsage.title") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("claude.cliUsage.help")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Label("claude.cliUsage.warning", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("claude-cli-usage-warning")
                    }
                }
            }
            SettingsDivider()
            SettingsRow("claude.passive.title") {
                ClaudeStatuslineSetupView(store: store.claudeStore)
            }
            if store.preferences.claudeMonitoringEnabled && store.claudeStore.sourceMode != .statuslineOnly {
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
                if store.claudeStore.sourceMode == .oauthPreferred {
                    Text("claude.oauth.unverifiedNotifications")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("claude-oauth-notification-limits")
                }
            }
        }
        .accessibilityIdentifier("provider-settings-page")
    }

    var sourceModeBinding: Binding<ClaudeQuotaSourceMode> {
        Binding(get: { store.claudeStore.sourceMode }, set: { store.setClaudeSourceMode($0) })
    }

    var fallbackBinding: Binding<Bool> {
        Binding(get: { store.claudeStore.allowsStatuslineFallback }, set: { store.setClaudeStatuslineFallbackEnabled($0) })
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

/// A future permitted connection UI belongs here. Until then this is only
/// information, with no fake login action, credential read or invalidation.
struct ClaudeOAuthConnectionNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("claude.oauth.notReady", systemImage: "info.circle")
                .font(.callout)
                .accessibilityIdentifier("claude-oauth-not-ready")
            Text("claude.oauth.integrationHelp")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
