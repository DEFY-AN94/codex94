import AppKit
import Combine
import ServiceManagement
import SwiftUI
import XCTest
@testable import Codex94

final class LaunchAtLoginControllerTests: XCTestCase {
    @MainActor
    func testRefreshPublishesSystemApprovalChanges() {
        var status: SMAppService.Status = .requiresApproval
        let controller = LaunchAtLoginController(
            readStatus: { status }, register: { XCTFail("Read-only refresh must not register") },
            unregister: { XCTFail("Read-only refresh must not unregister") }, stableInstall: { true }
        )
        XCTAssertFalse(controller.isEnabled)
        XCTAssertTrue(controller.requiresApproval)
        var observedEnabled: [Bool] = []
        let observation = controller.$isEnabled.sink { observedEnabled.append($0) }
        defer { observation.cancel() }

        status = .enabled
        controller.refresh()

        XCTAssertTrue(controller.isEnabled)
        XCTAssertFalse(controller.requiresApproval)
        XCTAssertEqual(observedEnabled, [false, true])
        status = .notRegistered
        controller.refresh()
        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(controller.requiresApproval)
    }

    @MainActor
    func testRegisterAndUnregisterReadBackStatus() {
        var status: SMAppService.Status = .notRegistered
        var registrations = 0
        var removals = 0
        let controller = LaunchAtLoginController(
            readStatus: { status },
            register: { registrations += 1; status = .requiresApproval },
            unregister: { removals += 1; status = .notRegistered },
            stableInstall: { true }
        )
        controller.setEnabled(true)
        XCTAssertEqual(registrations, 1)
        XCTAssertTrue(controller.requiresApproval)
        XCTAssertFalse(controller.isEnabled, "Pending approval is not enabled")
        controller.setEnabled(false)
        XCTAssertEqual(removals, 1)
        XCTAssertFalse(controller.requiresApproval)
        XCTAssertNil(controller.lastIssue)
    }

    @MainActor
    func testOperationFailuresAreSanitizedAndNextSuccessClearsIssue() {
        struct SyntheticError: Error {}
        var shouldFail = true
        var status: SMAppService.Status = .notRegistered
        let controller = LaunchAtLoginController(
            readStatus: { status },
            register: { if shouldFail { throw SyntheticError() }; status = .enabled },
            unregister: { if shouldFail { throw SyntheticError() }; status = .notRegistered },
            stableInstall: { true }
        )
        controller.setEnabled(true)
        XCTAssertEqual(controller.lastIssue, "service_management_error")
        XCTAssertFalse(controller.isEnabled)
        shouldFail = false
        controller.setEnabled(true)
        XCTAssertNil(controller.lastIssue)
        XCTAssertTrue(controller.isEnabled)
        shouldFail = true
        controller.setEnabled(false)
        XCTAssertEqual(controller.lastIssue, "service_management_error")
        XCTAssertTrue(controller.isEnabled, "A failed unregister must retain actual enabled status")
    }

    @MainActor
    func testUnstableInstallBlocksBothMutations() {
        let controller = LaunchAtLoginController(
            readStatus: { .notRegistered }, register: { XCTFail("Unstable app must not register") },
            unregister: { XCTFail("Unstable app must not unregister") }, stableInstall: { false }
        )
        for enabled in [true, false] {
            controller.setEnabled(enabled)
            XCTAssertEqual(controller.lastIssue, "stable_install_required")
            XCTAssertFalse(controller.isEnabled)
        }
    }

    @MainActor
    func testFailurePageFitsBothLanguagesWithFakeService() {
        struct SyntheticError: Error {}
        let controller = LaunchAtLoginController(
            readStatus: { .notRegistered }, register: { throw SyntheticError() },
            unregister: { XCTFail("No unregister expected") }, stableInstall: { true }
        )
        controller.setEnabled(true)
        for language in [LanguagePreference.english, .simplifiedChinese] {
            let host = NSHostingController(rootView: StartupSettingsView(controller: controller)
                .environment(\.locale, language.locale))
            let size = host.sizeThatFits(in: NSSize(width: 640, height: 600))
            XCTAssertTrue(size.height.isFinite)
            XCTAssertGreaterThan(size.height, 0)
            XCTAssertLessThanOrEqual(size.height, 600)
            let text = StatusAccessibilityString.localized(
                "startup.operationFailed", language: language, bundle: .main
            )
            XCTAssertNotEqual(text, "startup.operationFailed")
            XCTAssertFalse(text.contains("SyntheticError"))
        }
    }

    func testAcceptsSystemApplicationsInstall() throws {
        let fixture = try makeStableInstallFixture()

        XCTAssertTrue(
            LaunchAtLoginController.isStableInstall(
                bundleURL: fixture.systemBundleURL,
                homeDirectoryURL: fixture.homeDirectoryURL,
                systemApplicationsDirectoryURL: fixture.systemApplicationsDirectoryURL
            )
        )
    }

    func testAcceptsHomeApplicationsInstall() throws {
        let fixture = try makeStableInstallFixture()

        XCTAssertTrue(
            LaunchAtLoginController.isStableInstall(
                bundleURL: fixture.homeBundleURL,
                homeDirectoryURL: fixture.homeDirectoryURL,
                systemApplicationsDirectoryURL: fixture.systemApplicationsDirectoryURL
            )
        )
    }

    func testAcceptsEquivalentStandardizedPaths() throws {
        let fixture = try makeStableInstallFixture()
        let systemUtilitiesDirectoryURL = fixture.systemApplicationsDirectoryURL
            .appendingPathComponent("Utilities", isDirectory: true)
        let homeNestedDirectoryURL = fixture.homeDirectoryURL
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(
            at: systemUtilitiesDirectoryURL,
            withIntermediateDirectories: false
        )
        try FileManager.default.createDirectory(
            at: homeNestedDirectoryURL,
            withIntermediateDirectories: false
        )

        XCTAssertTrue(
            LaunchAtLoginController.isStableInstall(
                bundleURL: URL(
                    fileURLWithPath: systemUtilitiesDirectoryURL.path
                        + "/.././Codex94.app",
                    isDirectory: true
                ),
                homeDirectoryURL: fixture.homeDirectoryURL,
                systemApplicationsDirectoryURL: fixture.systemApplicationsDirectoryURL
            )
        )
        XCTAssertTrue(
            LaunchAtLoginController.isStableInstall(
                bundleURL: URL(
                    fileURLWithPath: homeNestedDirectoryURL.path
                        + "/../../Applications/Codex94.app",
                    isDirectory: true
                ),
                homeDirectoryURL: fixture.homeDirectoryURL,
                systemApplicationsDirectoryURL: fixture.systemApplicationsDirectoryURL
            )
        )
    }

    func testAcceptsHomeApplicationsRootSymlink() throws {
        let directory = try makeTemporaryDirectory()
        let homeDirectory = directory.appendingPathComponent("home", isDirectory: true)
        let resolvedApplicationsDirectory = directory.appendingPathComponent(
            "resolved-home-applications",
            isDirectory: true
        )
        let bundleURL = resolvedApplicationsDirectory.appendingPathComponent(
            "Codex94.app",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: homeDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: bundleURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: homeDirectory.appendingPathComponent("Applications", isDirectory: true),
            withDestinationURL: resolvedApplicationsDirectory
        )

        XCTAssertTrue(
            LaunchAtLoginController.isStableInstall(
                bundleURL: homeDirectory
                    .appendingPathComponent("Applications", isDirectory: true)
                    .appendingPathComponent("Codex94.app", isDirectory: true),
                homeDirectoryURL: homeDirectory,
                systemApplicationsDirectoryURL: directory.appendingPathComponent(
                    "system-applications",
                    isDirectory: true
                )
            )
        )
    }

    func testAcceptsSystemApplicationsRootSymlink() throws {
        let directory = try makeTemporaryDirectory()
        let systemApplicationsDirectory = directory.appendingPathComponent(
            "system-applications-link",
            isDirectory: true
        )
        let resolvedApplicationsDirectory = directory.appendingPathComponent(
            "resolved-system-applications",
            isDirectory: true
        )
        let bundleURL = resolvedApplicationsDirectory.appendingPathComponent(
            "Codex94.app",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: bundleURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: systemApplicationsDirectory,
            withDestinationURL: resolvedApplicationsDirectory
        )

        XCTAssertTrue(
            LaunchAtLoginController.isStableInstall(
                bundleURL: systemApplicationsDirectory.appendingPathComponent(
                    "Codex94.app",
                    isDirectory: true
                ),
                homeDirectoryURL: directory.appendingPathComponent("home", isDirectory: true),
                systemApplicationsDirectoryURL: systemApplicationsDirectory
            )
        )
    }

    func testRejectsHomeApplicationsLeafSymlinksToDownloadsAndTemporaryDirectories() throws {
        let directory = try makeTemporaryDirectory()
        let unstableBundleURLs = [
            directory
                .appendingPathComponent("Downloads", isDirectory: true)
                .appendingPathComponent("Codex94.app", isDirectory: true),
            directory
                .appendingPathComponent("Temporary", isDirectory: true)
                .appendingPathComponent("Codex94.app", isDirectory: true)
        ]
        for (index, unstableBundleURL) in unstableBundleURLs.enumerated() {
            let homeDirectory = directory.appendingPathComponent(
                "home-\(index)",
                isDirectory: true
            )
            let applicationsDirectory = homeDirectory.appendingPathComponent(
                "Applications",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: applicationsDirectory,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: unstableBundleURL,
                withIntermediateDirectories: true
            )
            let bundleSymlinkURL = applicationsDirectory.appendingPathComponent(
                "Codex94.app",
                isDirectory: true
            )
            try FileManager.default.createSymbolicLink(
                at: bundleSymlinkURL,
                withDestinationURL: unstableBundleURL
            )

            XCTAssertFalse(
                LaunchAtLoginController.isStableInstall(
                    bundleURL: bundleSymlinkURL,
                    homeDirectoryURL: homeDirectory,
                    systemApplicationsDirectoryURL: directory.appendingPathComponent(
                        "system-applications",
                        isDirectory: true
                    )
                )
            )
        }
    }

    func testRejectsSystemApplicationsLeafSymlinkToVolumes() throws {
        let directory = try makeTemporaryDirectory()
        let systemApplicationsDirectory = directory.appendingPathComponent(
            "system-applications",
            isDirectory: true
        )
        let unstableBundleURL = directory
            .appendingPathComponent("Volumes", isDirectory: true)
            .appendingPathComponent("Codex94.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: systemApplicationsDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: unstableBundleURL,
            withIntermediateDirectories: true
        )
        let bundleSymlinkURL = systemApplicationsDirectory.appendingPathComponent(
            "Codex94.app",
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(
            at: bundleSymlinkURL,
            withDestinationURL: unstableBundleURL
        )

        XCTAssertFalse(
            LaunchAtLoginController.isStableInstall(
                bundleURL: bundleSymlinkURL,
                homeDirectoryURL: directory.appendingPathComponent("home", isDirectory: true),
                systemApplicationsDirectoryURL: systemApplicationsDirectory
            )
        )
    }

    func testRejectsUnstableAndApproximateLocations() {
        let rejectedPaths = [
            "/Volumes/Codex94 0.2.0/Codex94.app",
            "/Users/example/Downloads/Codex94.app",
            "/Users/example/Desktop/Codex94.app",
            "/private/tmp/Codex94.app",
            "/private/tmp/AppTranslocation/UUID/d/Codex94.app",
            "/Users/another-person/Applications/Codex94.app",
            "/Applications Backup/Codex94.app",
            "/Applications/Codex94.app-copy",
            "/Users/example/Applications Backup/Codex94.app",
            "/Users/example/Applications/Codex94.app-copy"
        ]

        for path in rejectedPaths {
            XCTAssertFalse(isStableInstall(bundlePath: path), "Unexpectedly accepted \(path)")
        }
    }

    private func isStableInstall(bundlePath: String) -> Bool {
        LaunchAtLoginController.isStableInstall(
            bundleURL: URL(fileURLWithPath: bundlePath, isDirectory: true),
            homeDirectoryURL: URL(
                fileURLWithPath: "/Users/example",
                isDirectory: true
            ),
            systemApplicationsDirectoryURL: URL(
                fileURLWithPath: "/Applications",
                isDirectory: true
            )
        )
    }

    private func makeStableInstallFixture() throws -> (
        homeDirectoryURL: URL,
        systemApplicationsDirectoryURL: URL,
        homeBundleURL: URL,
        systemBundleURL: URL
    ) {
        let directory = try makeTemporaryDirectory()
        let homeDirectoryURL = directory.appendingPathComponent("home", isDirectory: true)
        let homeBundleURL = homeDirectoryURL
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("Codex94.app", isDirectory: true)
        let systemApplicationsDirectoryURL = directory.appendingPathComponent(
            "system-applications",
            isDirectory: true
        )
        let systemBundleURL = systemApplicationsDirectoryURL.appendingPathComponent(
            "Codex94.app",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: homeBundleURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: systemBundleURL,
            withIntermediateDirectories: true
        )
        return (
            homeDirectoryURL,
            systemApplicationsDirectoryURL,
            homeBundleURL,
            systemBundleURL
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Codex94LaunchAtLoginTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
