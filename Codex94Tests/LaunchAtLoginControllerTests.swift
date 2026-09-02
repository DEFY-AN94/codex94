import XCTest
@testable import Codex94

final class LaunchAtLoginControllerTests: XCTestCase {
    func testAcceptsSystemApplicationsInstall() {
        XCTAssertTrue(isStableInstall(bundlePath: "/Applications/Codex94.app"))
    }

    func testAcceptsHomeApplicationsInstall() {
        XCTAssertTrue(isStableInstall(bundlePath: "/Users/example/Applications/Codex94.app"))
    }

    func testAcceptsEquivalentStandardizedPaths() {
        XCTAssertTrue(
            isStableInstall(bundlePath: "/Applications/Utilities/.././Codex94.app")
        )
        XCTAssertTrue(
            isStableInstall(
                bundlePath: "/Users/example/Applications/Nested/../../Applications/Codex94.app"
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
