import Darwin
import XCTest
@testable import Codex94

final class ClaudeBridgeHealthTests: XCTestCase {
    private let first = Date(timeIntervalSince1970: 2_000_000_000)

    func testInstalledConnectionWithoutActivityIsWaitingAndNeverWritesOnRead() throws {
        let fixture = try fixture()
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first), .waiting)
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first.addingTimeInterval(60)), .waiting)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.health.fileURL.path))
        XCTAssertNil(try fixture.cache.load())
    }

    func testFirstReportWithoutQuotaRecordsActivityWithoutInventingQuota() throws {
        let fixture = try fixture()
        try capture(Data(#"{"session_id":"00000000-0000-0000-0000-000000000001","private":"DO_NOT_STORE"}"#.utf8), fixture: fixture)
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first), observed(.noQuotaFields, at: first))
        XCTAssertNil(try fixture.cache.load())
        let object = try json(fixture.health.fileURL)
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "installationID", "recordedAt", "outcome"])
        let bytes = try Data(contentsOf: fixture.health.fileURL)
        XCTAssertLessThanOrEqual(bytes.count, ClaudeBridgeHealthStore.maximumBytes)
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(text.contains("DO_NOT_STORE"))
        XCTAssertFalse(text.contains("session_id"))
        XCTAssertFalse(text.contains("00000000-0000-0000-0000-000000000001"))
        let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: fixture.health.fileURL.path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(mode.intValue & 0o777, 0o600)
    }

    func testDuplicateReportsRecordActivityWithoutRenewingQuotaObservation() throws {
        let fixture = try fixture()
        try capture(payload(), fixture: fixture)
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first), observed(.captured, at: first))
        try capture(payload(), fixture: fixture, at: first.addingTimeInterval(15))
        let report = try XCTUnwrap(fixture.cache.load())
        XCTAssertEqual(report.reportedAt, first)
        XCTAssertEqual(report.receivedAt, first.addingTimeInterval(15))
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first.addingTimeInterval(15)),
                       observed(.unchanged, at: first.addingTimeInterval(15)))
    }

    func testChangedOutcomeIsAlsoThrottledAcrossSeparateBridgeInvocations() throws {
        let fixture = try fixture()
        try capture(payload(), fixture: fixture)
        let original = try Data(contentsOf: fixture.health.fileURL)
        let originalInode = try inode(fixture.health.fileURL)
        try capture(Data("{}".utf8), fixture: fixture, at: first.addingTimeInterval(14.999))
        XCTAssertEqual(try Data(contentsOf: fixture.health.fileURL), original)
        XCTAssertEqual(try inode(fixture.health.fileURL), originalInode, "Throttled activity must not rewrite the sidecar")
        try capture(Data("{}".utf8), fixture: fixture, at: first.addingTimeInterval(15))
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first.addingTimeInterval(15)),
                       observed(.noQuotaFields, at: first.addingTimeInterval(15)))
        XCTAssertEqual(try fixture.cache.load()?.reportedAt, first)
    }

    func testNoQuotaAndExpiredInputPreservePreviouslyCapturedQuotaBytes() throws {
        let fixture = try fixture()
        try capture(payload(), fixture: fixture)
        let quota = try Data(contentsOf: fixture.cache.fileURL)
        try capture(Data(#"{"rate_limits":null}"#.utf8), fixture: fixture, at: first.addingTimeInterval(15))
        XCTAssertEqual(try Data(contentsOf: fixture.cache.fileURL), quota)
        try capture(payload(reset: 1_999_999_999), fixture: fixture, at: first.addingTimeInterval(30))
        XCTAssertEqual(try Data(contentsOf: fixture.cache.fileURL), quota)
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first.addingTimeInterval(30)),
                       observed(.expiredWindows, at: first.addingTimeInterval(30)))
    }

    func testMalformedInputHasBoundedDiagnosticButStillFailsCapture() throws {
        let fixture = try fixture()
        XCTAssertThrowsError(try capture(Data("not-json PRIVATE_INPUT".utf8), fixture: fixture)) {
            XCTAssertEqual($0 as? ClaudeQuotaIssue, .invalidData)
        }
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first), observed(.invalidInput, at: first))
        XCTAssertNil(try fixture.cache.load())
        XCTAssertFalse(String(decoding: try Data(contentsOf: fixture.health.fileURL), as: UTF8.self).contains("PRIVATE_INPUT"))
    }

    func testOversizedDirectInputRecordsNoPayloadAndNoQuota() throws {
        let fixture = try fixture()
        XCTAssertThrowsError(try capture(Data(repeating: 32, count: ClaudeStatuslineParser.maximumInputBytes + 1), fixture: fixture))
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first), observed(.invalidInput, at: first))
        XCTAssertNil(try fixture.cache.load())
    }

    func testQuotaCaptureFailureCanBeObservedWithoutReplacingQuota() throws {
        let fixture = try fixture()
        let invalidQuota = Data("invalid quota record".utf8)
        try ClaudeLocalFile.write(invalidQuota, to: fixture.cache.fileURL)
        XCTAssertThrowsError(try capture(payload(), fixture: fixture))
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first), observed(.captureFailed, at: first))
        XCTAssertEqual(try Data(contentsOf: fixture.cache.fileURL), invalidQuota)
    }

    func testDisabledBridgeWritesNeitherHealthNorQuota() throws {
        let fixture = try fixture()
        try ClaudeStatuslineBridge.capture(payload(), manifestURL: fixture.installer.manifestURL,
            enabled: false, now: first, installationID: fixture.installationID,
            environment: fixture.environment, homeDirectory: fixture.root)
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first), .waiting)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.health.fileURL.path))
        XCTAssertNil(try fixture.cache.load())
    }

    func testBusyInstallationLockCannotClaimThatBridgeDidNotRun() throws {
        let fixture = try fixture()
        try fixture.cache.withExclusiveAccess {
            XCTAssertThrowsError(try capture(Data("{}".utf8), fixture: fixture))
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.health.fileURL.path))
        }
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first), .waiting,
                       "No recorded activity is not proof of no invocation")
        try capture(Data("{}".utf8), fixture: fixture)
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first), observed(.noQuotaFields, at: first))
    }

    func testCorruptAndFutureSchemaHealthNeverBlockValidQuotaOrGetOverwritten() throws {
        for bytes in [Data("invalid-health".utf8),
                      Data(#"{"schemaVersion":2,"installationID":"00000000-0000-0000-0000-000000000001","recordedAt":1,"outcome":"captured"}"#.utf8)] {
            let fixture = try fixture()
            try ClaudeLocalFile.write(bytes, to: fixture.health.fileURL)
            try capture(payload(), fixture: fixture)
            XCTAssertNotNil(try fixture.cache.load())
            XCTAssertEqual(fixture.installer.bridgeHealth(at: first), .unreadable)
            XCTAssertEqual(try Data(contentsOf: fixture.health.fileURL), bytes)
            try fixture.installer.remove()
            XCTAssertEqual(try Data(contentsOf: fixture.health.fileURL), bytes,
                           "Uninstall must not delete an unrecognized record")
        }
    }

    func testOversizedAndUnknownFieldHealthAreRejected() throws {
        let fixture = try fixture()
        try capture(payload(), fixture: fixture)
        var object = try json(fixture.health.fileURL)
        object["unexpected"] = "not accepted"
        try JSONSerialization.data(withJSONObject: object).write(to: fixture.health.fileURL)
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first), .unreadable)
        try Data(repeating: 32, count: ClaudeBridgeHealthStore.maximumBytes + 1).write(to: fixture.health.fileURL)
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first), .unreadable)
    }

    func testSymlinkHealthIsUnreadableAndCannotModifyItsTarget() throws {
        let fixture = try fixture()
        let target = fixture.root.appendingPathComponent("unrelated-file")
        let original = Data("untouched".utf8)
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(at: fixture.health.fileURL, withDestinationURL: target)
        try capture(payload(), fixture: fixture)
        XCTAssertNotNil(try fixture.cache.load())
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first), .unreadable)
        XCTAssertEqual(try Data(contentsOf: target), original)
        try fixture.installer.remove()
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: fixture.health.fileURL.path), target.path)
        XCTAssertEqual(try Data(contentsOf: target), original)
    }

    func testHardLinkedHealthIsRejectedWithoutChangingTheOtherLink() throws {
        let fixture = try fixture()
        try capture(payload(), fixture: fixture)
        let other = fixture.root.appendingPathComponent("other-link")
        try FileManager.default.linkItem(at: fixture.health.fileURL, to: other)
        let before = try Data(contentsOf: other)
        try capture(payload(used: 41), fixture: fixture, at: first.addingTimeInterval(20))
        XCTAssertEqual(try fixture.cache.load()?.windows.first?.usedPercentage, 41)
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first.addingTimeInterval(20)), .unreadable)
        XCTAssertEqual(try Data(contentsOf: other), before)
    }

    func testClockRollbackDoesNotShowFutureActivityAndRestartsOneThrottleWindow() throws {
        let fixture = try fixture()
        try capture(Data("{}".utf8), fixture: fixture, at: first.addingTimeInterval(100))
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first), .waiting)
        try capture(Data("{}".utf8), fixture: fixture)
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first), observed(.noQuotaFields, at: first))
        try capture(payload(), fixture: fixture, at: first.addingTimeInterval(10))
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first.addingTimeInterval(10)), observed(.noQuotaFields, at: first))
    }

    func testMatchingHealthRemovedButQuotaAndBackupRemain() throws {
        let fixture = try fixture()
        try capture(payload(), fixture: fixture)
        let manifest = try JSONDecoder().decode(ClaudeStatuslineInstaller.Manifest.self,
                                                from: Data(contentsOf: fixture.installer.manifestURL))
        let quota = try Data(contentsOf: fixture.cache.fileURL)
        try fixture.installer.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.health.fileURL.path))
        XCTAssertEqual(try Data(contentsOf: fixture.cache.fileURL), quota)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.backupPath))
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first), .unavailable)
    }

    func testOtherInstallationHealthIsIgnoredAndPreservedByRemoval() throws {
        let fixture = try fixture()
        try fixture.cache.withExclusiveAccess {
            try fixture.health.recordLocked(.captured, installationID: UUID().uuidString, at: first)
        }
        let oldBytes = try Data(contentsOf: fixture.health.fileURL)
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first), .waiting)
        try fixture.installer.remove()
        XCTAssertEqual(try Data(contentsOf: fixture.health.fileURL), oldBytes)
    }

    func testReinstallStartsNewActivityAndRejectsRetiredCaptures() throws {
        let fixture = try fixture()
        try capture(payload(), fixture: fixture)
        let retired = try JSONDecoder().decode(ClaudeStatuslineInstaller.Manifest.self,
                                              from: Data(contentsOf: fixture.installer.manifestURL))
        try fixture.installer.remove()
        let next = try fixture.installer.previewInstall()
        try fixture.installer.install(next)
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first), .waiting)
        try ClaudeStatuslineBridge.capture(Data("{}".utf8), manifestURL: fixture.installer.manifestURL,
            enabled: true, now: first.addingTimeInterval(1), installationID: next.installationID,
            environment: fixture.environment, homeDirectory: fixture.root)
        let currentBytes = try Data(contentsOf: fixture.health.fileURL)
        XCTAssertThrowsError(try ClaudeStatuslineBridge.capture(payload(), manifest: retired,
            manifestURL: fixture.installer.manifestURL,
            directories: ClaudeConfigurationDirectories(environment: fixture.environment, homeDirectory: fixture.root),
            now: first.addingTimeInterval(100)))
        XCTAssertEqual(try Data(contentsOf: fixture.health.fileURL), currentBytes)
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first.addingTimeInterval(100)),
                       observed(.noQuotaFields, at: first.addingTimeInterval(1)))
    }

    func testDifferentConfigurationCannotRecordOrBorrowActivity() throws {
        let fixture = try fixture()
        let otherEnvironment = ["CLAUDE_CONFIG_DIR": fixture.root.appendingPathComponent("different").path]
        XCTAssertThrowsError(try ClaudeStatuslineBridge.capture(Data("{}".utf8),
            manifestURL: fixture.installer.manifestURL, enabled: true, now: first,
            installationID: fixture.installationID, environment: otherEnvironment, homeDirectory: fixture.root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.health.fileURL.path))
        try capture(payload(), fixture: fixture)
        let other = ClaudeStatuslineInstaller(cache: fixture.cache, executableURL: fixture.installer.executableURL,
            environment: otherEnvironment, homeDirectory: fixture.root)
        XCTAssertEqual(other.bridgeHealth(at: first), .unavailable)
    }

    func testConflictRecoveryRemovesOnlyItsMatchingHealth() throws {
        let fixture = try fixture()
        try capture(Data("{}".utf8), fixture: fixture)
        let edited = Data(#"{"statusLine":{"type":"command","command":"printf replacement"}}"#.utf8)
        try edited.write(to: fixture.installer.settingsURL)
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first), .unavailable)
        try fixture.installer.forgetConflictingInstallation()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.health.fileURL.path))
        XCTAssertEqual(try Data(contentsOf: fixture.installer.settingsURL), edited)
    }

    func testLegacyAnonymousBridgeKeepsQuotaWithoutAddingHealth() throws {
        let fixture = try fixture()
        // Legacy input keeps its existing contract without a health store.
        try fixture.cache.capture(payload(), at: first)
        XCTAssertNil(try fixture.cache.loadEntry()?.installationID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.health.fileURL.path))
        var manifest = try json(fixture.installer.manifestURL)
        manifest.removeValue(forKey: "installationID")
        try JSONSerialization.data(withJSONObject: manifest).write(to: fixture.installer.manifestURL)
        XCTAssertEqual(fixture.installer.bridgeHealth(at: first), .unavailable)
    }

    private struct Fixture {
        let root: URL
        let environment: [String: String]
        let installer: ClaudeStatuslineInstaller
        let installationID: String
        var cache: ClaudeStatuslineCache { installer.cache }
        var health: ClaudeBridgeHealthStore { ClaudeBridgeHealthStore(cache: cache) }
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("ClaudeBridgeHealthTests-\(UUID().uuidString)")
        try ClaudeLocalFile.createPrivateDirectory(root)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("synthetic-app")
        try Data("#!/bin/sh\nexit 99\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let environment = ["CLAUDE_CONFIG_DIR": root.appendingPathComponent("profile").path]
        let cache = ClaudeStatuslineCache(fileURL: root.appendingPathComponent("support/statusline-quota.json"))
        let installer = ClaudeStatuslineInstaller(cache: cache, executableURL: executable,
            environment: environment, homeDirectory: root)
        let preview = try installer.previewInstall()
        try installer.install(preview)
        return Fixture(root: root, environment: environment, installer: installer, installationID: preview.installationID)
    }

    private func capture(_ data: Data, fixture: Fixture, at date: Date? = nil) throws {
        try ClaudeStatuslineBridge.capture(data, manifestURL: fixture.installer.manifestURL,
            enabled: true, now: date ?? first, installationID: fixture.installationID,
            environment: fixture.environment, homeDirectory: fixture.root)
    }

    private func payload(used: Int = 23, reset: Int = 2_000_010_000) -> Data {
        Data("{\"session_id\":\"00000000-0000-0000-0000-000000000001\",\"rate_limits\":{\"five_hour\":{\"used_percentage\":\(used),\"resets_at\":\(reset)}}}".utf8)
    }

    private func observed(_ outcome: ClaudeBridgeHealthOutcome, at date: Date) -> ClaudeBridgeHealthState {
        .observed(ClaudeBridgeHealthObservation(recordedAt: date, outcome: outcome))
    }

    private func json(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func inode(_ url: URL) throws -> UInt64 {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { throw ClaudeQuotaIssue.unavailable }
        return UInt64(value.st_ino)
    }
}
