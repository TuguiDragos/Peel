public import Foundation

public struct DuplicateScanOptions: Sendable, Hashable {
    /// The smallest copy Peel looks for unless another size is chosen, in the app and in `peel duplicates` alike.
    public static let defaultMinimumSize: Int64 = 100_000

    public var folders: [URL]
    public var kind = FileKind.any
    /// The fewest bytes a file holds, or a folder holds in all, to be compared. Never less than one: a copy of
    /// nothing frees nothing.
    public var minimumSize = defaultMinimumSize {
        didSet { minimumSize = max(1, minimumSize) }
    }

    public init(folders: [URL]) {
        self.folders = folders
    }
}

public enum DuplicateScanProgress: Sendable, Hashable {
    case listing(foldersFound: Int)
    case collecting(filesFound: Int)
    case comparing(filesCompared: Int, filesToCompare: Int)
    case verifying(bytesRead: Int64, bytesToRead: Int64)
}

public struct DuplicateFile: Sendable, Hashable, Identifiable {
    public let url: URL
    public let size: Int64
    /// The bytes removing it would free: less than `size` for a hard link, an APFS clone, a file kept by a
    /// snapshot, or a compressed or sparse file.
    public let reclaimableSize: Int64
    /// The space it takes on disk, less than `size` when it is compressed or sparse. Compared with
    /// `reclaimableSize`, it shows whether the file really shares blocks with something else.
    public let allocatedSize: Int64

    /// Removing it frees less than it takes, because something else holds the same blocks.
    public var sharesStorage: Bool {
        reclaimableSize < allocatedSize
    }
    let identity: FileIdentity

    public var id: URL { url }

    public var modificationDate: Date {
        identity.modificationDate
    }
}

public struct DuplicateGroup: Sendable, Hashable, Identifiable {
    /// The SHA-256 of the contents.
    public let id: String
    /// Identical files, the suggested one to keep first.
    public let files: [DuplicateFile]

    public var size: Int64 {
        files.first?.size ?? 0
    }

    public var reclaimableSize: Int64 {
        files.dropFirst().reduce(0) { $0 + $1.reclaimableSize }
    }
}

public struct DuplicateFolder: Sendable, Hashable, Identifiable {
    public let url: URL
    public let fileCount: Int
    public let size: Int64
    /// The bytes removing it would free, counted file by file as for a `DuplicateFile`.
    public let reclaimableSize: Int64
    /// A digest of every entry's name and file identity when scanned, checked again before the move so a folder
    /// that changed since is refused.
    let contents: String
    /// The folders the scan never took for projects (`DuplicateFinder.neverProjects`), so the check before the
    /// move lists the folder the same way.
    let neverProjects: Set<String>

    public var id: URL { url }
}

public struct DuplicateFolderGroup: Sendable, Hashable, Identifiable {
    /// A SHA-256 of the names and contents of everything in the folders.
    public let id: String
    /// Folders holding identical contents, the suggested one to keep first.
    public let folders: [DuplicateFolder]

    public var size: Int64 {
        folders.first?.size ?? 0
    }

    public var fileCount: Int {
        folders.first?.fileCount ?? 0
    }

    public var reclaimableSize: Int64 {
        folders.dropFirst().reduce(0) { $0 + $1.reclaimableSize }
    }

    public func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return folders.contains { SearchText.matches($0.url.path(percentEncoded: false), query) }
    }
}

public struct DuplicateScan: Sendable {
    public let groups: [DuplicateGroup]
    /// A file inside one of these is never listed in `groups` as well.
    public var folderGroups: [DuplicateFolderGroup] = []
    public let unreadableLocations: [URL]
    /// Chosen folders that were not scanned, such as iCloud Drive, app data, system folders, and repositories.
    public var skippedLocations: [URL] = []
    /// True when macOS privacy protection refused one of the unreadable folders, which Full Disk Access would
    /// allow. It stays false for a folder locked by ordinary permissions, or one that is missing.
    public var needsFullDiskAccess = false

    /// The folders Peel could not read or skipped, where duplicates may still be, whatever else it found.
    public var notLookedIn: [URL] {
        unreadableLocations + skippedLocations
    }

    /// True when no duplicates were found but some of what was asked for could not be read or was skipped, even
    /// one locked folder at any depth. Duplicates may then exist where Peel could not look.
    public var readNothing: Bool {
        groups.isEmpty && folderGroups.isEmpty && !notLookedIn.isEmpty
    }

    /// Every file except the suggested one to keep in each group.
    public var suggestedSelection: Set<URL> {
        Set(groups.flatMap { $0.files.dropFirst().map(\.url) })
    }

    public var suggestedFolderSelection: Set<URL> {
        Set(folderGroups.flatMap { $0.folders.dropFirst().map(\.url) })
    }

    /// What a scan run under `exclusions` would have left out: every copy or folder that is excluded or sits
    /// inside something excluded, and every folder that holds something excluded. It runs off the caller's actor,
    /// since each check resolves links on disk and a scan can list a hundred thousand copies.
    @concurrent
    public func excluded(by exclusions: Exclusions) async -> Set<URL> {
        guard !exclusions.paths.isEmpty else { return [] }
        let files = groups.flatMap(\.files).map(\.url).filter(exclusions.excludes)
        let folders = folderGroups.flatMap(\.folders).map(\.url).filter {
            exclusions.excludes($0) || exclusions.holds($0)
        }
        return Set(files + folders)
    }

    /// Returns `selection` limited to what this scan can still move: only files it lists, and never every copy of
    /// a group, which the move refuses. When every copy left in a group is selected, its first copy is kept.
    public func keepingOneOfEach(_ selection: Set<URL>) -> Set<URL> {
        Self.keepingOne(of: groups.map { $0.files.map(\.url) }, selection)
    }

    public func keepingOneOfEachFolder(_ selection: Set<URL>) -> Set<URL> {
        Self.keepingOne(of: folderGroups.map { $0.folders.map(\.url) }, selection)
    }

    /// Whether the copy at `url` may be selected or deselected, given the `selected` copies of its group: one copy of
    /// every group always stays, so the last one not selected cannot be.
    public static func canChange(_ url: URL, among copies: [URL], selected: Set<URL>) -> Bool {
        selected.contains(url) || copies.count { !selected.contains($0) } > 1
    }

    private static func keepingOne(of groups: [[URL]], _ selection: Set<URL>) -> Set<URL> {
        Set(groups.flatMap { copies in
            let chosen = copies.filter(selection.contains)
            return chosen.count == copies.count ? Array(chosen.dropFirst()) : chosen
        })
    }

    public func removing(_ urls: Set<URL>) -> DuplicateScan {
        let remaining = groups.compactMap { group -> DuplicateGroup? in
            let files = group.files.filter { !urls.contains($0.url) }
            return files.count > 1 ? DuplicateGroup(id: group.id, files: files) : nil
        }
        let remainingFolders = folderGroups.compactMap { group -> DuplicateFolderGroup? in
            let folders = group.folders.filter { !urls.contains($0.url) }
            return folders.count > 1 ? DuplicateFolderGroup(id: group.id, folders: folders) : nil
        }
        return DuplicateScan(
            groups: remaining,
            folderGroups: remainingFolders,
            unreadableLocations: unreadableLocations,
            skippedLocations: skippedLocations,
            needsFullDiskAccess: needsFullDiskAccess
        )
    }
}

extension DuplicateGroup {
    /// True when the path of any copy matches `query`, not only the copy the row shows, so a search finds a file
    /// wherever it sits in the group.
    public func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        // Only the path is searched: it already holds the name, and this runs on every keystroke.
        return files.contains { SearchText.matches($0.url.path(percentEncoded: false), query) }
    }
}
