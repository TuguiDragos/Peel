import Darwin
import Foundation
internal import PeelPrivileged
import Synchronization

/// What syncs to the person's other devices, where moving it to the Trash would remove it there too: what iCloud and
/// File Provider keep (`isUbiquitousItem`), and what sits in a folder another app keeps in step, known by the entry
/// the app writes at that folder's root. Each folder is asked once for the life of an instance.
final class SyncedFolders: Sendable {
    /// The entry each app keeps at the root of a folder it syncs: Syncthing's folder marker (`.stfolder`, its default
    /// `markerName`), the share's identifier in Resilio Sync's `.sync` folder, Synology Drive Client's working folder,
    /// the ignore file MEGA writes in every new sync (`src/sync.cpp` in meganz/sdk), and the cache Dropbox keeps in
    /// its folder when it doesn't sync through File Provider (Dropbox's "How to clear the Dropbox cache folder").
    static let markers = [".stfolder", ".sync/ID", ".SynologyWorkingDirectory", ".megaignore", ".dropbox.cache"]

    private let answers = Mutex<[String: Bool]>([:])

    func syncsToOtherDevices(_ url: URL) -> Bool {
        url.isInTheCloud || isKeptInStep(url)
    }

    /// Whether `url`, when it is a folder, or a folder it sits in holds one of the markers.
    func isKeptInStep(_ url: URL) -> Bool {
        let names = PathComponents.of(url.path(percentEncoded: false))
        return isKeptInStep(folder: FileAccess.isARealFolder(url) ? names[...] : names.dropLast())
    }

    /// Whether the folder whose entries are `entries` holds one of the markers, read from a listing already made.
    static func marksAFolder(_ entries: [URL]) -> Bool {
        entries.contains { entry in
            markers.contains { marker in
                let parts = marker.split(separator: "/", maxSplits: 1).map(String.init)
                guard entry.lastPathComponent == parts[0] else { return false }
                var info = stat()
                return parts.count == 1 || lstat(entry.path(percentEncoded: false) + "/" + parts[1], &info) == 0
            }
        }
    }

    /// The answer for the folder named by `names`, kept with what the folders above it answered.
    private func isKeptInStep(folder names: ArraySlice<String>) -> Bool {
        guard !names.isEmpty else { return false }
        let folder = "/" + names.joined(separator: "/")
        if let known = answers.withLock({ $0[folder] }) { return known }
        var info = stat()
        let kept = Self.markers.contains { lstat(folder + "/" + $0, &info) == 0 }
            || isKeptInStep(folder: names.dropLast())
        answers.withLock { $0[folder] = kept }
        return kept
    }
}
