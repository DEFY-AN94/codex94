import AppKit
import SwiftUI

struct DisplaySettingsView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var windowState: DashboardWindowState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SettingsPage(title: "dashboard.display") {
            SettingsRow("display.label") {
                MenuBarQuotaPicker(store: store)
                    .frame(maxWidth: 360)
            }

            SettingsDivider()

            SettingsRow("display.layout") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("display.layout", selection: Binding(
                        get: { store.preferences.menuBarLayout },
                        set: { store.preferences.menuBarLayout = $0 }
                    )) {
                        ForEach(MenuBarLayout.allCases) { layout in
                            Text(layout.localizedKey).tag(layout)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 300)
                    .accessibilityIdentifier("menu-bar-layout")
                    Text("display.layout.restartNotice")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsDivider()

            SettingsRow("display.colors") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(StatusAccentRole.allCases) { role in
                        ColorPicker(
                            role.localizedKey,
                            selection: colorBinding(for: role),
                            supportsOpacity: false
                        )
                        .frame(maxWidth: 360)
                        .accessibilityLabel(Text(role.localizedKey))
                        .accessibilityIdentifier("status-accent-" + role.rawValue)
                    }
                    Text("display.colors.help")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("display.colors.restoreDefaults") {
                        store.preferences.restoreDefaultColors()
                    }
                    .disabled(store.preferences.statusAccentOverrides.isEmpty)
                    .accessibilityIdentifier("restore-default-colors")
                }
            }

            SettingsDivider()

            SettingsRow("display.dashboardWindowSize") {
                Picker("display.dashboardWindowSize", selection: Binding(
                    get: { windowState.selectedPreset },
                    set: { preset in
                        if let preset {
                            windowState.request(preset)
                        }
                    }
                )) {
                    ForEach(DashboardWindowSizePreset.allCases) { preset in
                        (Text(preset.localizedKey) + Text(verbatim: " · \(preset.dimensions)"))
                            .tag(Optional(preset))
                    }
                    if windowState.selectedPreset == nil {
                        (Text("display.windowSize.custom")
                            + Text(verbatim: " · \(windowState.currentDimensions)"))
                            .tag(DashboardWindowSizePreset?.none)
                    }
                }
                .labelsHidden()
                .frame(width: 260)
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

    private var palette: Codex94Palette {
        .resolve(
            store.preferences.theme,
            scheme: colorScheme,
            overrides: store.preferences.statusAccentOverrides
        )
    }

    private func colorBinding(for role: StatusAccentRole) -> Binding<Color> {
        Binding(
            get: { palette.accentColor(for: role) },
            set: { color in
                guard let value = StatusAccentColor(platformColor: NSColor(color)) else { return }
                store.preferences.statusAccentOverrides[role] = value
            }
        )
    }
}
