import Foundation

/// Quota-only records partitioned by a verified profile. No credential, raw
/// response, email, or token fingerprint is accepted by this cache interface.
struct ClaudeOAuthQuotaCache: Sendable {
    private struct Record: Codable {
        let version: Int
        let report: ClaudeQuotaReport
    }

    let directory: URL
    static let maximumBytes = 65_536

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("Codex94/Claude/OAuth", isDirectory: true)
    }

    static func isolationKey(for context: ClaudeOAuthAccountContext) -> String {
        // UUID-only canonical components; unrelated to credential generation.
        ClaudeLocalFile.digest(Data((context.accountID.uuidString.lowercased() + ":"
                                    + context.organizationID.uuidString.lowercased()).utf8))
    }

    func fileURL(for context: ClaudeOAuthAccountContext) -> URL {
        directory.appendingPathComponent(Self.isolationKey(for: context) + ".json")
    }

    func load(context: ClaudeOAuthAccountContext) throws -> ClaudeQuotaReport? {
        let url = fileURL(for: context)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try ClaudeLocalFile.read(url, maximumBytes: Self.maximumBytes, requirePrivateOwner: true)
        guard let record = try? JSONDecoder().decode(Record.self, from: data), record.version == 1,
              record.report.accountContext == context, Self.isValid(record.report) else {
            throw ClaudeOAuthIssue.invalidData
        }
        return record.report
    }

    func save(report: ClaudeQuotaReport) throws {
        guard Self.isValid(report), let context = report.accountContext else {
            throw ClaudeOAuthIssue.invalidData
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Record(version: 1, report: report))
        guard data.count <= Self.maximumBytes else { throw ClaudeOAuthIssue.responseTooLarge }
        try ClaudeLocalFile.write(data, to: fileURL(for: context))
    }

    private static func isValid(_ report: ClaudeQuotaReport) -> Bool {
        report.source == .oauth && report.accountContext != nil && report.producerID == nil
            && ClaudeQuotaSourcePolicy.validTimestamp(report.reportedAt)
            && ClaudeQuotaSourcePolicy.validTimestamp(report.receivedAt)
            && report.receivedAt == report.reportedAt
            && ClaudeQuotaSourcePolicy.validWindows(report.windows)
    }
}
