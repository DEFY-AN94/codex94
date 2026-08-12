import Foundation

struct SnapshotCache: Sendable {
    private struct CachedWindow: Codable {
        let kind: QuotaWindowKind
        let usedPercent: Int
        let resetsAt: Date?
    }

    private struct CachedSnapshot: Codable {
        let windows: [CachedWindow]
        let planType: String?
        let fetchedAt: Date
    }

    let fileURL: URL

    init(fileURL: URL? = nil) {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        self.fileURL = fileURL
            ?? applicationSupport.appendingPathComponent("Codex94/quota-snapshot.json")
    }

    func load() -> QuotaSnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let cached = try? JSONDecoder.codex94.decode(CachedSnapshot.self, from: data) else {
            return nil
        }

        return QuotaSnapshot(
            windows: cached.windows.map {
                QuotaWindowSnapshot(
                    kind: $0.kind,
                    usedPercent: $0.usedPercent,
                    windowMinutes: nil,
                    resetsAt: $0.resetsAt
                )
            },
            planType: cached.planType,
            fetchedAt: cached.fetchedAt,
            account: nil,
            codex: nil
        )
    }

    func save(_ snapshot: QuotaSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )

        let cached = CachedSnapshot(
            windows: snapshot.windows.map {
                CachedWindow(kind: $0.kind, usedPercent: $0.usedPercent, resetsAt: $0.resetsAt)
            },
            planType: snapshot.planType,
            fetchedAt: snapshot.fetchedAt
        )
        let data = try JSONEncoder.codex94.encode(cached)
        try data.write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}

private extension JSONEncoder {
    static var codex94: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var codex94: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
