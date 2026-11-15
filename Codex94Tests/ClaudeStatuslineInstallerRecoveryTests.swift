import Foundation
import XCTest
@testable import Codex94

final class ClaudeStatuslineInstallerRecoveryTests: XCTestCase {
    func testConflictRecoveryPreservesCurrentSettingsAndBackupsThenWrapsCurrentCommand() throws {
        let fixture = try fixture()
        let oldMarker = fixture.root.appendingPathComponent("old-command-ran")
        let newMarker = fixture.root.appendingPathComponent("new-command-ran")
        let oldCommand = "touch '\(oldMarker.path)'"
        let newCommand = "touch '\(newMarker.path)'"
        try writeSettings(["statusLine": ["type": "command", "command": oldCommand, "padding": 2],
                           "unrelated": ["kept": true]], fixture: fixture)
        XCTAssertEqual(fixture.installer.setupState, .notInstalled)
        try fixture.installer.install(fixture.installer.previewInstall())
        XCTAssertEqual(fixture.installer.setupState, .installed)
        let originalBackups = try backups(in: fixture)
        XCTAssertEqual(originalBackups.count, 1)

        let edited: [String: Any] = ["statusLine": ["type": "command", "command": newCommand, "padding": 7],
                                     "unrelated": ["kept": true], "addedAfterInstall": "retained"]
        try writeSettings(edited, fixture: fixture)
        let editedBytes = try Data(contentsOf: fixture.installer.settingsURL)
        XCTAssertEqual(fixture.installer.setupState, .conflict)
        XCTAssertFalse(fixture.installer.isInstalled)
        XCTAssertThrowsError(try fixture.installer.previewInstall())
        XCTAssertThrowsError(try fixture.installer.remove())

        try fixture.installer.forgetConflictingInstallation()
        XCTAssertEqual(fixture.installer.setupState, .notInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.installer.manifestURL.path))
        XCTAssertEqual(try Data(contentsOf: fixture.installer.settingsURL), editedBytes)
        XCTAssertEqual(try backups(in: fixture), originalBackups)
        let preview = try fixture.installer.previewInstall()
        XCTAssertEqual(preview.originalCommand, newCommand)
        XCTAssertTrue(preview.preservesExistingStatusline)
        try fixture.installer.install(preview)
        XCTAssertEqual(fixture.installer.setupState, .installed)
        let manifest = try JSONDecoder().decode(ClaudeStatuslineInstaller.Manifest.self,
                                                from: Data(contentsOf: fixture.installer.manifestURL))
        XCTAssertEqual(manifest.originalCommand, newCommand)
        let installed = try settings(fixture)
        XCTAssertEqual((installed["statusLine"] as? [String: Any])?["padding"] as? Int, 7)
        XCTAssertEqual(installed["addedAfterInstall"] as? String, "retained")
        XCTAssertEqual((installed["unrelated"] as? [String: Bool])?["kept"], true)
        for (name, data) in originalBackups { XCTAssertEqual(try backups(in: fixture)[name], data) }
        XCTAssertEqual(try backups(in: fixture).count, 2)
        try fixture.installer.remove()
        XCTAssertEqual((try settings(fixture)["statusLine"] as? [String: Any])?["command"] as? String, newCommand)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldMarker.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newMarker.path), "Recovery and preview never execute either command")
    }

    func testRecoveryAfterUserDeletesSettingsDoesNotRecreateThem() throws {
        let fixture = try fixture()
        try fixture.installer.install(fixture.installer.previewInstall())
        let originalBackups = try backups(in: fixture)
        try FileManager.default.removeItem(at: fixture.installer.settingsURL)
        XCTAssertEqual(fixture.installer.setupState, .conflict)
        try fixture.installer.forgetConflictingInstallation()
        XCTAssertEqual(fixture.installer.setupState, .notInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.installer.settingsURL.path))
        XCTAssertEqual(try backups(in: fixture), originalBackups)
        XCTAssertNil(try fixture.installer.previewInstall().originalCommand)
    }

    func testRecoveryRefusesInstalledOrStillReferencedBridge() throws {
        let fixture = try fixture()
        let preview = try fixture.installer.previewInstall()
        try fixture.installer.install(preview)
        let manifestBytes = try Data(contentsOf: fixture.installer.manifestURL)
        for command in [preview.bridgeCommand, "printf prefix; " + preview.bridgeCommand] {
            try writeSettings(["statusLine": ["type": "command", "command": command, "padding": 9]], fixture: fixture)
            let settingsBytes = try Data(contentsOf: fixture.installer.settingsURL)
            XCTAssertEqual(fixture.installer.setupState, .conflict)
            XCTAssertThrowsError(try fixture.installer.forgetConflictingInstallation()) {
                XCTAssertEqual($0 as? ClaudeQuotaIssue, .configurationConflict)
            }
            XCTAssertEqual(try Data(contentsOf: fixture.installer.manifestURL), manifestBytes)
            XCTAssertEqual(try Data(contentsOf: fixture.installer.settingsURL), settingsBytes)
        }
        try writeSettings(["statusLine": ["type": "command", "command": preview.bridgeCommand]], fixture: fixture)
        XCTAssertEqual(fixture.installer.setupState, .installed)
        XCTAssertThrowsError(try fixture.installer.forgetConflictingInstallation())
        XCTAssertEqual(try Data(contentsOf: fixture.installer.manifestURL), manifestBytes)
    }

    func testRecoveryRefusesForeignOrMalformedManifestWithoutDeletingIt() throws {
        for mutation in ["settingsPath", "cachePath", "installedCommand", "installedStatusline", "backupPath", "originalCommand"] {
            let fixture = try fixture()
            try fixture.installer.install(fixture.installer.previewInstall())
            try writeSettings(["statusLine": ["type": "command", "command": "printf user-change"]], fixture: fixture)
            var manifest = try json(fixture.installer.manifestURL)
            if mutation == "installedStatusline" {
                manifest[mutation] = try JSONSerialization.data(withJSONObject: ["type": "command", "command": "printf foreign"])
                    .base64EncodedString()
            } else { manifest[mutation] = "foreign-record" }
            let bytes = try JSONSerialization.data(withJSONObject: manifest)
            try bytes.write(to: fixture.installer.manifestURL)
            XCTAssertEqual(fixture.installer.setupState, .conflict)
            XCTAssertThrowsError(try fixture.installer.forgetConflictingInstallation(), mutation)
            XCTAssertEqual(try Data(contentsOf: fixture.installer.manifestURL), bytes, mutation)
            XCTAssertEqual((try settings(fixture)["statusLine"] as? [String: String])?["command"], "printf user-change")
        }
        let fixture = try fixture()
        try FileManager.default.createDirectory(at: fixture.installer.supportDirectory, withIntermediateDirectories: true)
        let bytes = Data("not a manifest".utf8)
        try bytes.write(to: fixture.installer.manifestURL)
        XCTAssertEqual(fixture.installer.setupState, .conflict)
        XCTAssertThrowsError(try fixture.installer.forgetConflictingInstallation())
        XCTAssertEqual(try Data(contentsOf: fixture.installer.manifestURL), bytes)
    }

    func testRecoveryRequiresOriginalBackupAndPreservesMalformedCurrentSettings() throws {
        let fixture = try fixture()
        try writeSettings(["statusLine": ["type": "command", "command": "printf original"]], fixture: fixture)
        try fixture.installer.install(fixture.installer.previewInstall())
        let manifestBytes = try Data(contentsOf: fixture.installer.manifestURL)
        let manifest = try JSONDecoder().decode(ClaudeStatuslineInstaller.Manifest.self, from: manifestBytes)
        let backupURL = URL(fileURLWithPath: manifest.backupPath)
        let backupBytes = try Data(contentsOf: backupURL)
        try writeSettings(["statusLine": ["type": "command", "command": "printf user-change"]], fixture: fixture)
        var backup = try json(backupURL)
        backup["statusLine"] = ["type": "command", "command": "printf unrelated"]
        try JSONSerialization.data(withJSONObject: backup).write(to: backupURL)
        XCTAssertThrowsError(try fixture.installer.forgetConflictingInstallation())
        XCTAssertEqual(try Data(contentsOf: fixture.installer.manifestURL), manifestBytes)
        try backupBytes.write(to: backupURL)
        let invalidSettings = Data("unfinished settings edit".utf8)
        try invalidSettings.write(to: fixture.installer.settingsURL)
        XCTAssertEqual(fixture.installer.setupState, .conflict)
        XCTAssertThrowsError(try fixture.installer.forgetConflictingInstallation())
        XCTAssertEqual(try Data(contentsOf: fixture.installer.settingsURL), invalidSettings)
        XCTAssertEqual(try Data(contentsOf: fixture.installer.manifestURL), manifestBytes)
        XCTAssertEqual(try Data(contentsOf: backupURL), backupBytes)
    }

    func testChangingConfigurationDoesNotRedirectRemovalOrAcceptTheOldReport() throws {
        let fixture = try fixture()
        let preview = try fixture.installer.previewInstall()
        try fixture.installer.install(preview)
        let oldSettings = try Data(contentsOf: fixture.installer.settingsURL)
        let manifest = try Data(contentsOf: fixture.installer.manifestURL)
        let oldBackups = try backups(in: fixture)
        let newDirectory = fixture.root.appendingPathComponent("other profile")
        let other = ClaudeStatuslineInstaller(cache: fixture.installer.cache,
            executableURL: fixture.installer.executableURL, supportDirectory: fixture.installer.supportDirectory,
            environment: ["CLAUDE_CONFIG_DIR": newDirectory.path], homeDirectory: fixture.root, stableInstall: true)
        XCTAssertEqual(other.setupState, .differentConfiguration)
        XCTAssertEqual(other.reportEligibility(installationID: preview.installationID), .blocked)
        XCTAssertEqual(other.reportEligibility(installationID: nil), .blocked)
        XCTAssertThrowsError(try other.remove())
        XCTAssertThrowsError(try other.forgetConflictingInstallation())
        XCTAssertThrowsError(try other.previewInstall())
        XCTAssertEqual(try Data(contentsOf: fixture.installer.settingsURL), oldSettings)
        XCTAssertEqual(try Data(contentsOf: fixture.installer.manifestURL), manifest)
        XCTAssertEqual(try backups(in: fixture), oldBackups)
        XCTAssertFalse(FileManager.default.fileExists(atPath: other.settingsURL.path))
        // The recovery instruction remains actionable in the original configuration.
        try fixture.installer.remove()
        let newPreview = try other.previewInstall()
        try other.install(newPreview)
        XCTAssertEqual(other.setupState, .installed)
        XCTAssertEqual(other.reportEligibility(installationID: newPreview.installationID), .allowed)
        XCTAssertEqual(other.reportEligibility(installationID: preview.installationID), .blocked)
        XCTAssertEqual(other.reportEligibility(installationID: nil), .blocked)
    }

    func testLegacyDefaultInstallationRemainsRemovableAndAutomaticallyEligible() throws {
        let fixture = try fixture()
        let installer = ClaudeStatuslineInstaller(cache: fixture.installer.cache,
            executableURL: fixture.installer.executableURL, supportDirectory: fixture.installer.supportDirectory,
            environment: [:], homeDirectory: fixture.root, stableInstall: true)
        let preview = try installer.previewInstall()
        try installer.install(preview)
        var manifest = try json(installer.manifestURL)
        let legacyCommand = String(preview.bridgeCommand.dropLast(preview.installationID.count + 3))
        let line = try JSONSerialization.data(withJSONObject: ["type": "command", "command": legacyCommand], options: [.sortedKeys, .prettyPrinted])
        manifest.removeValue(forKey: "installationID")
        manifest["installedCommand"] = legacyCommand
        manifest["installedStatusline"] = line.base64EncodedString()
        try JSONSerialization.data(withJSONObject: manifest).write(to: installer.manifestURL)
        try JSONSerialization.data(withJSONObject: ["statusLine": ["type": "command", "command": legacyCommand]])
            .write(to: installer.settingsURL)
        XCTAssertEqual(installer.setupState, .installed)
        XCTAssertEqual(installer.reportEligibility(installationID: nil), .allowed)
        XCTAssertEqual(installer.reportEligibility(installationID: UUID().uuidString), .blocked)
        try installer.remove()
        XCTAssertEqual(installer.setupState, .notInstalled)
        XCTAssertEqual(installer.reportEligibility(installationID: nil), .confirmationRequired)
        XCTAssertEqual(installer.reportEligibility(installationID: preview.installationID), .blocked)
    }

    func testUnstableAppLocationRefusesPreviewAndLockedInstallWithoutWritingAnything() throws {
        let fixture = try fixture()
        let unstable = twin(of: fixture.installer, stableInstall: false)
        try writeSettings(["statusLine": ["type": "command", "command": "printf original"], "unrelated": true],
                          fixture: fixture)
        let bytes = try Data(contentsOf: fixture.installer.settingsURL)
        XCTAssertEqual(unstable.setupState, .notInstalled)
        XCTAssertThrowsError(try unstable.previewInstall()) {
            XCTAssertEqual($0 as? ClaudeQuotaIssue, .stableInstallRequired)
        }
        // A preview minted by a stable App cannot bypass the locked install's own guard.
        let preview = try fixture.installer.previewInstall()
        XCTAssertThrowsError(try unstable.install(preview)) {
            XCTAssertEqual($0 as? ClaudeQuotaIssue, .stableInstallRequired)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.installer.settingsURL), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.installer.manifestURL.path))
        XCTAssertTrue(((try? backups(in: fixture)) ?? [:]).isEmpty, "A refused installation leaves no backup behind")
        XCTAssertEqual(unstable.setupState, .notInstalled)
        // The refusal is about the App location only: the same preview installs when stable.
        try fixture.installer.install(preview)
        XCTAssertEqual(fixture.installer.setupState, .installed)
        XCTAssertEqual((try settings(fixture)["statusLine"] as? [String: Any])?["command"] as? String,
                       preview.bridgeCommand)
    }

    func testUnstableAppLocationStillReportsRemovesAndRecoversAnExistingConnection() throws {
        let fixture = try fixture()
        let unstable = twin(of: fixture.installer, stableInstall: false)
        try writeSettings(["statusLine": ["type": "command", "command": "printf original", "padding": 2]],
                          fixture: fixture)
        let preview = try fixture.installer.previewInstall()
        try fixture.installer.install(preview)
        XCTAssertEqual(unstable.setupState, .installed)
        XCTAssertTrue(unstable.isInstalled)
        XCTAssertEqual(unstable.reportEligibility(installationID: preview.installationID), .allowed)
        XCTAssertEqual(unstable.bridgeHealth(), .waiting)
        try unstable.remove()
        XCTAssertEqual(unstable.setupState, .notInstalled)
        let restored = try XCTUnwrap(settings(fixture)["statusLine"] as? [String: Any])
        XCTAssertEqual(restored["command"] as? String, "printf original")
        XCTAssertEqual(restored["padding"] as? Int, 2)

        try fixture.installer.install(fixture.installer.previewInstall())
        try writeSettings(["statusLine": ["type": "command", "command": "printf user-change"]], fixture: fixture)
        let edited = try Data(contentsOf: fixture.installer.settingsURL)
        XCTAssertEqual(unstable.setupState, .conflict)
        try unstable.forgetConflictingInstallation()
        XCTAssertEqual(unstable.setupState, .notInstalled)
        XCTAssertEqual(try Data(contentsOf: fixture.installer.settingsURL), edited)
        XCTAssertThrowsError(try unstable.previewInstall()) {
            XCTAssertEqual($0 as? ClaudeQuotaIssue, .stableInstallRequired)
        }
    }

    func testAppAtAnotherExecutablePathRemovesAnIntactConnectionButCannotForgetAConflict() throws {
        // Pins what a moved App can and cannot do. State and removal compare the
        // settings with the manifest only; recovery additionally requires the
        // manifest's command to be the one THIS executable path would install.
        let fixture = try fixture()
        let moved = try relocated(fixture.installer, in: fixture.root)
        XCTAssertNotEqual(moved.executableURL.path, fixture.installer.executableURL.path)
        try writeSettings(["statusLine": ["type": "command", "command": "printf original", "padding": 2],
                           "unrelated": true], fixture: fixture)
        try fixture.installer.install(fixture.installer.previewInstall())
        XCTAssertEqual(moved.setupState, .installed)
        try moved.remove()
        XCTAssertEqual(moved.setupState, .notInstalled)
        XCTAssertEqual(fixture.installer.setupState, .notInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.installer.manifestURL.path))
        let restored = try settings(fixture)
        XCTAssertEqual(restored.keys.sorted(), ["statusLine", "unrelated"])
        XCTAssertEqual(restored["unrelated"] as? Bool, true)
        let restoredLine = try XCTUnwrap(restored["statusLine"] as? [String: Any])
        XCTAssertEqual(restoredLine.keys.sorted(), ["command", "padding", "type"])
        XCTAssertEqual(restoredLine["command"] as? String, "printf original")
        XCTAssertEqual(restoredLine["padding"] as? Int, 2)

        try fixture.installer.install(fixture.installer.previewInstall())
        try writeSettings(["statusLine": ["type": "command", "command": "printf user-change"]], fixture: fixture)
        let edited = try Data(contentsOf: fixture.installer.settingsURL)
        let manifest = try Data(contentsOf: fixture.installer.manifestURL)
        XCTAssertEqual(moved.setupState, .conflict)
        XCTAssertThrowsError(try moved.forgetConflictingInstallation()) {
            XCTAssertEqual($0 as? ClaudeQuotaIssue, .configurationConflict)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.installer.settingsURL), edited)
        XCTAssertEqual(try Data(contentsOf: fixture.installer.manifestURL), manifest)
        XCTAssertEqual(moved.setupState, .conflict)

        // The App at the path that installed the connection can still forget it.
        XCTAssertEqual(fixture.installer.setupState, .conflict)
        try fixture.installer.forgetConflictingInstallation()
        XCTAssertEqual(fixture.installer.setupState, .notInstalled)
        XCTAssertEqual(moved.setupState, .notInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.installer.manifestURL.path))
        XCTAssertEqual(try Data(contentsOf: fixture.installer.settingsURL), edited)
    }

    func testProductionDefaultTakesTheStableInstallDecisionFromTheRunningBundle() throws {
        let fixture = try fixture()
        let defaulted = twin(of: fixture.installer, stableInstall: nil)
        let expected = LaunchAtLoginController.isCurrentBundleStableInstall()
        XCTAssertEqual(defaulted.isStableInstall, expected)
        XCTAssertEqual(expected, LaunchAtLoginController.isStableInstall(
            bundleURL: Bundle.main.bundleURL, homeDirectoryURL: FileManager.default.homeDirectoryForCurrentUser,
            systemApplicationsDirectoryURL: URL(fileURLWithPath: "/Applications", isDirectory: true)
        ))
        guard !expected else { throw XCTSkip("The test host unexpectedly runs from an Applications folder") }
        // The hosted test App runs from a build directory: without an injected
        // decision even fully synthetic paths must be refused.
        XCTAssertThrowsError(try defaulted.previewInstall()) {
            XCTAssertEqual($0 as? ClaudeQuotaIssue, .stableInstallRequired)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.installer.settingsURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.installer.manifestURL.path))
    }

    func testInstallAndRemoveWriteTheSettingsFileWithoutEscapedSlashes() throws {
        let fixture = try fixture()
        let original = Data(("{\"hooks\":{\"url\":\"https://example.invalid/a/b\"},\"statusLine\":"
            + "{\"command\":\"~/.claude/statusline.sh\",\"padding\":2,\"type\":\"command\"}}").utf8)
        try original.write(to: fixture.installer.settingsURL)
        let originalObject = try settings(fixture)
        let preview = try fixture.installer.previewInstall()
        try fixture.installer.install(preview)
        XCTAssertFalse(try settingsText(fixture).contains(#"\/"#),
                       "The user's settings file must not gain escaped slashes")
        XCTAssertTrue(try settingsText(fixture).contains("https://example.invalid/a/b"))
        var expected = originalObject
        let installedLine: [String: Any] = ["type": "command", "command": preview.bridgeCommand, "padding": 2]
        expected["statusLine"] = installedLine
        XCTAssertEqual(try settings(fixture) as NSDictionary, expected as NSDictionary)
        XCTAssertEqual(fixture.installer.setupState, .installed)
        // The persisted comparison form stays byte-for-byte what earlier releases wrote.
        let manifest = try JSONDecoder().decode(ClaudeStatuslineInstaller.Manifest.self,
                                                from: Data(contentsOf: fixture.installer.manifestURL))
        XCTAssertEqual(manifest.installedStatusline, try legacyEncoded(installedLine))
        XCTAssertEqual(manifest.previousStatusline, try legacyEncoded(try XCTUnwrap(originalObject["statusLine"])))
        XCTAssertTrue(String(decoding: manifest.installedStatusline, as: UTF8.self).contains(#"\/"#))
        let backup = try json(URL(fileURLWithPath: manifest.backupPath))
        XCTAssertEqual(backup["statusLine"] as? NSDictionary, originalObject["statusLine"] as? NSDictionary)

        try fixture.installer.remove()
        XCTAssertFalse(try settingsText(fixture).contains(#"\/"#))
        XCTAssertEqual(try settings(fixture) as NSDictionary, originalObject as NSDictionary)
        XCTAssertEqual((try settings(fixture)["statusLine"] as? [String: Any])?["command"] as? String,
                       "~/.claude/statusline.sh")
        XCTAssertEqual(fixture.installer.setupState, .notInstalled)
    }

    func testInstallationWrittenWithEscapedSlashesStaysInstalledRemovableAndRecoverable() throws {
        let previous: [String: Any] = ["type": "command", "command": "~/.claude/statusline.sh", "padding": 2]
        let extra: [String: Any] = ["hooks": ["url": "https://example.invalid/a/b"]]
        let fixture = try fixture()
        let installationID = try seedEscapedFormatInstallation(fixture, previous: previous, extra: extra)
        XCTAssertTrue(try settingsText(fixture).contains(#"https:\/\/example.invalid\/a\/b"#),
                      "The fixture must reproduce the earlier on-disk format")
        XCTAssertEqual(fixture.installer.setupState, .installed)
        XCTAssertEqual(fixture.installer.reportEligibility(installationID: installationID), .allowed)
        XCTAssertEqual(fixture.installer.bridgeHealth(), .waiting)
        XCTAssertThrowsError(try fixture.installer.forgetConflictingInstallation(),
                             "An intact earlier installation is not a conflict")
        // The same value rewritten without escapes (by this release or the user) is still ours.
        let escaped = try Data(contentsOf: fixture.installer.settingsURL)
        try JSONSerialization.data(withJSONObject: try settings(fixture), options: [.withoutEscapingSlashes])
            .write(to: fixture.installer.settingsURL)
        XCTAssertEqual(fixture.installer.setupState, .installed)
        try escaped.write(to: fixture.installer.settingsURL)
        try fixture.installer.remove()
        XCTAssertEqual(fixture.installer.setupState, .notInstalled)
        var expected = extra
        expected["statusLine"] = previous
        XCTAssertEqual(try settings(fixture) as NSDictionary, expected as NSDictionary)
        XCTAssertFalse(try settingsText(fixture).contains(#"\/"#))

        let recovering = try self.fixture()
        _ = try seedEscapedFormatInstallation(recovering, previous: previous, extra: extra)
        try writeSettings(["statusLine": ["type": "command", "command": "printf user-change"]], fixture: recovering)
        let edited = try Data(contentsOf: recovering.installer.settingsURL)
        XCTAssertEqual(recovering.installer.setupState, .conflict)
        try recovering.installer.forgetConflictingInstallation()
        XCTAssertEqual(recovering.installer.setupState, .notInstalled)
        XCTAssertEqual(try Data(contentsOf: recovering.installer.settingsURL), edited)
    }

    func testConcurrentSettingsEditsAreStillDetectedAroundUnescapedWrites() throws {
        let fixture = try fixture()
        try Data(#"{"statusLine":{"type":"command","command":"~/.claude/statusline.sh"}}"#.utf8)
            .write(to: fixture.installer.settingsURL)
        let stale = try fixture.installer.previewInstall()
        let concurrent = Data(("{\"addedMeanwhile\":\"https://example.invalid/x\",\"statusLine\":"
            + "{\"type\":\"command\",\"command\":\"~/.claude/statusline.sh\"}}").utf8)
        try concurrent.write(to: fixture.installer.settingsURL)
        XCTAssertThrowsError(try fixture.installer.install(stale)) {
            XCTAssertEqual($0 as? ClaudeQuotaIssue, .configurationConflict)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.installer.settingsURL), concurrent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.installer.manifestURL.path))

        try fixture.installer.install(fixture.installer.previewInstall())
        XCTAssertEqual(fixture.installer.setupState, .installed)
        XCTAssertEqual(try settings(fixture)["addedMeanwhile"] as? String, "https://example.invalid/x")
        var edited = try settings(fixture)
        var line = try XCTUnwrap(edited["statusLine"] as? [String: Any])
        line["padding"] = 4
        edited["statusLine"] = line
        let editedBytes = try JSONSerialization.data(withJSONObject: edited,
                                                     options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
        try editedBytes.write(to: fixture.installer.settingsURL)
        XCTAssertEqual(fixture.installer.setupState, .conflict)
        XCTAssertThrowsError(try fixture.installer.remove()) {
            XCTAssertEqual($0 as? ClaudeQuotaIssue, .configurationConflict)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.installer.settingsURL), editedBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.installer.manifestURL.path))
    }

    private struct Fixture {
        let root: URL
        let installer: ClaudeStatuslineInstaller
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeRecoveryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("synthetic-app")
        try Data("#!/bin/sh\nexit 99\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let support = root.appendingPathComponent("support")
        let cache = ClaudeStatuslineCache(fileURL: support.appendingPathComponent("statusline-quota.json"))
        let installer = ClaudeStatuslineInstaller(settingsURL: root.appendingPathComponent("settings.json"),
            cache: cache, executableURL: executable, supportDirectory: support, stableInstall: true)
        return Fixture(root: root, installer: installer)
    }

    /// The same synthetic files AND the same executable path: only the injected
    /// stable-install decision varies. A different App location is modelled by
    /// relocated(_:in:), whose bridge command no longer matches the manifest.
    private func twin(of installer: ClaudeStatuslineInstaller, stableInstall: Bool?) -> ClaudeStatuslineInstaller {
        ClaudeStatuslineInstaller(settingsURL: installer.settingsURL, cache: installer.cache,
            executableURL: installer.executableURL, supportDirectory: installer.supportDirectory,
            stableInstall: stableInstall)
    }

    /// The same settings, cache and support files seen by an App whose
    /// executable really lives elsewhere, at an unstable location.
    private func relocated(_ installer: ClaudeStatuslineInstaller, in root: URL) throws -> ClaudeStatuslineInstaller {
        let executable = root.appendingPathComponent("relocated-synthetic-app")
        try Data("#!/bin/sh\nexit 99\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return ClaudeStatuslineInstaller(settingsURL: installer.settingsURL, cache: installer.cache,
            executableURL: executable, supportDirectory: installer.supportDirectory, stableInstall: false)
    }

    /// Canonical bytes exactly as every release so far produced and persisted them.
    private func legacyEncoded(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
    }

    /// Hand-built on-disk state of an earlier release: escaped slashes in the
    /// settings file and legacy canonical bytes in the manifest and backup.
    private func seedEscapedFormatInstallation(_ fixture: Fixture, previous: [String: Any],
                                               extra: [String: Any]) throws -> String {
        let installer = fixture.installer
        let installationID = UUID().uuidString
        let command = "'\(installer.executableURL.path)' \(ClaudeStatuslineBridge.argument) "
            + "'\(installer.manifestURL.path)' '\(installationID)'"
        var line = previous
        line["command"] = command
        try FileManager.default.createDirectory(at: installer.supportDirectory, withIntermediateDirectories: true)
        let backupURL = installer.supportDirectory.appendingPathComponent("settings-backup-\(UUID().uuidString).json")
        try legacyEncoded(["version": 1, "settingsDigest": String(repeating: "a", count: 64),
                           "hadStatusline": true, "statusLine": previous] as [String: Any]).write(to: backupURL)
        let manifest: [String: Any] = [
            "version": 1, "settingsPath": installer.settingsURL.path, "cachePath": installer.cache.fileURL.path,
            "installedCommand": command, "installedStatusline": try legacyEncoded(line).base64EncodedString(),
            "previousStatusline": try legacyEncoded(previous).base64EncodedString(),
            "originalCommand": try XCTUnwrap(previous["command"] as? String),
            "backupPath": backupURL.path, "installationID": installationID
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: installer.manifestURL)
        var settings = extra
        settings["statusLine"] = line
        try legacyEncoded(settings).write(to: installer.settingsURL)
        return installationID
    }

    private func settingsText(_ fixture: Fixture) throws -> String {
        try String(contentsOf: fixture.installer.settingsURL, encoding: .utf8)
    }

    private func writeSettings(_ value: [String: Any], fixture: Fixture) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: fixture.installer.settingsURL)
    }

    private func json(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func settings(_ fixture: Fixture) throws -> [String: Any] { try json(fixture.installer.settingsURL) }

    private func backups(in fixture: Fixture) throws -> [String: Data] {
        let files = try FileManager.default.contentsOfDirectory(at: fixture.installer.supportDirectory, includingPropertiesForKeys: nil)
        return try Dictionary(uniqueKeysWithValues: files.filter { $0.lastPathComponent.hasPrefix("settings-backup-") }
            .map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }
}
