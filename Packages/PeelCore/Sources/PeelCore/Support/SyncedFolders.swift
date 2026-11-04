import Darwin
public import Foundation
internal import PeelPrivileged
import Synchronization

/// What keeps an item in step with the person's other devices.
public enum SyncKeeper: Sendable, Hashable {
    /// iCloud or a cloud app through File Provider.
    case cloud
    /// An app that syncs the folder holding `marker`, the entry the app keeps at that folder's root.
    case app(SyncApp, marker: URL)

    /// The keeper as text, which a refusal log stores beside the refusal. Nil for `cloud`, which says no more than the
    /// refusal's own word.
    var detail: String? {
        guard case .app(let app, let marker) = self else { return nil }
        return app.rawValue + "\n" + marker.path(percentEncoded: false)
    }

    /// The keeper a refusal log stored as `detail`. A record that names no app is `cloud`, as every record did before
    /// the app was kept.
    init(detail: String?) {
        let parts = detail?.split(separator: "\n", maxSplits: 1).map(String.init) ?? []
        guard parts.count == 2, let app = SyncApp(rawValue: parts[0]), parts[1].hasPrefix("/") else {
            self = .cloud
            return
        }
        self = .app(app, marker: URL(filePath: parts[1]))
    }
}

/// An app that keeps a folder in step with other devices, known by the entry it writes at that folder's root.
public enum SyncApp: String, Sendable, Hashable, CaseIterable {
    case syncthing
    case resilioSync
    case synologyDrive
    case mega
    case dropbox

    /// The app's name, as its maker writes it.
    public var name: String {
        switch self {
        case .syncthing: "Syncthing"
        case .resilioSync: "Resilio Sync"
        case .synologyDrive: "Synology Drive Client"
        case .mega: "MEGA"
        case .dropbox: "Dropbox"
        }
    }

    /// The entry the app keeps at the root of a folder it syncs: Syncthing's folder marker (`.stfolder`, its default
    /// `markerName`), the share's identifier in Resilio Sync's `.sync` folder, Synology Drive Client's working folder,
    /// the ignore file MEGA writes in every new sync (`src/sync.cpp` in meganz/sdk), and the cache Dropbox keeps in
    /// its folder when it doesn't sync through File Provider (Dropbox's "How to clear the Dropbox cache folder").
    var marker: String {
        switch self {
        case .syncthing: ".stfolder"
        case .resilioSync: ".sync/ID"
        case .synologyDrive: ".SynologyWorkingDirectory"
        case .mega: ".megaignore"
        case .dropbox: ".dropbox.cache"
        }
    }

    /// The identifiers of the app's bundles: those Homebrew's casks quit (`syncthing-app`, `resilio-sync`,
    /// `synology-drive`, `megasync`, `dropbox`), Synctrain's (pixelspark/sushitrain) and MEGAcmd's (meganz/MEGAcmd).
    var bundleIdentifiers: [String] {
        switch self {
        case .syncthing: ["com.github.xor-gate.syncthing-macosx", "nl.t-shaped.Sushitrain"]
        case .resilioSync: ["com.resilio.Sync"]
        case .synologyDrive: ["com.synology.CloudStation"]
        case .mega: ["mega.mac", "megacmd.mac"]
        case .dropbox: ["com.getdropbox.dropbox"]
        }
    }

    /// The program that runs the app outside a bundle: Syncthing's, from Homebrew's formula or MacPorts' port.
    var program: String? {
        self == .syncthing ? "syncthing" : nil
    }

    /// Whether the app is on this Mac. Only the app keeps a folder in step, and its marker stays behind when it goes
    /// and comes along when a folder is copied, so a marker counts only while the app is here.
    @Sendable static func isOnThisMac(_ app: SyncApp) -> Bool {
        isOnThisMac(bundleIdentifiers: app.bundleIdentifiers, program: app.program)
    }

    /// Whether macOS knows a bundle of one of `bundleIdentifiers` outside a Trash, or `program` is in the folders
    /// Homebrew (on Apple silicon and on Intel) and MacPorts link programs into, or runs. A list of processes that
    /// can't be read says the program may run.
    static func isOnThisMac(
        bundleIdentifiers: [String],
        program: String?,
        programFolders: [String] = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"]
    ) -> Bool {
        if bundleIdentifiers.contains(where: { !AppInspector.applicationURLs(forBundleIdentifier: $0).isEmpty }) {
            return true
        }
        guard let program else { return false }
        if programFolders.contains(where: { FileManager.default.isExecutableFile(atPath: $0 + "/" + program) }) {
            return true
        }
        return runs(program) ?? true
    }

    /// Whether a process runs a program named `name`, or nil when the processes can't be listed.
    private static func runs(_ name: String) -> Bool? {
        var pids = [pid_t](repeating: 0, count: 8_192)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        guard count > 0 else { return nil }
        return pids.prefix(count).contains { pid in
            pid > 0 && RunningProgram.path(of: pid).map { URL(filePath: $0).lastPathComponent == name } == true
        }
    }

    /// Whether each app is on this Mac, in place of this Mac's answer, for a test: no test can install a sync app.
    @TaskLocal static var standIn: (@Sendable (SyncApp) -> Bool)?
}

/// What syncs to the person's other devices, where moving it to the Trash would remove it there too: what iCloud and
/// File Provider keep (`isUbiquitousItem`), and what sits in a folder another app on this Mac keeps in step, known by
/// the entry the app writes at that folder's root. Each folder and each app are asked once for the life of an
/// instance.
final class SyncedFolders: Sendable {
    private let answers = Mutex<[String: SyncKeeper?]>([:])
    private let lookUp: @Sendable (SyncApp) -> Bool
    private let appsOnThisMac = Mutex<[SyncApp: Bool]>([:])

    init() {
        lookUp = SyncApp.standIn ?? SyncApp.isOnThisMac
    }

    /// Whether `app` is on this Mac, asked only once a marker of its own was found.
    private func isOnThisMac(_ app: SyncApp) -> Bool {
        if let known = appsOnThisMac.withLock({ $0[app] }) { return known }
        let isHere = lookUp(app)
        appsOnThisMac.withLock { $0[app] = isHere }
        return isHere
    }

    func syncsToOtherDevices(_ url: URL) -> Bool {
        keeper(of: url) != nil
    }

    /// What keeps `url` in step: iCloud or File Provider, or else the app whose marker is in the nearest folder at or
    /// above it. Nil when nothing does.
    func keeper(of url: URL) -> SyncKeeper? {
        if url.isInTheCloud { return .cloud }
        let names = PathComponents.of(url.path(percentEncoded: false))
        return keeper(ofFolder: FileAccess.isARealFolder(url) ? names[...] : names.dropLast())
    }

    /// Whether the folder whose entries are `entries` holds the marker of an app on this Mac, read from a listing
    /// already made.
    func marksAFolder(_ entries: [URL]) -> Bool {
        entries.contains { entry in
            SyncApp.allCases.contains { app in
                let parts = app.marker.split(separator: "/", maxSplits: 1).map(String.init)
                guard entry.lastPathComponent == parts[0] else { return false }
                var info = stat()
                return (parts.count == 1 || lstat(entry.path(percentEncoded: false) + "/" + parts[1], &info) == 0)
                    && isOnThisMac(app)
            }
        }
    }

    /// The keeper for the folder named by `names`, kept with what the folders above it answered.
    private func keeper(ofFolder names: ArraySlice<String>) -> SyncKeeper? {
        guard !names.isEmpty else { return nil }
        let folder = "/" + names.joined(separator: "/")
        if let known = answers.withLock({ $0[folder] }) { return known }
        var info = stat()
        let keeper = SyncApp.allCases.first { lstat(folder + "/" + $0.marker, &info) == 0 && isOnThisMac($0) }
            .map { SyncKeeper.app($0, marker: URL(filePath: folder + "/" + $0.marker)) }
            ?? keeper(ofFolder: names.dropLast())
        answers.withLock { $0[folder] = keeper }
        return keeper
    }
}
