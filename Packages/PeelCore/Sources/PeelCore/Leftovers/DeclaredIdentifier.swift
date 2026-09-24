import Foundation

/// The identifier an item declares about itself, for when its file name matches nothing: a plug-in is named for
/// what it does rather than for who made it, and a container is sometimes named by a UUID. The identifier is
/// only a claim, so it goes through the same matching as a file name.
enum DeclaredIdentifier {
    static func of(_ url: URL, kind: SearchLocation.Kind) -> String? {
        switch kind {
        case .plugIns: Plugins.declaredIdentifier(at: url)
        case .containers: container(at: url)
        default: nil
        }
    }

    /// The `MCMMetadataIdentifier` in a container's metadata, read only when the folder's name is not already an
    /// identifier. On macOS 26, a container whose name is an identifier is named after that value, so reading
    /// the file would add nothing.
    private static func container(at url: URL) -> String? {
        guard !Identifier.isReverseDNS(url.lastPathComponent) else { return nil }
        let metadata = url.appending(path: ".com.apple.containermanagerd.metadata.plist")
        return BoundedRead.propertyList(at: metadata)?["MCMMetadataIdentifier"] as? String
    }
}
