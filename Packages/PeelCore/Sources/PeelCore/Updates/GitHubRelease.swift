import Foundation

/// A repository's latest release, as GitHub's REST API answers it: the newest one that is neither a draft nor a
/// prerelease.
enum GitHubRelease {
    /// Peel's own releases, the one repository Peel asks about: no other app says where it is released.
    static let peel = URL(string: "https://api.github.com/repos/TuguiDragos/Peel/releases/latest")!

    /// The version the release's tag names, the release's page on GitHub, where it is downloaded, and its
    /// description, in Markdown. Nil for an answer in any other form.
    static func latest(in data: Data) -> (version: String, page: URL?, notes: ReleaseNotes?)? {
        guard let release = try? JSONDecoder().decode(Release.self, from: data) else { return nil }
        let version = release.tagName.first == "v" || release.tagName.first == "V"
            ? String(release.tagName.dropFirst())
            : release.tagName
        guard !version.isEmpty else { return nil }
        let page = release.htmlURL.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" && $0.host() == "github.com" ? $0 : nil }
        return (version, page, release.body.flatMap { ReleaseNotes($0, format: .markdown) })
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: String?
        let body: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body
        }
    }
}
