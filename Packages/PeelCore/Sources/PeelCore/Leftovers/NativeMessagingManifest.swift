import Foundation
internal import PeelPrivileged

extension NativeMessagingManifest {
    static func program(at url: URL) -> String? {
        guard isManifest(named: url.lastPathComponent), let data = BoundedRead.data(at: url, maximum: maximumSize)
        else { return nil }
        return program(in: data)
    }

    /// Whether the manifest at `url` starts nothing: a link that leads nowhere, or a manifest naming a program that is
    /// gone.
    static func startsNothing(at url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil {
            return !FileManager.default.fileExists(atPath: path)
        }
        return program(at: url).map(isGone) ?? false
    }
}
