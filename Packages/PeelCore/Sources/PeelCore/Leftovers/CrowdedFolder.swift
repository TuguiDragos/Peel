public import Foundation

/// A folder a scan did not read, since it holds more entries than a scan reads.
public struct CrowdedFolder: Sendable, Hashable {
    public let url: URL
    /// Nil when the file system doesn't tell.
    public let entries: Int?

    public init(url: URL, entries: Int?) {
        self.url = url
        self.entries = entries
    }
}
