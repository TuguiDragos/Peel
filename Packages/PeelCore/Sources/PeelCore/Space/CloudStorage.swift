public import Foundation
import Synchronization
internal import PeelPrivileged

/// A file in iCloud Drive that also has a local copy. Freeing the local copy deletes nothing: the file stays in
/// iCloud, Finder still shows it, and it downloads again when it is opened. So freeing does not go through the
/// Trash, since there is nothing to put back.
public struct CloudFile: Sendable, Hashable, Identifiable {
    public let url: URL
    public let name: String
    /// The folder under `Mobile Documents` it belongs to, in readable form: "iCloud Drive", "Pages".
    public let container: String
    /// What removing the local copy frees: less than the file's length when it is stored compressed, and nothing
    /// when a clone shares its blocks.
    public let size: Int64
    public let modified: Date?

    public var id: URL { url }
}

/// What one scan of iCloud Drive found, and whether the scan stopped early or could not read the folder.
public struct CloudScan: Sendable {
    public var files: [CloudFile] = []
    /// The walk stopped early (it ran out of time, was stopped, or filled the list), so the list may be incomplete.
    public var wasCutShort = false
    /// iCloud Drive could not be read at all, which is what happens without Full Disk Access.
    public var couldNotRead = false
}

/// A file that was not freed, and why.
public struct CloudRefusal: Sendable, Hashable, Identifiable {
    public enum Reason: Sendable, Hashable {
        /// The file is not as it was at the scan: edited, moved, or freed already, or not safely in iCloud.
        case changedSinceScan
        /// macOS refused to free the file. The value is the error message it gave.
        case failed(String)
    }

    public let url: URL
    public let reason: Reason

    public var id: URL { url }
}

public enum CloudStorage {
    /// A file that frees less than this isn't worth a row in a list about space.
    public static let minimumSize: Int64 = 1_000_000
    /// The most files listed. The cap counts listed files, not every entry walked, so a walk through many small
    /// files still reaches the big ones after them.
    static let maximumFiles = 5_000
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
        .isRegularFileKey, .contentModificationDateKey, .ubiquitousItemDownloadingStatusKey,
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
        within budget: TimeInterval = CloudStorage.budget
    ) async -> CloudScan {
        let collector = Collector()
        let scan = ScanCount.current
        let finished = await SlowRead.answer(within: budget) { isGivenUp in
            collect(
                home: home,
                minimumSize: minimumSize,
                exclusions: exclusions,
                into: collector,
                deadline: .now + .seconds(budget),
                countingFor: scan,
                unless: isGivenUp
            )
            return true
        }
        let collected = collector.collected
        return CloudScan(
            files: collected.files.sorted { $0.size > $1.size },
            wasCutShort: finished == nil || collected.wasCutShort,
            couldNotRead: collected.couldNotRead
        )
    }

    /// What the walk has gathered so far, written by the thread that walks and read once it stops or the
    /// budget runs out.
    final class Collector: Sendable {
        struct Collected {
            var files: [CloudFile] = []
            var wasCutShort = false
            var couldNotRead = false
        }

        private let state = Mutex(Collected())

        var collected: Collected { state.withLock { $0 } }

        /// Adds `file` to the list. Returns true once the list is full.
        func add(_ file: CloudFile) -> Bool {
            state.withLock { collected in
                collected.files.append(file)
                collected.wasCutShort = collected.wasCutShort || collected.files.count >= maximumFiles
                return collected.files.count >= maximumFiles
            }
        }

        func cutShort() {
            state.withLock { $0.wasCutShort = true }
        }

        func unreadable() {
            state.withLock { $0.couldNotRead = true }
        }
    }

    /// Walks iCloud Drive and adds each file worth freeing to `collector`. Stops at `deadline` as well as when
    /// `isGivenUp` says so, because the timer behind `isGivenUp` runs on another thread and can fire late on a
    /// busy Mac. Only iCloud can say a file is safely there, so a test says it through `isSafe`.
    static func collect(
        home: URL,
        minimumSize: Int64,
        exclusions: Exclusions,
        into collector: Collector,
        deadline: ContinuousClock.Instant,
        countingFor scan: ScanCount?,
        isSafe: (URLResourceValues) -> Bool = isSafeToFree(_:),
        unless isGivenUp: () -> Bool
    ) {
        let root = home.appending(path: "Library/Mobile Documents", directoryHint: .isDirectory)
        let rootPath = PathPattern.comparablePath(of: root)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, error in
                // Only an error on the root counts: without Full Disk Access nothing under it can be read. A
                // missing root (`NSFileReadNoSuchFileError`) means iCloud Drive was never set up, which is
                // nothing to list rather than a refusal.
                let isMissing = (error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSFileReadNoSuchFileError
                if PathPattern.comparablePath(of: url) == rootPath, !isMissing { collector.unreadable() }
                return true
            }
        ) else {
            collector.unreadable()
            return
        }

        for case let url as URL in enumerator {
            // The budget is spent, or the page that asked was left or stopped.
            guard ContinuousClock.now < deadline, !isGivenUp() else {
                collector.cutShort()
                return
            }
            scan?.add(1)
            guard
                let values = try? url.resourceValues(forKeys: keys),
                values.isRegularFile == true,
                !exclusions.excludes(url),
                isSafe(values)
            else { continue }
            let size = ReclaimableSpace.of(url)
            guard size >= minimumSize else { continue }

            let file = CloudFile(
                url: url,
                name: url.lastPathComponent,
                container: containerName(of: url, under: root),
                size: size,
                modified: values.contentModificationDate
            )
            if collector.add(file) { return }
        }
    }

    /// Frees the local copies of `files` and returns the ones that were not freed. Each file is checked again
    /// first: the list may have been on screen for hours, and a file edited since then may exist in its newest
    /// form only on the local disk.
    @discardableResult
    @concurrent
    public static func free(_ files: [CloudFile]) async -> [CloudRefusal] {
        var refused: [CloudRefusal] = []
        for file in files {
            var url = file.url
            url.removeAllCachedResourceValues()
            guard
                let values = try? url.resourceValues(forKeys: keys),
                values.isRegularFile == true,
                isSafeToFree(values),
                values.contentModificationDate == file.modified
            else {
                refused.append(CloudRefusal(url: file.url, reason: .changedSinceScan))
                continue
            }
            do {
                try FileManager.default.evictUbiquitousItem(at: file.url)
            } catch {
                refused.append(CloudRefusal(url: file.url, reason: .failed(error.localizedDescription)))
            }
        }
        return refused
    }

    /// The readable name of the iCloud folder that holds `url`: "iCloud Drive" for `com~apple~CloudDocs`, and
    /// the last part of the identifier for an app's folder, so `iCloud~com~acme~App` reads "App".
    static func containerName(of url: URL, under root: URL) -> String {
        let rootNames = PathComponents.of(PathPattern.comparablePath(of: root))
        let names = PathComponents.of(PathPattern.comparablePath(of: url))
        guard names.count > rootNames.count, names.starts(with: rootNames) else { return "" }
        let folder = names[rootNames.count]

        if folder == "com~apple~CloudDocs" {
            // Finder's name for the folder, in the user's language (iCloud云盘 in Simplified Chinese), for search.
            let shown = FileManager.default.displayName(atPath: root.appending(path: folder).path(percentEncoded: false))
            return shown == folder ? "iCloud Drive" : shown
        }
        var name = folder.replacingOccurrences(of: "~", with: ".")
        if let range = name.range(of: "iCloud.") { name = String(name[range.upperBound...]) }
        // Only the last part is kept. The rest, such as the team prefix in "F3LWYJ7GM7.com.apple.garageband10",
        // means nothing to the user.
        let parts = name.split(separator: ".")
        return parts.last.map(String.init) ?? folder
    }
}

extension CloudFile {
    /// The row shows an abbreviated path, so the whole path is searched and not only the file name.
    public func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return SearchText.matches(name, query)
            || SearchText.matches(container, query)
            || SearchText.matches(url.path(percentEncoded: false), query)
    }
}
