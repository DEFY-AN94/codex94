import CryptoKit
import Darwin
import Foundation

enum ClaudeStatuslineParser {
    static let maximumInputBytes = 1_048_576
    static let legacyUnknownProducerID = ClaudeLocalFile.digest(Data("Codex94.ClaudeStatusline.v1:unknown-session".utf8))

    struct ParsedInput: Equatable, Sendable {
        let windows: [ClaudeQuotaWindow]
        let producerID: String
    }

    /// Capture needs both values from one bounded JSON decode. Compatibility
    /// entry points below retain their own original validation responsibilities.
    static func parse(_ data: Data) throws -> ParsedInput {
        let root = try object(from: data)
        return ParsedInput(windows: try windows(in: root), producerID: producerID(in: root))
    }

    /// The legacy anonymous discriminator deduplicates reports but cannot bind
    /// a stream: unrelated sessions without IDs all share that same value.
    static func identifiableProducerID(_ value: String?) -> String? {
        guard let normalized = ClaudePassiveProducerID.normalized(value), normalized != legacyUnknownProducerID else { return nil }
        return normalized
    }

    static func producerID(from data: Data) throws -> String {
        producerID(in: try object(from: data))
    }

    private static func producerID(in root: [String: Any]) -> String {
        // This opaque session discriminator is never interpreted as account identity.
        let session = (root["session_id"] as? String).flatMap { UUID(uuidString: $0) }?.uuidString ?? "unknown-session"
        return ClaudeLocalFile.digest(Data(("Codex94.ClaudeStatusline.v1:" + session).utf8))
    }

    static func windows(from data: Data) throws -> [ClaudeQuotaWindow] {
        try windows(in: object(from: data))
    }

    private static func object(from data: Data) throws -> [String: Any] {
        guard data.count <= maximumInputBytes,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeQuotaIssue.invalidData
        }
        return root
    }

    private static func windows(in root: [String: Any]) throws -> [ClaudeQuotaWindow] {
        guard let raw = root["rate_limits"], !(raw is NSNull) else { return [] }
        guard let limits = raw as? [String: Any] else { throw ClaudeQuotaIssue.invalidData }
        return try [("five_hour", QuotaWindowKind.fiveHour), ("seven_day", .weekly)].compactMap { key, kind in
            guard let value = limits[key], !(value is NSNull) else { return nil }
            guard let window = value as? [String: Any],
                  let percentage = StrictJSONPercentage.value(window["used_percentage"]),
                  let reset = StrictJSONInteger.nonnegative(window["resets_at"]),
                  reset <= 253_402_300_799 else { throw ClaudeQuotaIssue.invalidData }
            return ClaudeQuotaWindow(kind: kind, usedPercentage: percentage,
                                     resetsAt: Date(timeIntervalSince1970: Double(reset)))
        }
    }
}

/// Only the two public quota windows and observation timestamps are persisted.
struct ClaudeStatuslineCache: Sendable {
    private struct Record: Codable {
        let version: Int
        let report: ClaudeQuotaReport
        let producers: [String: Producer]
    }

    private struct Producer: Codable {
        let fingerprint: String
        let reportedAt: Date
        let validUntil: Date
    }

    let fileURL: URL
    static let maximumCacheBytes = 65_536

    init(fileURL: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? support.appendingPathComponent("Codex94/Claude/statusline-quota.json")
    }

    func load() throws -> ClaudeQuotaReport? {
        try loadRecord()?.report
    }

    private func loadRecord() throws -> Record? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try ClaudeLocalFile.read(fileURL, maximumBytes: Self.maximumCacheBytes)
        guard let record = try? JSONDecoder().decode(Record.self, from: data), record.version == 1,
              record.report.source == .statusline,
              record.report.modelLimits.isEmpty,
              Self.isSupportedTimestamp(record.report.reportedAt),
              Self.isSupportedTimestamp(record.report.receivedAt),
              record.report.reportedAt <= record.report.receivedAt,
              record.producers.count <= 128,
              record.producers.allSatisfy({ key, value in
                  key.count == 64 && key.allSatisfy(\.isHexDigit)
                    && value.fingerprint.count == 64 && value.fingerprint.allSatisfy(\.isHexDigit)
                    && Self.isSupportedTimestamp(value.reportedAt) && Self.isSupportedTimestamp(value.validUntil)
                    && value.reportedAt <= value.validUntil && value.reportedAt <= record.report.receivedAt
              }),
              record.report.windows.count <= 2,
              Set(record.report.windows.map(\.kind)).count == record.report.windows.count,
              record.report.windows.allSatisfy({ window in
                  window.usedPercentage.isFinite && (0...100).contains(window.usedPercentage)
                    && window.resetsAt.map(Self.isSupportedTimestamp) == true
              }) else { throw ClaudeQuotaIssue.invalidData }
        return record
    }

    private static func isSupportedTimestamp(_ date: Date) -> Bool {
        let seconds = date.timeIntervalSince1970
        return seconds.isFinite && (0...253_402_300_799).contains(seconds)
    }

    func capture(_ data: Data, at now: Date = Date()) throws {
        let parsed = try ClaudeStatuslineParser.parse(data)
        let windows = parsed.windows
        // Startup/expired statusline payloads are not new quota evidence. They
        // must not overwrite a useful report or advance its observation clock.
        guard windows.contains(where: { $0.resetsAt.map { $0 > now } ?? false }) else { return }
        let producerID = parsed.producerID
        try ClaudeLocalFile.createPrivateDirectory(fileURL.deletingLastPathComponent())
        let lockURL = fileURL.appendingPathExtension("lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw ClaudeQuotaIssue.unavailable }
        defer { Darwin.close(descriptor) }
        // Statusline producers must never stall another terminal's status line.
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return }
        defer { flock(descriptor, LOCK_UN) }
        let previous = try loadRecord()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let fingerprint = ClaudeLocalFile.digest(try encoder.encode(windows))
        var producers = previous?.producers.filter { $0.value.validUntil > now } ?? [:]
        guard producers[producerID] != nil || producers.count < 128 else { throw ClaudeQuotaIssue.unavailable }
        let priorProducer = producers[producerID]
        let reportedAt = priorProducer?.fingerprint == fingerprint ? priorProducer!.reportedAt : now
        producers[producerID] = Producer(
            fingerprint: fingerprint, reportedAt: reportedAt,
            validUntil: max(windows.compactMap(\.resetsAt).max() ?? now, now.addingTimeInterval(7 * 86_400))
        )
        let report = ClaudeQuotaReport(source: .statusline, reportedAt: reportedAt,
                                       receivedAt: max(now, reportedAt), windows: windows, producerID: producerID)
        // An older cached producer cannot displace a more recent observed report.
        let selected = previous.map { $0.report.reportedAt > reportedAt ? $0.report : report } ?? report
        let encoded = try encoder.encode(Record(version: 1, report: selected, producers: producers))
        guard encoded.count <= Self.maximumCacheBytes else { throw ClaudeQuotaIssue.invalidData }
        try ClaudeLocalFile.write(encoded, to: fileURL)
    }
}

/// File boundaries shared by the opt-in configuration and quota bridge only.
enum ClaudeLocalFile {
    struct ReadStamp: Equatable, Sendable {
        let device: Int64
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
    }

    enum StampedRead: Equatable, Sendable {
        case unchanged(ReadStamp)
        case contents(Data, ReadStamp)
    }

    enum ReadFailure: Error, Equatable {
        case absent, unavailable, invalidFile, changedDuringRead
    }

    static func requireNoSymlinks(_ url: URL) throws {
        // Foundation deliberately folds /private/var and /private/tmp back to
        // /var and /tmp, even in resolvingSymlinksInPath(). Handle only those
        // root-owned system aliases; never resolve arbitrary user symlinks.
        var parts = url.path.split(separator: "/").map(String.init)
        guard url.isFileURL, url.path.hasPrefix("/"), !parts.contains(".."), !parts.contains(".") else {
            throw ClaudeQuotaIssue.configurationConflict
        }
        if let first = parts.first, first == "var" || first == "tmp" {
            let alias = "/" + first
            var value = stat()
            if lstat(alias, &value) == 0, value.st_mode & S_IFMT == S_IFLNK {
                let destination = try FileManager.default.destinationOfSymbolicLink(atPath: alias)
                guard value.st_uid == 0, destination == "private/" + first || destination == "/private/" + first else {
                    throw ClaudeQuotaIssue.configurationConflict
                }
                parts.insert("private", at: 0)
            }
        }
        var current = ""
        for part in parts {
            current += "/" + part
            var value = stat()
            if lstat(current, &value) == 0 {
                if value.st_mode & S_IFMT == S_IFLNK { throw ClaudeQuotaIssue.configurationConflict }
            } else if errno != ENOENT {
                throw ClaudeQuotaIssue.unavailable
            }
        }
    }

    static func createPrivateDirectory(_ url: URL) throws {
        try requireNoSymlinks(url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
    }

    static func read(_ url: URL, maximumBytes: Int) throws -> Data {
        do {
            switch try readStamped(url, maximumBytes: maximumBytes) {
            case let .contents(data, _): return data
            case .unchanged: throw ClaudeQuotaIssue.invalidData // No previous stamp was supplied.
            }
        } catch ReadFailure.invalidFile {
            throw ClaudeQuotaIssue.invalidData
        } catch is ReadFailure {
            throw ClaudeQuotaIssue.unavailable
        }
    }

    /// The owner requirement is opt-in: local Claude Code state requires the
    /// current uid; existing bridge/configuration reads retain their prior policy.
    /// A changing file never supplies stable bytes/stamp, and is not retried here.
    static func readStamped(
        _ url: URL, maximumBytes: Int, requireCurrentOwner: Bool = false,
        unchangedSince previous: ReadStamp? = nil,
        readData: ((FileHandle, Int) throws -> Data)? = nil
    ) throws -> StampedRead {
        guard maximumBytes >= 0, maximumBytes < Int.max else { throw ReadFailure.invalidFile }
        try requireNoSymlinks(url)
        // O_NOFOLLOW protects the last component; O_NONBLOCK lets fstat reject
        // a FIFO without waiting for a writer on the calling thread.
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw errno == ENOENT ? ReadFailure.absent : .unavailable }
        defer { Darwin.close(descriptor) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        var before = stat()
        guard fstat(descriptor, &before) == 0 else { throw ReadFailure.unavailable }
        guard isReadableRegularFile(before, maximumBytes: maximumBytes, requireCurrentOwner: requireCurrentOwner) else {
            throw ReadFailure.invalidFile
        }
        let stamp = readStamp(before)
        if previous == stamp { return .unchanged(stamp) }
        let data: Data
        do { data = try readData?(handle, maximumBytes + 1) ?? handle.read(upToCount: maximumBytes + 1) ?? Data() }
        catch {
            var afterFailure = stat()
            if fstat(descriptor, &afterFailure) == 0,
               readStamp(afterFailure) != stamp || afterFailure.st_nlink != before.st_nlink
                || afterFailure.st_uid != before.st_uid {
                throw ReadFailure.changedDuringRead
            }
            throw ReadFailure.unavailable
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0 else { throw ReadFailure.unavailable }
        guard isReadableRegularFile(after, maximumBytes: maximumBytes, requireCurrentOwner: requireCurrentOwner),
              readStamp(after) == stamp, data.count == before.st_size,
              data.count <= maximumBytes else { throw ReadFailure.changedDuringRead }
        return .contents(data, stamp)
    }

    private static func isReadableRegularFile(_ info: stat, maximumBytes: Int, requireCurrentOwner: Bool) -> Bool {
        info.st_mode & S_IFMT == S_IFREG && info.st_nlink == 1
            && info.st_size >= 0 && info.st_size <= maximumBytes
            && (!requireCurrentOwner || info.st_uid == getuid())
    }

    private static func readStamp(_ info: stat) -> ReadStamp {
        ReadStamp(device: Int64(info.st_dev), inode: UInt64(info.st_ino), size: Int64(info.st_size),
                  modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec))
    }

    static func write(_ data: Data, to url: URL) throws {
        try requireNoSymlinks(url)
        try createPrivateDirectory(url.deletingLastPathComponent())
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
