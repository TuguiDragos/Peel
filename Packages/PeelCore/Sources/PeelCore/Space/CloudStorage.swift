public import Foundation
import Synchronization
internal import PeelPrivileged

/// A file in iCloud Drive, or a document saved as a package, that also has a local copy. Freeing the local copy
/// deletes nothing: the file stays in iCloud, Finder still shows it, and it downloads again when it is opened. So
/// freeing does not go through the Trash, since there is nothing to put back.
public struct CloudFile: Sendable, Hashable, Identifiable {
    public let url: URL
    public let name: String
    /// The folder under `Mobile Documents` it belongs to, in readable form: "iCloud Drive", "Pages".
    public let container: String
    /// What removing the local copy frees: less than the file's length when it is stored compressed, and nothing
    /// when a clone shares its blocks.
    public let size: Int64
    public let modified: Date?
    /// The picture on one of the displays' desktop, which macOS keeps open while it is shown, so its download cannot be
    /// removed then.
    public var isDesktopPicture = false
    /// Why Peel doesn't recommend removing this download, or nil.
    public var heldBack: HoldBack?

    public var id: URL { url }

    public var isRecommended: Bool {
        !isDesktopPicture && heldBack == nil
    }
}

/// What one scan of iCloud Drive found, and whether the scan stopped early or could not read the folder.
public struct CloudScan: Sendable {
    public var files: [CloudFile] = []
    /// Why the list isn't all there is, and nil when it is.
    public var cutShort: CutShort?
    /// iCloud Drive could not be read at all, which is what happens without Full Disk Access.
    public var couldNotRead = false
    /// How many downloads were left out because another copy on this Mac shares their space: each takes at least
    /// `CloudStorage.minimumSize` on disk, yet removing it would free less.
    public var sharedDownloads = 0
    public var folders: [CloudFolder] = []
    /// iCloud Drive was never set up for this account: the folder iCloud keeps in the home isn't there.
    public var isNotSetUp = false

    public enum CutShort: Sendable, Equatable {
        /// The walk ran out of time or was stopped before it read everything.
        case ranOutOfTime
        /// The walk read everything and kept the biggest files, `CloudStorage.maximumFiles` of them.
        case listIsFull
    }
}

/// A file that was not freed, and why.
public struct CloudRefusal: Sendable, Hashable, Identifiable {
    public enum Reason: Sendable, Hashable {
        /// The file is not as it was at the scan: edited, moved, or freed already, or not safely in iCloud.
        case changedSinceScan
        /// Excluded in Settings since the scan, or the exclusions are not known, so it is left as a move to the
        /// Trash would be.
        case excluded
        /// A program holds the file, as the wallpaper is held, so macOS could not lock it to free its copy.
        case inUse
        /// macOS refused to free the file. The value is the error message it gave.
        case failed(String)
    }

    public let url: URL
    public let reason: Reason

    public var id: URL { url }
}

/// What freeing the local copies did.
public struct CloudFreeing: Sendable {
    public var freed: [CloudFile] = []
    public var refused: [CloudRefusal] = []
}

public enum CloudStorage {
    /// A file that frees less than this isn't worth a row in a list about space.
    public static let minimumSize: Int64 = 1_000_000
    /// The most files listed. The walk goes on past it, keeping the biggest files it finds, so a big file read late
    /// is not left out for smaller ones read first.
    public static let maximumFiles = 5_000
    /// How long the walk may take, in seconds. A folder iCloud manages can stall a directory read for minutes,
    /// and this walk also reads the sync state of every file.
    public static let budget: TimeInterval = 20

    /// True only for a file whose local copy is current and already safely in iCloud. A file not yet uploaded,
    /// in conflict, with sync paused, or with an upload error is left alone: freeing it could remove the only copy.
    static func isSafeToFree(
        status: URLUbiquitousItemDownloadingStatus?,
        isUploaded: Bool?,
        isUploading: Bool?,
        hasConflicts: Bool?,
        isSyncPaused: Bool? = nil,
        uploadingError: (any Error)? = nil
    ) -> Bool {
        status == .current && isUploaded == true && isUploading != true && hasConflicts != true
            && isSyncPaused != true && uploadingError == nil
    }

    /// The resource keys read for each file, by the scan and again by `free(_:)`.
    static let keys: Set<URLResourceKey> = [
        .isRegularFileKey, .isPackageKey, .contentModificationDateKey, .ubiquitousItemDownloadingStatusKey,
        .ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey, .ubiquitousItemHasUnresolvedConflictsKey,
        .ubiquitousItemIsSyncPausedKey, .ubiquitousItemUploadingErrorKey,
    ]

    static func isSafeToFree(_ values: URLResourceValues) -> Bool {
        isSafeToFree(
            status: values.ubiquitousItemDownloadingStatus,
            isUploaded: values.ubiquitousItemIsUploaded,
            isUploading: values.ubiquitousItemIsUploading,
            hasConflicts: values.ubiquitousItemHasUnresolvedConflicts,
            isSyncPaused: values.ubiquitousItemIsSyncPaused,
            uploadingError: values.ubiquitousItemUploadingError
        )
    }

    @concurrent
    public static func downloaded(
        home: URL = .homeDirectory,
        minimumSize: Int64 = CloudStorage.minimumSize,
        exclusions: Exclusions = .none,
        desktopPictures: Set<URL> = [],
        within budget: TimeInterval = CloudStorage.budget
    ) async -> CloudScan {
        await downloaded(
            home: home, minimumSize: minimumSize, exclusions: exclusions, desktopPictures: desktopPictures,
            within: budget, isDataless: FileSize.isDataless(_:)
        )
    }

    @concurrent
    static func downloaded(
        home: URL,
        minimumSize: Int64,
        exclusions: Exclusions,
        desktopPictures: Set<URL>,
        within budget: TimeInterval,
        isDataless: @escaping @Sendable (URL) -> Bool
    ) async -> CloudScan {
        let collector = Collector()
        let scan = ScanCount.current
        let finished = await SlowRead.answer(within: budget) { isGivenUp in
            collect(
                home: home,
                minimumSize: minimumSize,
                exclusions: exclusions,
                desktopPictures: desktopPictures,
                into: collector,
                deadline: .now + .seconds(budget),
                countingFor: scan,
                isDataless: isDataless,
                unless: isGivenUp
            )
            return true
        }
        let collected = collector.collected
        return CloudScan(
            files: collected.files.sorted { $0.size > $1.size },
            cutShort: finished == nil ? .ranOutOfTime : collected.cutShort,
            couldNotRead: collected.couldNotRead,
            sharedDownloads: collected.sharedDownloads,
            folders: folders(of: collected.files, home: home),
            isNotSetUp: !isSetUp(home: home)
        )
    }

    /// What the walk has gathered so far, written by the thread that walks and read once it stops or the
    /// budget runs out.
    final class Collector: Sendable {
        struct Collected {
            var files: [CloudFile] = []
            var cutShort: CloudScan.CutShort?
            var couldNotRead = false
            var sharedDownloads = 0
        }

        private let state = Mutex(Collected())
        private let maximum: Int

        init(maximum: Int = CloudStorage.maximumFiles) {
            self.maximum = maximum
        }

        var collected: Collected { state.withLock { $0 } }

        /// Adds `file` to the list. Once the list is full, `file` takes the place of the smallest one when it is
        /// bigger, and the list says it is not all there is. The list is a min heap by size, so the smallest is
        /// always first.
        func add(_ file: CloudFile) {
            state.withLock { collected in
                if collected.files.count < maximum {
                    collected.files.append(file)
                    Self.siftUp(&collected.files, from: collected.files.count - 1)
                    return
                }
                if collected.cutShort == nil { collected.cutShort = .listIsFull }
                guard let smallest = collected.files.first, file.size > smallest.size else { return }
                collected.files[0] = file
                Self.siftDown(&collected.files, from: 0)
            }
        }

        private static func siftUp(_ files: inout [CloudFile], from start: Int) {
            var child = start
            while child > 0 {
                let parent = (child - 1) / 2
                guard files[child].size < files[parent].size else { return }
                files.swapAt(child, parent)
                child = parent
            }
        }

        private static func siftDown(_ files: inout [CloudFile], from start: Int) {
            var parent = start
            while true {
                let left = 2 * parent + 1, right = left + 1
                var smallest = parent
                if left < files.count, files[left].size < files[smallest].size { smallest = left }
                if right < files.count, files[right].size < files[smallest].size { smallest = right }
                guard smallest != parent else { return }
                files.swapAt(parent, smallest)
                parent = smallest
            }
        }

        func ranOutOfTime() {
            state.withLock { $0.cutShort = .ranOutOfTime }
        }

        func unreadable() {
            state.withLock { $0.couldNotRead = true }
        }

        func leftOutAsShared() {
            state.withLock { $0.sharedDownloads += 1 }
        }
    }

    /// Walks iCloud Drive and adds each file worth freeing to `collector`. Stops at `deadline` as well as when
    /// `isGivenUp` says so, because the timer behind `isGivenUp` runs on another thread and can fire late on a
    /// busy Mac. Only iCloud can say a file is safely there, so a test says it through `isSafe`.
    static func collect(
        home: URL,
        minimumSize: Int64,
        exclusions: Exclusions,
        desktopPictures: Set<URL> = [],
        into collector: Collector,
        deadline: ContinuousClock.Instant,
        countingFor scan: ScanCount?,
        isSafe: (URLResourceValues) -> Bool = isSafeToFree(_:),
        isPinned: (URL) -> Bool = isPinned(_:),
        isDataless: (URL) -> Bool = FileSize.isDataless(_:),
        unless isGivenUp: () -> Bool
    ) {
        let root = home.appending(path: "Library/Mobile Documents", directoryHint: .isDirectory)
        let rootPath = PathPattern.comparablePath(of: root)
        let pictures = Set(desktopPictures.map(PathPattern.comparablePath))
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, error in
                // Only an error on the root counts: without Full Disk Access nothing under it can be read. A
                // missing root (`NSFileReadNoSuchFileError`) means iCloud Drive was never set up, which is
                // nothing to list rather than a refusal.
                let isMissing =
                    (error as NSError).domain == NSCocoaErrorDomain
                    && (error as NSError).code == NSFileReadNoSuchFileError
                if PathPattern.comparablePath(of: url) == rootPath, !isMissing { collector.unreadable() }
                return true
            }
        ) else {
            collector.unreadable()
            return
        }

        // The budget is spent, or the page that asked was left or stopped.
        func stopped() -> Bool { ContinuousClock.now >= deadline || isGivenUp() }
        func key(_ url: URL) -> String {
            let path = url.path(percentEncoded: false)
            return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        }
        var container = ""
        var isICloudDrive = false
        // The folders Keep Downloaded is on for, itself or through a folder above.
        var pinnedFolders: Set<String> = []
        for case let url as URL in enumerator {
            guard !stopped() else {
                collector.ranOutOfTime()
                return
            }
            scan?.add(1)
            // Each folder directly in Mobile Documents is one container, named once for everything inside it.
            if enumerator.level == 1 {
                container = containerName(of: url, under: root)
                isICloudDrive = url.lastPathComponent == "com~apple~CloudDocs"
            }
            // Of an app's container Finder shows only `Documents`; the rest is the app's own data.
            let isAppsOwnData = enumerator.level == 2 && !isICloudDrive
                && url.lastPathComponent.caseInsensitiveCompare("Documents") != .orderedSame
            if isAppsOwnData || exclusions.excludes(url) || isDataless(url) {
                // `skipDescendants()` after a file would skip the next folder.
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            let isInAPinnedFolder = pinnedFolders.contains(key(url.deletingLastPathComponent()))
            guard values.isRegularFile == true || values.isPackage == true else {
                if isInAPinnedFolder || isPinned(url) { pinnedFolders.insert(key(url)) }
                continue
            }
            guard isSafe(values) else { continue }
            let measured = values.isRegularFile == true
                ? (
                    size: ReclaimableSpace.of(url), taken: ReclaimableSpace.allocated(url),
                    modified: values.contentModificationDate
                )
                : package(url, values, exclusions: exclusions, countingFor: scan, unless: stopped)
            guard let measured else {
                if stopped() {
                    collector.ranOutOfTime()
                    return
                }
                continue
            }
            guard measured.size >= minimumSize else {
                if measured.taken >= minimumSize { collector.leftOutAsShared() }
                continue
            }

            let file = CloudFile(
                url: url,
                name: shownName(of: url),
                container: container,
                size: measured.size,
                modified: measured.modified,
                isDesktopPicture: pictures.contains(PathPattern.comparablePath(of: url)),
                heldBack: isInAPinnedFolder || isPinned(url) ? .keptDownloaded
                    : holdsSecrets(url, below: root) ? .opensOnlyOnline
                    : isICloudDrive ? nil : .inAnAppsICloudFolder
            )
            collector.add(file)
        }
    }

    /// Whether iCloud Drive was ever set up for the account of `home`: iCloud makes `~/Library/Mobile Documents` then.
    public static func isSetUp(home: URL = .homeDirectory) -> Bool {
        home.appending(path: "Library/Mobile Documents", directoryHint: .isDirectory).isRealFolder
    }

    /// Whether `url`, or a folder it sits in below `root`, is named as a password database or a wallet's keys are.
    static func holdsSecrets(_ url: URL, below root: URL) -> Bool {
        let names = PathComponents.of(url.path(percentEncoded: false))
            .dropFirst(PathComponents.of(root.path(percentEncoded: false)).count)
        return names.contains { FileSize.isPasswordDatabase($0) || FileSize.isWallet($0) }
    }

    /// Whether Keep Downloaded is on for `url` in Finder: FileProvider keeps it as the extended attribute
    /// `com.apple.fileprovider.pinned`, whose stored name carries flags after a `#` (`xattr_name_with_flags(3)`).
    static func isPinned(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        let size = listxattr(path, nil, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return false }
        var names = [CChar](repeating: 0, count: size)
        guard listxattr(path, &names, size, XATTR_NOFOLLOW) == size else { return false }
        let pinned = "com.apple.fileprovider.pinned"
        return names.split(separator: 0).contains { name in
            let text = String(decoding: name.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            return text == pinned || text.hasPrefix(pinned + "#")
        }
    }

    /// Frees the local copies of `files`, one at a time. Each file is checked again first, against `exclusions` as
    /// they are now as well: the list may have been on screen for hours, and a file edited since then may exist in
    /// its newest form only on the local disk.
    @discardableResult
    @concurrent
    public static func free(_ files: [CloudFile], exclusions: Exclusions) async -> CloudFreeing {
        await free(files, exclusions: exclusions, isSafe: isSafeToFree(_:))
    }

    @concurrent
    static func free(
        _ files: [CloudFile],
        exclusions: Exclusions,
        isSafe: (URLResourceValues) -> Bool,
        evict: (URL) throws -> Void = { try FileManager.default.evictUbiquitousItem(at: $0) }
    ) async -> CloudFreeing {
        var done = CloudFreeing()
        for file in files {
            // A stop lets the file iCloud is answering for finish, and nothing after it starts.
            if Task.isCancelled { break }
            guard exclusions.isKnown, !exclusions.excludes(file.url) else {
                done.refused.append(CloudRefusal(url: file.url, reason: .excluded))
                continue
            }
            var url = file.url
            url.removeAllCachedResourceValues()
            guard let values = try? url.resourceValues(forKeys: keys), isSafe(values) else {
                done.refused.append(CloudRefusal(url: file.url, reason: .changedSinceScan))
                continue
            }
            if values.isPackage == true, exclusions.holds(url) {
                done.refused.append(CloudRefusal(url: file.url, reason: .excluded))
                continue
            }
            let modified: Date? = if values.isRegularFile == true {
                values.contentModificationDate
            } else if values.isPackage == true {
                package(url, values, exclusions: exclusions, unless: { false })?.modified
            } else {
                nil
            }
            // A date that can't be read, now or at the scan, never says the file is as it was.
            guard let modified, modified == file.modified else {
                done.refused.append(CloudRefusal(url: file.url, reason: .changedSinceScan))
                continue
            }
            do {
                try evict(file.url)
                done.freed.append(file)
                MoveCount.current?.add(1)
            } catch {
                done.refused.append(CloudRefusal(url: file.url, reason: reason(for: error)))
            }
        }
        return done
    }

    /// The name Finder shows. An app is named as `AppInspector` names it, since asking the system for the name of
    /// an app Launch Services doesn't know there registers it.
    static func shownName(of url: URL) -> String {
        url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
            ? AppInspector.displayName(of: url)
            : FileManager.default.displayName(atPath: url.path(percentEncoded: false))
    }

    /// Why freeing a file failed: `NSFileLockingError` when a program holds it, and macOS's own message otherwise.
    static func reason(for error: any Error) -> CloudRefusal.Reason {
        (error as? CocoaError)?.code == .fileLocking ? .inUse : .failed(error.localizedDescription)
    }

    /// A document saved as a package, which iCloud keeps as one item: what removing its download frees, what it takes
    /// on disk, and the newest date of anything inside, since editing a file inside leaves the package's own date as
    /// it was. Nil for a package with something excluded inside, one that could not be read whole, or a walk that
    /// was stopped.
    static func package(
        _ url: URL,
        _ values: URLResourceValues,
        exclusions: Exclusions,
        countingFor scan: ScanCount? = nil,
        unless isStopped: () -> Bool
    ) -> (size: Int64, taken: Int64, modified: Date?)? {
        guard !exclusions.holds(url), let contents = FileSize.walk(url, countingFor: scan, unless: isStopped),
              !contents.couldNotBeRead
        else { return nil }
        let modified = [values.contentModificationDate, contents.newestChange].compactMap(\.self).max()
        return (contents.size, contents.taken, modified)
    }

    /// "iCloud Drive" for `com~apple~CloudDocs`; for an app's folder the name macOS shows, else the identifier's last
    /// part, so `iCloud~com~acme~App` reads "App".
    static func containerName(of url: URL, under root: URL) -> String {
        let rootNames = PathComponents.of(PathPattern.comparablePath(of: root))
        let names = PathComponents.of(PathPattern.comparablePath(of: url))
        guard names.count > rootNames.count, names.starts(with: rootNames) else { return "" }
        let folder = names[rootNames.count]

        if folder == "com~apple~CloudDocs" {
            // Finder's name for the folder, in the user's language (iCloud云盘 in Simplified Chinese), for search.
            let shown = FileManager.default.displayName(
                atPath: root.appending(path: folder).path(percentEncoded: false)
            )
            return shown == folder ? "iCloud Drive" : shown
        }
        let container = root.appending(path: folder, directoryHint: .isDirectory)
        if let shown = try? container.resourceValues(forKeys: [.ubiquitousItemContainerDisplayNameKey])
            .ubiquitousItemContainerDisplayName, !shown.isEmpty {
            return shown
        }
        var name = folder.replacingOccurrences(of: "~", with: ".")
        if let range = name.range(of: "iCloud.") { name = String(name[range.upperBound...]) }
        // Only the last part is kept. The rest, such as the team prefix in "F3LWYJ7GM7.com.apple.garageband10",
        // means nothing to the user.
        let parts = name.split(separator: ".")
        return parts.last.map(String.init) ?? folder
    }
}
