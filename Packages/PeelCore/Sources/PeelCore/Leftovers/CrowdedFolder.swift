public import Foundation

/// A folder a scan did not read, since it holds more entries than a scan reads.
public struct CrowdedFolder: Sendable, Hashable {
    public let url: URL
    /// Nil when the file system doesn't tell.
    public let entries: Int?
    /// False for a folder an uninstall passed over where nothing it found there would ever be selected: one below a
    /// searched place, named for neither the app nor its maker, with nothing of the app known inside. The app's page
    /// has no reason to name it. True in every other scan.
    public var concernsTheApp = true

    public init(url: URL, entries: Int?) {
        self.url = url
        self.entries = entries
    }
}

extension Sequence<CrowdedFolder> {
    /// Each folder once, by its path: two places a scan reads can be one folder, as the home folder is. One that any
    /// of them says concerns the app does, whichever answered first.
    var eachOnce: [CrowdedFolder] {
        var kept: [String: CrowdedFolder] = [:]
        for folder in self {
            let path = PathPattern.comparablePath(of: folder.url)
            if kept[path] == nil {
                kept[path] = folder
            } else if folder.concernsTheApp {
                kept[path]?.concernsTheApp = true
            }
        }
        return kept.values.sorted { $0.url.path(percentEncoded: false) < $1.url.path(percentEncoded: false) }
    }
}
