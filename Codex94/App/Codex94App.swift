import SwiftUI

struct Codex94App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
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
