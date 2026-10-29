import Foundation

/// A published build, as described by GitHub's "latest release" API.
/// CI names releases "BetterGlide (build N)", where N is the CFBundleVersion of that build.
struct ReleaseInfo: Equatable {
    let build: Int
    let title: String
    let notes: String
    let downloadURL: URL
    let pageURL: URL?
    let publishedAt: Date?

    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/KubaCh7/Better_glide/releases/latest")!

    static func parse(_ data: Data) -> ReleaseInfo? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let title = json["name"] as? String,
              let build = buildNumber(in: title),
              let assets = json["assets"] as? [[String: Any]],
              let dmg = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
              let urlString = dmg["browser_download_url"] as? String,
              let downloadURL = URL(string: urlString)
        else { return nil }
        return ReleaseInfo(
            build: build,
            title: title,
            notes: json["body"] as? String ?? "",
            downloadURL: downloadURL,
            pageURL: (json["html_url"] as? String).flatMap(URL.init(string:)),
            publishedAt: (json["published_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        )
    }

    /// "BetterGlide (build 12)" → 12.
    static func buildNumber(in title: String) -> Int? {
        guard let range = title.range(of: "build ", options: .caseInsensitive) else { return nil }
        let digits = title[range.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }

    func isNewer(than currentBuild: Int) -> Bool {
        build > currentBuild
    }
}
