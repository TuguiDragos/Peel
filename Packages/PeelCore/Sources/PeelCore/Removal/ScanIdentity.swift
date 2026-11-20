import Darwin
public import Foundation

/// An item as a scan found it. A move needs the same kind, and the same folder or link; a file may be a new one,
/// since an app saves a file by putting a new one in its place.
public struct ScanIdentity: Sendable, Hashable {
    private let identity: TrashedItem.Identity
    private let type: mode_t

    init?(ofItemAt url: URL) {
        var info = stat()
        guard lstat(url.path(percentEncoded: false), &info) == 0, let identity = TrashedItem.Identity(ofItemAt: url)
        else { return nil }
        self.identity = identity
        type = info.st_mode & S_IFMT
    }

    func isStill(_ info: stat) -> Bool {
        guard info.st_mode & S_IFMT == type else { return false }
        return type == S_IFREG || identity.isTheItem(info)
    }
}

/// What a scan found, checked again right before it moves (`TrashService.refusingWhatChangedSinceTheScan`).
public protocol FoundByAScan {
    var url: URL { get }
    var foundBelow: URL? { get }
    var scanIdentity: ScanIdentity? { get }
}
