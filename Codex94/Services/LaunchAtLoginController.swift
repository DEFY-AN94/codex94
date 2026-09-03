import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var lastIssue: String?

    var isStableInstall: Bool {
        Self.isStableInstall(
            bundleURL: Bundle.main.bundleURL,
            homeDirectoryURL: FileManager.default.homeDirectoryForCurrentUser,
            systemApplicationsDirectoryURL: URL(
                fileURLWithPath: "/Applications",
                isDirectory: true
            )
        )
    }

    nonisolated static func isStableInstall(
        bundleURL: URL,
        homeDirectoryURL: URL,
        systemApplicationsDirectoryURL: URL
    ) -> Bool {
        let resolvedBundleURL = bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        let homeApplicationsDirectoryURL = homeDirectoryURL
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let resolvedSystemApplicationsDirectoryURL = systemApplicationsDirectoryURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let expectedBundleURLs = [
            homeApplicationsDirectoryURL.appendingPathComponent(
                "Codex94.app",
                isDirectory: true
            ),
            resolvedSystemApplicationsDirectoryURL.appendingPathComponent(
                "Codex94.app",
                isDirectory: true
            )
        ]

        return expectedBundleURLs.contains(resolvedBundleURL)
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
