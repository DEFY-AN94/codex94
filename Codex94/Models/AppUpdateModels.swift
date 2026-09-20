import Foundation

struct AppReleaseVersion: Equatable, Comparable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ raw: String) {
        let value = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty,
                  part.utf8.allSatisfy({ (48...57).contains($0) }),
                  part.count == 1 || part.first != "0" else { return nil }
            return Int(part)
        }
        guard numbers.count == 3 else { return nil }
        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
    }

    var normalized: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

struct AppRelease: Equatable, Sendable {
    let version: AppReleaseVersion
    let tagName: String
    let name: String
    let notes: String
    let pageURL: URL
    let dmgURL: URL?

    static func parse(_ data: Data) throws -> AppRelease {
        let payload: ReleasePayload
        do { payload = try JSONDecoder().decode(ReleasePayload.self, from: data) }
        catch { throw AppUpdateIssue.invalidResponse }
        guard !payload.draft, !payload.prerelease else { throw AppUpdateIssue.noPublishedRelease }
        guard let version = AppReleaseVersion(payload.tagName),
              let pageURL = validatedURL(
                  payload.htmlURL,
                  path: "/DEFY-AN94/codex94/releases/tag/\(payload.tagName)"
              ) else {
            throw AppUpdateIssue.invalidResponse
        }
        let expectedAsset = "Codex94-\(version.normalized)-macos-universal-unnotarized.dmg"
        let dmgURL = payload.assets.lazy
            .filter { $0.name == expectedAsset }
            .compactMap {
                validatedURL(
                    $0.browserDownloadURL,
                    path: "/DEFY-AN94/codex94/releases/download/\(payload.tagName)/\(expectedAsset)"
                )
            }
            .first
        return AppRelease(
            version: version,
            tagName: payload.tagName,
            name: String((payload.name ?? payload.tagName).prefix(200)),
            notes: String((payload.body ?? "").prefix(8_000)),
            pageURL: pageURL,
            dmgURL: dmgURL
        )
    }

    private static func validatedURL(_ raw: String, path: String) -> URL? {
        guard let components = URLComponents(string: raw),
              components.scheme == "https", components.host == "github.com",
              components.port == nil, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.percentEncodedPath == path else { return nil }
        return components.url
    }

    private struct ReleasePayload: Decodable {
        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: String
        let prerelease: Bool
        let draft: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name, body, prerelease, draft, assets
            case htmlURL = "html_url"
        }
    }

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
}

enum AppUpdateIssue: Error, Equatable, Sendable {
    case noPublishedRelease
    case rateLimited
    case offline
    case timedOut
    case unavailable
    case invalidResponse
    case responseTooLarge
    case invalidCurrentVersion

    var localizationKey: String {
        switch self {
        case .noPublishedRelease: "updates.error.noPublishedRelease"
        case .rateLimited: "updates.error.rateLimited"
        case .offline: "updates.error.offline"
        case .timedOut: "updates.error.timedOut"
        case .unavailable: "updates.error.unavailable"
        case .invalidResponse: "updates.error.invalidResponse"
        case .responseTooLarge: "updates.error.responseTooLarge"
        case .invalidCurrentVersion: "updates.error.invalidCurrentVersion"
        }
    }
}

enum AppUpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(AppRelease)
    case failed(AppUpdateIssue)
}
