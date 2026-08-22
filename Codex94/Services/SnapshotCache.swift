import Foundation

struct SnapshotCache: Sendable {
    private struct CacheVersionProbe: Decodable {
        private enum CodingKeys: String, CodingKey {
            case version
        }

        let containsVersion: Bool
        let version: Int?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            containsVersion = container.contains(.version)
            version = try container.decodeIfPresent(Int.self, forKey: .version)
        }
    }

    private struct CachedWindowV2: Codable {
        let kind: QuotaWindowKind
        let usedPercent: Int
        let windowMinutes: Int?
        let resetsAt: Date?
    }

    private struct CachedBucketV2: Codable {
        let limitID: String
        let limitName: String?
        let planType: String?
        let windows: [CachedWindowV2]
    }

    private struct CachedSnapshotV2: Codable {
        let version: Int
        let buckets: [CachedBucketV2]
        let defaultLimitID: String
        let fetchedAt: Date
    }

    private struct CachedWindowV1: Codable {
        let kind: QuotaWindowKind
        let usedPercent: Int
        let resetsAt: Date?
    }

    private struct CachedSnapshotV1: Codable {
        let windows: [CachedWindowV1]
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
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let versionProbe = try? JSONDecoder.codex94.decode(
            CacheVersionProbe.self,
            from: data
        ) else {
            return nil
        }

        if versionProbe.containsVersion {
            guard versionProbe.version == 2,
                  let cached = try? JSONDecoder.codex94.decode(
                      CachedSnapshotV2.self,
                      from: data
                  ) else {
                return nil
            }
            let buckets = cached.buckets.map { bucket in
                QuotaBucketSnapshot(
                    limitID: bucket.limitID,
                    limitName: bucket.limitName,
                    planType: bucket.planType,
                    windows: bucket.windows.map {
                        QuotaWindowSnapshot(
                            kind: $0.kind,
                            usedPercent: $0.usedPercent,
                            windowMinutes: $0.windowMinutes,
                            resetsAt: $0.resetsAt
                        )
                    }
                )
            }
            let ids = buckets.map(\.limitID)
            let bucketsAreValid = buckets.allSatisfy { bucket in
                let kinds = bucket.windows.map(\.kind)
                return Set(kinds).count == kinds.count
                    && (bucket.limitID == cached.defaultLimitID || !bucket.windows.isEmpty)
            }
            guard !buckets.isEmpty,
                  ids.allSatisfy({
                      !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  }),
                  Set(ids).count == ids.count,
                  ids.contains(cached.defaultLimitID),
                  bucketsAreValid else {
                return nil
            }

            let snapshot = QuotaSnapshot(
                buckets: buckets,
                defaultLimitID: cached.defaultLimitID,
                fetchedAt: cached.fetchedAt,
                account: nil,
                codex: nil
            )
            guard snapshot.displayableBuckets.contains(where: { !$0.windows.isEmpty }) else {
                return nil
            }
            return snapshot
        }

        guard let cached = try? JSONDecoder.codex94.decode(CachedSnapshotV1.self, from: data),
              !cached.windows.isEmpty else {
            return nil
        }

        return QuotaSnapshot(
            buckets: [
                QuotaBucketSnapshot(
                    limitID: "codex",
                    limitName: nil,
                    planType: cached.planType,
                    windows: cached.windows.map {
                        QuotaWindowSnapshot(
                            kind: $0.kind,
                            usedPercent: $0.usedPercent,
                            windowMinutes: nil,
                            resetsAt: $0.resetsAt
                        )
                    }
                )
            ],
            defaultLimitID: "codex",
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

        let cached = CachedSnapshotV2(
            version: 2,
            buckets: snapshot.buckets.map { bucket in
                CachedBucketV2(
                    limitID: bucket.limitID,
                    limitName: bucket.limitName,
                    planType: bucket.planType,
                    windows: bucket.windows.map {
                        CachedWindowV2(
                            kind: $0.kind,
                            usedPercent: $0.usedPercent,
                            windowMinutes: $0.windowMinutes,
                            resetsAt: $0.resetsAt
                        )
                    }
                )
            },
            defaultLimitID: snapshot.defaultLimitID,
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
