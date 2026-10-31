import Foundation

/// The service Microsoft's build of VS Code asks about its own updates (`updateService.darwin.ts` and
/// `abstractUpdateService.ts` in microsoft/vscode at e646868227c3e3a9e3f24277c8c7220be42c0be7).
enum VSCodeUpdateService {
    /// An editor built on VS Code names a service of its own, whose answers Peel doesn't know.
    static let service = "https://update.code.visualstudio.com"

    enum Reading: Equatable {
        case unreadable
        case nothingOffered
        case offered(version: String)
    }

    /// The address VS Code asks when you check for updates (`createUpdateURL`), from its `product.json`: the build's
    /// platform, its quality and the commit it was made from. Only a stable build, since an Insiders build keeps its
    /// version from one build to the next.
    static func feedURL(product: [String: Any], runsOnAppleSilicon: Bool) -> URL? {
        guard product["updateUrl"] as? String == service, product["quality"] as? String == "stable",
              let commit = product["commit"] as? String, commit.wholeMatch(of: /[0-9a-f]{40}/) != nil
        else { return nil }
        let platform = product["darwinUniversalAssetId"] as? String ?? (runsOnAppleSilicon ? "darwin-arm64" : "darwin")
        guard platform.wholeMatch(of: /[a-z0-9-]+/) != nil else { return nil }
        return URL(string: "\(service)/api/update/\(platform)/stable/\(commit)?u=none")
    }

    /// A reply as VS Code reads one (`checkForUpdateNoDownload`): it offers a build only when it names the download,
    /// the commit and the version.
    static func read(_ data: Data) -> Reading {
        guard let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .unreadable }
        guard reply["url"] is String, reply["version"] is String, let version = reply["productVersion"] as? String,
              !version.isEmpty
        else { return .nothingOffered }
        return .offered(version: version)
    }
}
