import Foundation

extension URL {
    /// True when something is there under this name, a link that leads nowhere included. `fileExists` follows
    /// links, so it calls such a link missing, and a relative link often leads nowhere once it is in the Trash.
    var isThere: Bool {
        var info = stat()
        return lstat(path(percentEncoded: false), &info) == 0
    }

    /// True for a folder that is there in its own right: a symbolic link to one does not count.
    var isRealFolder: Bool {
        let values = try? resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }
}
