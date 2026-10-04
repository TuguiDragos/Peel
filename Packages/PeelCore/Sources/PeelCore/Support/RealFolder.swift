import Foundation

extension URL {
    /// True when something is there under this name, a link that leads nowhere included. `fileExists` follows
    /// links, so it calls such a link missing, and a relative link often leads nowhere once it is in the Trash.
    var isThere: Bool {
        var info = stat()
        return lstat(path(percentEncoded: false), &info) == 0
    }

    /// True only when nothing is there under this name. A name macOS cannot look up, as in a folder that cannot be
    /// searched, is not missing, so one of Peel's files it cannot reach is never read as one that is not there.
    var isMissing: Bool {
        var info = stat()
        return lstat(path(percentEncoded: false), &info) != 0 && errno == ENOENT
    }

    /// True for a folder that is there in its own right: a symbolic link to one does not count.
    var isRealFolder: Bool {
        let values = try? resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }

    /// Whether the item is stored in the cloud, as `isUbiquitousItem` reports. With Desktop and Documents in iCloud,
    /// their files are cloud items even though their paths are in the home folder, and removing one removes it
    /// from every device.
    var isInTheCloud: Bool {
        (try? resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
    }

    /// Whether this is a package, such as an app.
    var isAPackage: Bool {
        (try? resourceValues(forKeys: [.isPackageKey]).isPackage) == true
    }

    /// The outermost package this sits inside, such as the app around a helper app, or nil when none encloses it.
    var enclosingPackage: URL? {
        var found: URL?
        var folder = standardizedFileURL.deletingLastPathComponent()
        while folder.pathComponents.count > 1 {
            if folder.isAPackage { found = folder }
            folder = folder.deletingLastPathComponent()
        }
        return found
    }

    /// Whether this is a package or sits inside one. What is inside a package belongs to it.
    var isOrIsInsideAPackage: Bool {
        var folder = standardizedFileURL
        while folder.pathComponents.count > 1 {
            if folder.isAPackage { return true }
            folder = folder.deletingLastPathComponent()
        }
        return false
    }
}
