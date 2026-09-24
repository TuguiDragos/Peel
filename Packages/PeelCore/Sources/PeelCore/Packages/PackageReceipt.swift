public import Foundation

/// The result of one scan of the installed packages. `couldNotAsk` is set when `pkgutil` gave no answer, which
/// is not the same as finding no packages.
public struct PackageScan: Sendable {
    public var receipts: [PackageReceipt] = []
    public var couldNotAsk = false
}

public struct PackageReceipt: Sendable, Hashable, Identifiable {
    public struct Item: Sendable, Hashable, Identifiable {
        public let url: URL
        /// Nil when the size is not known: the item did not answer in time, or macOS would not let Peel open it.
        /// Unknown is not the same as empty.
        public let size: Int64?
        public let requiresPrivileges: Bool
        /// True when Peel never moves this item: `RemovalGuard` refuses it (a file in `/usr/local/bin`, for
        /// example), or it needs an administrator and the helper would refuse it. It is listed but never offered.
        public var isLeftAlone = false

        public var id: URL { url }
    }

    public let identifier: String
    public let version: String?
    public let installDate: Date?
    /// The volume the package was installed to, which is where its receipt is kept.
    public let volume: URL
    public let items: [Item]
    /// True when the file list is known and nothing on it is still on disk. This is judged from the disk, not
    /// from `items`, which leaves out what is excluded or protected even while it is still there.
    public var nothingLeftOnDisk = false
    /// False when `pkgutil` did not say what the package installed, because it failed or ran out of time.
    /// Nothing can then be said about what is left, and an empty list is not "nothing left".
    public var isFileListKnown = true

    public var id: String { identifier }

    /// Unknown when the file list is, since an empty list then says nothing about what is left.
    public var total: SizeTotal {
        isFileListKnown ? SizeTotal(items.map(\.size)) : SizeTotal(known: 0, isComplete: false)
    }

    /// True when the package still has files on disk but none of them can be moved: each is excluded, protected,
    /// or left alone. False when the file list is unknown, since then nothing is known about what is left.
    public var holdsNothingToRemove: Bool {
        isFileListKnown && !nothingLeftOnDisk && items.allSatisfy(\.isLeftAlone)
    }
}
