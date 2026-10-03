import XCTest
@testable import Codex94

final class ClaudeExecutableLocatorTests: XCTestCase {
    func testDesktopBuildHashLayoutIsFoundWithoutShellPATH() throws {
        let home = try directory()
        let binary = nativeRoot(home).appendingPathComponent("2.1.286/f2326db61802/claude.app/Contents/MacOS/claude")
        try executable(binary)
        let locator = ClaudeExecutableLocator(homeDirectory: home, environment: ["PATH": "/usr/bin:/bin"], standardExecutableURLs: [])
        XCTAssertEqual(try locator.locate(), binary.resolvingSymlinksInPath())
    }

    func testNumericVersionOrderAndLegacyLayoutFallback() throws {
        let home = try directory()
        let older = nativeRoot(home).appendingPathComponent("2.1.99/abcdef12/claude.app/Contents/MacOS/claude")
        let latestLegacy = nativeRoot(home).appendingPathComponent("2.1.286/claude.app/Contents/MacOS/claude")
        let missingBuild = nativeRoot(home).appendingPathComponent("2.1.286/f2326db61802")
        try executable(older)
        try executable(latestLegacy)
        try FileManager.default.createDirectory(at: missingBuild, withIntermediateDirectories: true)
        let locator = ClaudeExecutableLocator(homeDirectory: home, environment: [:], standardExecutableURLs: [])
        XCTAssertEqual(try locator.locate(), latestLegacy.resolvingSymlinksInPath())
        let latest = missingBuild.appendingPathComponent("claude.app/Contents/MacOS/claude")
        try executable(latest)
        XCTAssertEqual(try locator.locate(), latest.resolvingSymlinksInPath())
    }

    func testManualPathIsAuthoritativeAndStandardPATHSourcesRemainSupported() throws {
        let home = try directory()
        let standard = home.appendingPathComponent("standard/claude")
        let path = home.appendingPathComponent("path/claude")
        let manual = home.appendingPathComponent("manual/claude")
        for binary in [standard, path, manual] { try executable(binary) }
        let locator = ClaudeExecutableLocator(homeDirectory: home, environment: ["PATH": path.deletingLastPathComponent().path], standardExecutableURLs: [standard])
        XCTAssertEqual(try locator.locate(), standard.resolvingSymlinksInPath())
        XCTAssertEqual(try locator.locate(manualURL: manual), manual.resolvingSymlinksInPath())
        XCTAssertThrowsError(try locator.locate(manualURL: home.appendingPathComponent("missing")))
        try FileManager.default.removeItem(at: standard)
        XCTAssertEqual(try locator.locate(), path.resolvingSymlinksInPath())
    }

    func testDesktopDiscoveryRejectsUnsafeNamesSymlinkDirectoriesAndVMBuilds() throws {
        let home = try directory()
        let root = nativeRoot(home)
        for component in ["latest/abcdef12", "2.1.286\n/abcdef12", "2.1.287/not-a-build", "2.1.288/abc", "2.1.289/" + String(repeating: "a", count: 65)] {
            try executable(root.appendingPathComponent(component + "/claude.app/Contents/MacOS/claude"))
        }
        let foreign = home.appendingPathComponent("foreign")
        try executable(foreign.appendingPathComponent("claude.app/Contents/MacOS/claude"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("2.1.999"), withDestinationURL: foreign)
        let version = root.appendingPathComponent("2.1.290")
        try FileManager.default.createDirectory(at: version, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: version.appendingPathComponent("abcd1234"), withDestinationURL: foreign)
        let vm = home.appendingPathComponent("Library/Application Support/Claude/claude-code-vm/2.1.999/claude")
        try executable(vm)
        let locator = ClaudeExecutableLocator(homeDirectory: home, environment: ["PATH": vm.deletingLastPathComponent().path], standardExecutableURLs: [])
        XCTAssertThrowsError(try locator.locate())
        XCTAssertThrowsError(try locator.locate(manualURL: vm))
        XCTAssertFalse(locator.candidateURLs().contains { $0.path.contains("claude-code-vm") || $0.path.contains("foreign") })
    }

    func testDesktopDiscoveryBoundsVersionsAndBuildCandidates() throws {
        let home = try directory()
        for index in 0..<40 {
            let version = nativeRoot(home).appendingPathComponent("2.1.\(index)")
            for build in 0..<40 {
                try FileManager.default.createDirectory(at: version.appendingPathComponent(String(format: "%08x", build)), withIntermediateDirectories: true)
            }
        }
        let locator = ClaudeExecutableLocator(homeDirectory: home, environment: [:], standardExecutableURLs: [])
        let candidates = locator.candidateURLs()
        XCTAssertEqual(candidates.count, 32 * 33, "At most 32 hash candidates plus legacy for each of 32 versions")
        XCTAssertTrue(candidates.first?.path.contains("/2.1.39/") == true)
        XCTAssertFalse(candidates.contains { $0.path.contains("/2.1.7/") })
    }

    private func nativeRoot(_ home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Claude/claude-code")
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeLocatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func executable(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("synthetic executable marker; never run".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
}
