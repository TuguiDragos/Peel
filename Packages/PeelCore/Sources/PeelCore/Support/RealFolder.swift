public import Foundation
internal import PeelPrivileged

extension URL {
    /// True when something is there under this name, a link that leads nowhere included. `fileExists` follows
    /// links, so it calls such a link missing, and a relative link often leads nowhere once it is in the Trash.
    var isThere: Bool {
        var info = stat()
        return lstat(path(percentEncoded: false), &info) == 0
    }

    /// `lstat` follows a link named with a slash after it, as a URL marked as a directory is.
    var isSymbolicLink: Bool {
        var info = stat()
        return lstat(PathPattern.comparablePath(of: self), &info) == 0 && info.st_mode & S_IFMT == S_IFLNK
    }

    /// True for a link whose destination isn't there, as on a disk that isn't connected.
    var isALinkThatLeadsNowhere: Bool {
        var info = stat()
        return isSymbolicLink && stat(path(percentEncoded: false), &info) != 0 && errno == ENOENT
    }

    /// True only when nothing is there under this name. A name macOS cannot look up, as in a folder that cannot be
    /// searched, is not missing, so one of Peel's files it cannot reach is never read as one that is not there.
    public var isMissing: Bool {
        var info = stat()
        return lstat(path(percentEncoded: false), &info) != 0 && errno == ENOENT
    }

    /// True for a path on a disk under `/Volumes` that is not connected, where nothing can be told about what it holds.
    var isOnADiskNotConnected: Bool {
        let names = PathComponents.of(path(percentEncoded: false))
        return names.count > 2 && names[0] == "Volumes" && URL(filePath: "/Volumes/\(names[1])").isMissing
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

    /// True for a kernel extension, which macOS takes out of the kernel only when the Mac restarts: since macOS 11,
    /// third-party kernel extensions load as one collection when the Mac starts up.
    public var isKernelExtension: Bool {
        pathExtension.caseInsensitiveCompare("kext") == .orderedSame
    }

    /// Where a link or a Finder alias here leads: a link read without following it, an alias resolved with nothing
    /// mounted or asked, since it follows a target that moved, or else the place it noted, whose target is gone.
    var leadsTo: URL? {
        let path = path(percentEncoded: false)
        if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: path) {
            return URL(filePath: destination, relativeTo: deletingLastPathComponent()).standardizedFileURL
        }
        guard (try? resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) == true,
              let data = try? URL.bookmarkData(withContentsOf: self)
        else { return nil }
        var isStale = false
        if let target = try? URL(
            resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &isStale
        ) {
            return target.standardizedFileURL
        }
        return URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: data)?.path.map {
            URL(filePath: $0).standardizedFileURL
        }
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
