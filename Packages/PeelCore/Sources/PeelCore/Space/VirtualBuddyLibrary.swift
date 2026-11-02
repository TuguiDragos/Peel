import Foundation

/// VirtualBuddy's library: a machine is a `.vbvm` package, and each records in `.vbdata/Metadata.plist` the local
/// restore image it was installed from (`installImageURL`), which the library keeps in `_Downloads`.
enum VirtualBuddyLibrary {
    /// The images the library's machines were installed from, or nil when a machine's record can't be read, since an
    /// image is then not known to be unused.
    static func imagesInUse(in library: URL) -> Set<String>? {
        let path = library.path(percentEncoded: false)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return nil }
        var images: Set<String> = []
        for name in names where name.lowercased().hasSuffix(".vbvm") {
            let record = library.appending(path: "\(name)/.vbdata/Metadata.plist")
            guard let data = BoundedRead.data(at: record),
                  let metadata = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { return nil }
            if let image = (metadata["installImageURL"] as? [String: Any])?["relative"] as? String,
               let url = URL(string: image), url.isFileURL {
                images.insert(PathPattern.comparablePath(of: url))
            }
        }
        return images
    }
}
