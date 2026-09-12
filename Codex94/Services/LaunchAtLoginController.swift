import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var lastIssue: String?

    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    private let stableInstall: () -> Bool

    var isStableInstall: Bool {
        stableInstall()
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

    init(
        readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
        register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
        unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() },
        stableInstall: @escaping () -> Bool = {
            LaunchAtLoginController.isStableInstall(
                bundleURL: Bundle.main.bundleURL,
                homeDirectoryURL: FileManager.default.homeDirectoryForCurrentUser,
                systemApplicationsDirectoryURL: URL(fileURLWithPath: "/Applications", isDirectory: true)
            )
        }
    ) {
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
        self.stableInstall = stableInstall
        refresh()
    }

    func refresh() {
        switch readStatus() {
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
                try register()
            } else {
                try unregister()
            }
        } catch {
            lastIssue = "service_management_error"
        }
        refresh()
    }
}
