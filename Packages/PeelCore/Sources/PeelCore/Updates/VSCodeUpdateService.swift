import Foundation

/// The service Microsoft's build of VS Code asks about its own updates (`updateService.darwin.ts` and
/// `abstractUpdateService.ts` in microsoft/vscode at e646868227c3e3a9e3f24277c8c7220be42c0be7).
enum VSCodeUpdateService {
    /// An editor built on VS Code names a service of its own, whose answers Peel doesn't know.
    static let service = "https://update.code.visualstudio.com"

    /// The address of the latest stable build, for a stable build of Microsoft's, whose `product.json` names the
    /// service. VS Code asks about the commit it was built from, which names its version, and for its own platform, so
    /// Peel asks for the latest build of one platform whatever is installed: every platform gets the same version, and
    /// the address says nothing of this Mac. Only a stable build, since an Insiders build keeps its version from one
    /// build to the next.
    static func feedURL(product: [String: Any]) -> URL? {
        guard product["updateUrl"] as? String == service, product["quality"] as? String == "stable" else { return nil }
        return URL(string: "\(service)/api/update/darwin-universal/stable/latest")
    }

    /// The version a reply gives the latest build, its `productVersion`: its `version` is the commit.
    static func version(in data: Data) -> String? {
        let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let version = reply?["productVersion"] as? String, !version.isEmpty else { return nil }
        return version
    }
}
