import SwiftUI

struct Codex94App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            appDelegate.dashboardCommands
        }
    }
}

/// Replace SwiftUI's empty Settings route at application scope. The command
/// remains available while the menu-bar popover is closed and uses the same
/// Dashboard controller as the other navigation buttons.
@MainActor
struct DashboardSettingsCommands: Commands {
    @ObservedObject var preferences: PreferencesStore
    let openDashboard: () -> Void

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(action: openDashboard) {
                Text(verbatim: StatusAccessibilityString.localized(
                    "command.dashboard", language: preferences.language, bundle: .main
                ))
            }
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityIdentifier("settings-dashboard-command")
        }
    }
}

/// Claude invokes the same signed executable as a local statusline command.
/// Handle that bounded stdin operation before SwiftUI or application services
/// are initialized, so reporting quota never opens another menu bar app.
@main
enum Codex94Main {
    @MainActor
    static func main() {
        if let status = ClaudeStatuslineBridge.runIfRequested() {
            exit(status)
        }
        Codex94App.main()
    }
}
