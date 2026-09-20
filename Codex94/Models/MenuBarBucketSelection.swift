import Foundation

/// The dual-window layout chooses a bucket independently of the single-window preference.
enum MenuBarBucketSelection: Codable, Equatable, Hashable, Sendable {
    case automatic
    case defaultBucket
    case bucket(limitID: String)

    private enum Mode: String, Codable {
        case automatic
        case defaultBucket
        case bucket
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case limitID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Mode.self, forKey: .mode) {
        case .automatic:
            self = .automatic
        case .defaultBucket:
            self = .defaultBucket
        case .bucket:
            let limitID = try container.decode(String.self, forKey: .limitID)
            guard !limitID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .limitID,
                    in: container,
                    debugDescription: "Quota limit ID must not be empty"
                )
            }
            self = .bucket(limitID: limitID)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .automatic:
            try container.encode(Mode.automatic, forKey: .mode)
        case .defaultBucket:
            try container.encode(Mode.defaultBucket, forKey: .mode)
        case let .bucket(limitID):
            try container.encode(Mode.bucket, forKey: .mode)
            try container.encode(limitID, forKey: .limitID)
        }
    }

    /// A missing explicit choice stays missing here; AppStore owns the fallback policy.
    func resolved(in snapshot: QuotaSnapshot) -> QuotaBucketSnapshot? {
        let bucket: QuotaBucketSnapshot?
        switch self {
        case .automatic:
            return snapshot.automaticResolvedWindow?.bucket
        case .defaultBucket:
            bucket = snapshot.defaultBucket
        case let .bucket(limitID):
            bucket = snapshot.bucket(id: limitID)
        }
        guard let bucket,
              !bucket.windows.isEmpty,
              snapshot.displayableBuckets.contains(where: { $0.limitID == bucket.limitID }) else {
            return nil
        }
        return bucket
    }
}

struct MenuBarBucketOption: Equatable, Identifiable, Sendable {
    let selection: MenuBarBucketSelection
    let bucketName: String?
    let isAvailable: Bool

    var id: MenuBarBucketSelection { selection }

    static func options(
        in snapshot: QuotaSnapshot?,
        selected: MenuBarBucketSelection
    ) -> [MenuBarBucketOption] {
        var options = [MenuBarBucketOption(
            selection: .automatic, bucketName: nil, isAvailable: true
        )]
        if let snapshot {
            options += snapshot.displayableBuckets.filter { !$0.windows.isEmpty }.map { bucket in
                MenuBarBucketOption(
                    selection: bucket.limitID == snapshot.defaultLimitID
                        ? .defaultBucket : .bucket(limitID: bucket.limitID),
                    bucketName: snapshot.displayName(for: bucket),
                    isAvailable: true
                )
            }
        }
        if selected != .automatic, !options.contains(where: { $0.selection == selected }) {
            options.append(MenuBarBucketOption(
                selection: selected,
                bucketName: selected == .defaultBucket ? "Codex" : nil,
                isAvailable: false
            ))
        }
        return options
    }
}
