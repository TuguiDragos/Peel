public import Foundation

/// Whether only some accounts can change what a path names, which is what a program running as root may trust.
public enum ClosedChain {
    /// True when `url` and every folder above it, and what it leads to through links and every folder above that,
    /// belong to `owners` and are closed to everyone else: a link says nothing of its target.
    public static func isClosed(_ url: URL, toAllBut owners: Set<uid_t>) -> Bool {
        let named = URL(filePath: url.path(percentEncoded: false)).standardizedFileURL
        guard let real = realpath(named.path(percentEncoded: false), nil) else { return false }
        defer { free(real) }
        let target = URL(filePath: String(cString: real))
        return chain(of: named, isClosedToAllBut: owners)
            && (target.path(percentEncoded: false) == named.path(percentEncoded: false)
                || chain(of: target, isClosedToAllBut: owners))
    }

    private static func chain(of url: URL, isClosedToAllBut owners: Set<uid_t>) -> Bool {
        var path = url
        while true {
            var info = stat()
            guard lstat(path.path(percentEncoded: false), &info) == 0, owners.contains(info.st_uid),
                  info.st_mode & (S_IWGRP | S_IWOTH) == 0
            else { return false }
            guard path.pathComponents.count > 1 else { return true }
            path = path.deletingLastPathComponent()
        }
    }
}
