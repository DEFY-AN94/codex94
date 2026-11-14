import Foundation

/// Installation activity is not quota freshness or proof of account identity.
enum ClaudeBridgeHealthOutcome: String, Codable, CaseIterable, Sendable {
    case captured, unchanged, noQuotaFields, expiredWindows, invalidInput, captureFailed
}

struct ClaudeBridgeHealthObservation: Equatable, Sendable {
    let recordedAt: Date
    let outcome: ClaudeBridgeHealthOutcome
}

enum ClaudeBridgeHealthState: Equatable, Sendable {
    case unavailable
    case waiting
    case unreadable
    case observed(ClaudeBridgeHealthObservation)
}

/// One bounded, private diagnostic beside the existing quota cache. Mutations
/// are called only under that cache's installation lock after revalidation.
/// A failure here must never change quota capture or the user's statusline.
struct ClaudeBridgeHealthStore: Sendable {
    private struct Record: Codable {
        let schemaVersion: Int
        let installationID: String
        let recordedAt: Date
        let outcome: ClaudeBridgeHealthOutcome
    }

    static let maximumBytes = 4_096
    static let minimumWriteInterval: TimeInterval = 15
    let fileURL: URL

    init(cache: ClaudeStatuslineCache) {
        fileURL = cache.fileURL.deletingLastPathComponent().appendingPathComponent("statusline-health.json")
    }

    func read(installationID: String, at now: Date) throws -> ClaudeBridgeHealthObservation? {
        guard Self.validInstallation(installationID), Self.validTime(now) else {
            throw ClaudeQuotaIssue.invalidData
        }
        guard let record = try load(), record.installationID == installationID,
              record.recordedAt <= now else { return nil }
        return ClaudeBridgeHealthObservation(recordedAt: record.recordedAt, outcome: record.outcome)
    }

    /// Different outcomes are also throttled. This is the latest *recorded*
    /// activity, not a complete log of invocations. A wall-clock rollback opens
    /// one new interval rather than suppressing diagnostics indefinitely.
    func recordLocked(_ outcome: ClaudeBridgeHealthOutcome, installationID: String, at now: Date) throws {
        guard Self.validInstallation(installationID), Self.validTime(now) else {
            throw ClaudeQuotaIssue.invalidData
        }
        if let previous = try load(), previous.installationID == installationID {
            let age = now.timeIntervalSince(previous.recordedAt)
            if age >= 0, age < Self.minimumWriteInterval { return }
        }
        let record = Record(schemaVersion: 1, installationID: installationID, recordedAt: now, outcome: outcome)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        guard data.count <= Self.maximumBytes else { throw ClaudeQuotaIssue.invalidData }
        try ClaudeLocalFile.write(data, to: fileURL)
    }

    /// Leave unknown, malformed and other-installation files alone. The caller
    /// owns the installation lock; diagnostics never make removal fail.
    func removeLocked(installationID: String?) {
        guard let installationID, Self.validInstallation(installationID),
              let record = try? load(), record.installationID == installationID else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func load() throws -> Record? {
        let data: Data
        do {
            switch try ClaudeLocalFile.readStamped(fileURL, maximumBytes: Self.maximumBytes, requireCurrentOwner: true) {
            case let .contents(value, _): data = value
            case .unchanged: throw ClaudeQuotaIssue.invalidData
            }
        } catch ClaudeLocalFile.ReadFailure.absent { return nil }
        let expectedKeys: Set<String> = ["schemaVersion", "installationID", "recordedAt", "outcome"]
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == expectedKeys,
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.schemaVersion == 1, Self.validInstallation(record.installationID),
              Self.validTime(record.recordedAt) else { throw ClaudeQuotaIssue.invalidData }
        return record
    }

    private static func validInstallation(_ value: String) -> Bool {
        UUID(uuidString: value)?.uuidString == value
    }

    private static func validTime(_ value: Date) -> Bool {
        let seconds = value.timeIntervalSince1970
        return seconds.isFinite && (0...253_402_300_799).contains(seconds)
    }
}
