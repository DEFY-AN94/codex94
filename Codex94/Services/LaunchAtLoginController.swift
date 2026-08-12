import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var lastIssue: String?

    var isStableInstall: Bool {
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Codex94.app")
            .standardizedFileURL
            .resolvingSymlinksInPath()
        return Bundle.main.bundleURL.standardizedFileURL.resolvingSymlinksInPath() == expected
    }

    init() {
        refresh()
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            requiresApproval = false
        case .requiresApproval:
            isEnabled = false
            requiresApproval = true
        default:
            isEnabled = false
            requiresApproval = false
        }
    }

    func setEnabled(_ enabled: Bool) {
        lastIssue = nil
        guard isStableInstall else {
            lastIssue = "stable_install_required"
            refresh()
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastIssue = "service_management_error"
        }
        refresh()
    }
}

