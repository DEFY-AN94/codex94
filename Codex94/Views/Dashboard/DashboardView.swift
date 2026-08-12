import AppKit
import SwiftUI

struct DashboardView: View {
    enum Section: String, CaseIterable, Identifiable {
        case connection
        case display
        case startup
        case diagnostics

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            switch self {
            case .connection: "dashboard.connection"
            case .display: "dashboard.display"
            case .startup: "dashboard.startup"
            case .diagnostics: "dashboard.diagnostics"
            }
        }

        var systemImage: String {
            switch self {
            case .connection: "point.3.connected.trianglepath.dotted"
            case .display: "rectangle.on.rectangle"
            case .startup: "power.circle"
            case .diagnostics: "stethoscope"
            }
        }
    }

    @ObservedObject var store: AppStore
    let chooseCodex: () -> Void
    let clearManualCodex: () -> Void
    let quit: () -> Void

    @State private var selection: Section? = .connection

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.titleKey, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("Codex94")
            .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 280)
        } detail: {
            Group {
                switch selection ?? .connection {
                case .connection:
                    ConnectionSettingsView(
                        store: store,
                        chooseCodex: chooseCodex,
                        clearManualCodex: clearManualCodex
                    )
                case .display:
                    DisplaySettingsView(store: store)
                case .startup:
                    StartupSettingsView(store: store)
                case .diagnostics:
                    DiagnosticsView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.refresh(trigger: .manual)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("command.refresh")
                .disabled(store.isRefreshing || !store.preferences.hasChosenIdentityMode)

                Button(action: quit) {
                    Image(systemName: "power")
                }
                .help("command.quit")
            }
        }
        .codex94Environment(store.preferences)
    }
}

private struct ConnectionSettingsView: View {
    @ObservedObject var store: AppStore
    let chooseCodex: () -> Void
    let clearManualCodex: () -> Void

    var body: some View {
        SettingsPage(title: "dashboard.connection") {
            SettingsRow("connection.status") {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(store.connectionState.localizedTitle)
                    if store.isRefreshing { ProgressView().controlSize(.small) }
                }
            }

            SettingsDivider()

            SettingsRow("connection.codexPath") {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.locatedCodex?.executableURL.path ?? "—")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                    HStack(spacing: 10) {
                        Text(store.locatedCodex?.version ?? "—")
                            .foregroundStyle(.secondary)
                        Button("connection.choose", action: chooseCodex)
                        if store.preferences.manualCodexPath != nil {
                            Button("connection.useAutomatic", action: clearManualCodex)
                        }
                    }
                    .controlSize(.small)
                }
            }

            SettingsDivider()

            SettingsRow("connection.identity") {
                Picker("connection.identity", selection: Binding(
                    get: { store.preferences.identityMode },
                    set: { store.setIdentityMode($0) }
                )) {
                    ForEach(IdentityMode.allCases) { mode in
                        Text(mode.localizedKey).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }

            if store.preferences.identityMode == .quotaAndAccount {
                SettingsDivider()
                SettingsRow("connection.account") {
                    Text(store.snapshot?.account?.email ?? "—")
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var statusColor: Color {
        switch store.connectionState {
        case .connected: .green
        case .stale: .orange
        case .unavailable: .red
        case .refreshing: .blue
        case .idle: .secondary
        }
    }
}

private struct DisplaySettingsView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        SettingsPage(title: "dashboard.display") {
            SettingsRow("display.label") {
                Picker("display.label", selection: Binding(
                    get: { store.preferences.displayMode },
                    set: { store.setDisplayMode($0) }
                )) {
                    ForEach(store.availableDisplayModes) { mode in
                        Text(mode.localizedKey).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }

            SettingsDivider()

            SettingsRow("settings.refreshInterval") {
                Picker("settings.refreshInterval", selection: Binding(
                    get: { store.preferences.refreshInterval },
                    set: { store.setRefreshInterval($0) }
                )) {
                    ForEach(RefreshInterval.allCases) { interval in
                        (Text(verbatim: "\(interval.rawValue) ") + Text("settings.minutesShort"))
                            .tag(interval)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }

            SettingsDivider()

            SettingsRow("settings.theme") {
                Picker("settings.theme", selection: Binding(
                    get: { store.preferences.theme },
                    set: { store.preferences.theme = $0 }
                )) {
                    ForEach(ThemePreference.allCases) { theme in
                        Text(theme.localizedKey).tag(theme)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            SettingsDivider()

            SettingsRow("settings.language") {
                Picker("settings.language", selection: Binding(
                    get: { store.preferences.language },
                    set: { store.preferences.language = $0 }
                )) {
                    ForEach(LanguagePreference.allCases) { language in
                        Text(language.localizedKey).tag(language)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }
        }
    }
}

private struct StartupSettingsView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        SettingsPage(title: "dashboard.startup") {
            SettingsRow("startup.login") {
                VStack(alignment: .leading, spacing: 7) {
                    Toggle("startup.login", isOn: Binding(
                        get: { store.launchAtLogin.isEnabled },
                        set: { store.launchAtLogin.setEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!store.launchAtLogin.isStableInstall)

                    if !store.launchAtLogin.isStableInstall {
                        Text("startup.installRequired")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if store.launchAtLogin.requiresApproval {
                        Text("startup.approvalRequired")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }
}

private struct DiagnosticsView: View {
    @ObservedObject var store: AppStore
    @State private var copied = false

    var body: some View {
        SettingsPage(title: "dashboard.diagnostics") {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    Text(store.diagnostics().text)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(14)
                }
                .background(.quaternary.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary)
                }
                .frame(minHeight: 320)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.diagnostics().text, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        copied = false
                    }
                } label: {
                    Label(copied ? "diagnostics.copied" : "diagnostics.copy", systemImage: "doc.on.doc")
                }
            }
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    init(title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 28, weight: .semibold))
                    .padding(.bottom, 28)
                content
            }
            .frame(maxWidth: 1_080, alignment: .leading)
            .padding(.horizontal, 48)
            .padding(.vertical, 42)
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            Text(title)
                .fontWeight(.medium)
                .frame(width: 190, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 18)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.leading, 218)
    }
}

private extension ConnectionState {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .idle: "status.idle"
        case .refreshing: "status.refreshing"
        case .connected: "status.connected"
        case .stale: "status.staleShort"
        case .unavailable: "status.unavailable"
        }
    }
}
