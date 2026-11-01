public import Foundation
internal import CoreServices

/// Marks a folder for Time Machine to skip, such as one a build makes again, and reads or clears that mark.
/// The mark sits on the folder itself rather than on its path, so it moves with the folder, goes away with
/// it, and needs no administrator rights.
///
/// It uses `CSBackupSetItemExcluded`, Apple's API for this, rather than `tmutil addexclusion`, which is slow
/// and fails in a process that macOS hasn't given Full Disk Access.
public enum TimeMachineExclusion {
    /// Written beside the mark Peel puts, since the mark itself says nothing of who put it.
    private static let ownMark = "com.tuguidragos.Peel.backupMark"

    /// Whether Time Machine backs up a folder, and if not, where the exclusion comes from. Per `BackupCore.h`,
    /// `CSBackupIsItemExcluded` answers true "if the item or any of its ancestors are excluded" and says
    /// whether the exclusion is by path. Only a mark on the folder itself can be taken off from here.
    public enum Standing: Sendable, Hashable {
        case included
        /// The mark is on this folder, and nothing says who put it: a tool, as Poetry marks each environment it makes
        /// and Xcode its DerivedData, the person, or a version of Peel that didn't say.
        case excludedItself
        /// The mark is on this folder, and Peel put it.
        case markedByPeel
        /// A folder above it is excluded, or the exclusion is on the path rather than on this folder.
        case excludedFromAbove
    }

    public static func standing(of url: URL) -> Standing {
        var byPath: DarwinBoolean = false
        guard CSBackupIsItemExcluded(url as CFURL, &byPath) else { return .included }
        // An exclusion by path is not this folder's own mark, and neither is one its parent folder also has.
        guard !byPath.boolValue, !CSBackupIsItemExcluded(url.deletingLastPathComponent() as CFURL, nil) else {
            return .excludedFromAbove
        }
        return getxattr(url.path(percentEncoded: false), ownMark, nil, 0, 0, XATTR_NOFOLLOW) >= 0
            ? .markedByPeel : .excludedItself
    }

    public static func isExcluded(_ url: URL) -> Bool {
        standing(of: url) != .included
    }

    /// Returns the standing of each folder, worked out off the caller's actor: each answer takes up to two
    /// calls into `BackupCore`, and a page can ask about hundreds of folders at once.
    @concurrent
    public static func standings(of urls: [URL]) async -> [URL: Standing] {
        Dictionary(urls.map { ($0, standing(of: $0)) }, uniquingKeysWith: { first, _ in first })
    }

    public static func excluded(among urls: [URL]) -> Set<URL> {
        Set(urls.filter(isExcluded))
    }

    /// `setExcluded(_:_:)` away from the caller's thread, since on a network volume a mark can take its time.
    @concurrent
    public static func marking(_ isExcluded: Bool, _ urls: [URL]) async -> Set<URL> {
        setExcluded(isExcluded, urls)
    }

    /// Sets or clears the mark on each folder and returns the folders that could not be changed. A folder
    /// that refuses the mark, such as one owned by root, does not stop the others.
    public static func setExcluded(_ isExcluded: Bool, _ urls: [URL]) -> Set<URL> {
        Set(urls.filter { url in
            guard CSBackupSetItemExcluded(url as CFURL, isExcluded, false) == noErr else { return true }
            let path = url.path(percentEncoded: false)
            if isExcluded {
                _ = setxattr(path, ownMark, "1", 1, 0, XATTR_NOFOLLOW)
            } else {
                _ = removexattr(path, ownMark, XATTR_NOFOLLOW)
            }
            return false
        })
    }
}
