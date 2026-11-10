import Darwin
import Foundation
import Observation
import PeelCore

/// An app that arrived in a Trash: thrown away itself, or inside a folder that was.
struct TrashedApp {
    let url: URL
    let cameInAFolder: Bool
}

/// Watches the Trash for apps the user moves there: the home's Trash, and the Trash of each other disk Peel lists
/// apps on, where an app thrown away from that disk lands.
@Observable
final class TrashMonitor {
    enum Status {
        /// Not asked to watch, or stopped.
        case off
        case watching
        case needsFullDiskAccess
        /// The Trash folder's own permissions keep this account out, which Full Disk Access doesn't change.
        case closedByPermissions
        /// Asked to watch, and the Trash could not be watched.
        case unavailable

        init(_ start: TrashWatch.Start) {
            self = switch start {
            case .watching: .watching
            case .refused: .needsFullDiskAccess
            case .closedByPermissions: .closedByPermissions
            case .unavailable: .unavailable
            }
        }
    }

    /// The home Trash's watch, the one macOS keeps behind Full Disk Access.
    private(set) var status = Status.off
    var onApplicationTrashed: ((TrashedApp) -> Void)?

    @ObservationIgnored private var home: TrashWatch?
    /// The start under way, which a stop cancels.
    @ObservationIgnored private var starting: Task<Void, Never>?
    @ObservationIgnored private var volumeTrashes: [URL] = []
    /// A disk's Trash is watched from the first time Peel lists an app on the disk until the disk goes away, so an
    /// app thrown away from it is seen even when it was the last one there.
    @ObservationIgnored private var volumes: [URL: TrashWatch] = [:]

    func start() {
        guard home == nil, starting == nil else { return }
        // The setting is about apps the user moves to the Trash, so Peel's own moves are told apart, from
        // before the first listing, and every Trash is looked at again once one ends.
        OwnTrashMoves.shared.whenSettled { [weak self] in
            Task { @MainActor in
                self?.home?.changed()
                self?.volumes.values.forEach { $0.changed() }
            }
        }
        let trash = URL.homeDirectory.appending(path: ".Trash", directoryHint: .isDirectory)
        // Finder makes the home's Trash again only when something is next thrown away, so while it is missing the
        // home folder is watched for it.
        let watch = TrashWatch(trash: trash, waitsIn: .homeDirectory) { [weak self] in self?.onApplicationTrashed?($0) }
        starting = Task { [weak self] in
            let started = await watch.start()
            guard let self, !Task.isCancelled, let started else {
                watch.stop()
                return
            }
            starting = nil
            status = Status(started)
            guard started == .watching else {
                OwnTrashMoves.shared.whenSettled(nil)
                return
            }
            home = watch
            watch.onRestart = { [weak self] result in
                guard result != .watching else { return }
                self?.stop()
                self?.status = Status(result)
            }
            startVolumes()
        }
    }

    func stop() {
        starting?.cancel()
        starting = nil
        OwnTrashMoves.shared.whenSettled(nil)
        home?.stop()
        home = nil
        volumes.values.forEach { $0.stop() }
        volumes = [:]
        status = .off
    }

    /// Follows the apps Peel lists: each disk other than the home's that holds one has a Trash of its own.
    func follow(appsAt apps: [URL]) {
        volumeTrashes = VolumeTrashes.folders(forAppsAt: apps)
        guard home != nil else { return }
        startVolumes()
    }

    private func startVolumes() {
        for trash in volumeTrashes {
            if let watch = volumes[trash], watch.isActive || watch.isStarting {
                // A Trash can appear inside `.Trashes`, which cannot be opened, so no event says when it does.
                // The list of apps changing, as it does when one leaves its folder, is when to look again.
                watch.lookForTheTrash()
            } else {
                let volume = trash.deletingLastPathComponent().deletingLastPathComponent()
                let watch = TrashWatch(trash: trash, waitsIn: volume) { [weak self] in
                    self?.onApplicationTrashed?($0)
                }
                volumes[trash] = watch
                Task { _ = await watch.start() }
            }
        }
    }
}

/// One Trash folder, watched for apps arriving, on their own or inside a folder thrown away with them. A Trash can be
/// missing: a disk's appears only once something there first goes to the Trash, and the home's is made again only then
/// after it is deleted. Until it is there, the folder it appears in is watched: the top of the disk, where `.Trashes`
/// appears, or the home folder.
@MainActor
final class TrashWatch {
    enum Start {
        case watching
        /// macOS's privacy protection refused to let Peel look, which for the home's Trash means Full Disk Access is
        /// missing.
        case refused
        case closedByPermissions
        case unavailable
    }

    let trash: URL
    private let waitingPlace: URL
    /// How the Trash is listed, on a thread of its own.
    private let listing: @Sendable (URL) -> Set<String>?
    private let onArrived: (TrashedApp) -> Void
    /// Told what came of starting again after the folder watched went away.
    var onRestart: ((Start) -> Void)?
    private var source: (any DispatchSourceFileSystemObject)?
    private(set) var isWaitingForTheTrash = false
    private var known: Set<String> = []
    /// One listing at a time, and one more when events arrived while it ran: the Trash can hold thousands of
    /// items, and the event comes in on the main queue.
    private var isListing = false
    private var needsAnotherLook = false
    private(set) var isStarting = false
    /// Counts the stops, so a start still opening a folder when one comes closes it instead of watching.
    private var stops = 0

    var isActive: Bool { source != nil }

    init(
        trash: URL,
        waitsIn waitingPlace: URL,
        listing: @escaping @Sendable (URL) -> Set<String>? = WatchedFolder.names(in:),
        onArrived: @escaping (TrashedApp) -> Void
    ) {
        self.trash = trash
        self.waitingPlace = waitingPlace
        self.listing = listing
        self.onArrived = onArrived
    }

    /// Opens and lists the Trash off the main thread, as a disk that doesn't answer would hold it. `appeared` is true
    /// for a Trash that appeared while it was waited for: whatever is in it came with it. Nil when the watch was
    /// stopped before it ended, or another start was under way.
    func start(appeared: Bool = false) async -> Start? {
        guard source == nil else { return .watching }
        guard !isStarting else { return nil }
        isStarting = true
        defer { isStarting = false }
        let stopsBefore = stops
        let opening = await WatchedFolder.open(trash, listing: listing)
        guard stops == stopsBefore else {
            if case .opened(let descriptor, _) = opening { close(descriptor) }
            return nil
        }
        switch opening {
        case .missing:
            return await waitForTheTrash(unlessStoppedSince: stopsBefore)
        case .opened(let descriptor, let names):
            known = appeared ? [] : names
            watch(descriptor)
            if appeared {
                changed()
            }
            return .watching
        case .refused(let refusal):
            // Only a refusal from macOS's privacy protection means Full Disk Access is missing.
            return switch refusal {
            case .privacy: .refused
            case .permissions: .closedByPermissions
            case .other, nil: .unavailable
            }
        case .noAnswer:
            return .unavailable
        }
    }

    func stop() {
        stops += 1
        source?.cancel()
        source = nil
        isWaitingForTheTrash = false
    }

    /// Looks again for a Trash that was waited for. The watch starts whether anyone listens or not: an optional call
    /// leaves out its arguments when nothing is there.
    func lookForTheTrash() {
        guard isWaitingForTheTrash else { return }
        stop()
        Task {
            guard let result = await start(appeared: true) else { return }
            onRestart?(result)
        }
    }

    private func waitForTheTrash(unlessStoppedSince stopsBefore: Int) async -> Start? {
        let descriptor = await WatchedFolder.openToWait(in: waitingPlace)
        guard stops == stopsBefore else {
            if let descriptor { close(descriptor) }
            return nil
        }
        guard let descriptor else { return .unavailable }
        watch(descriptor)
        isWaitingForTheTrash = true
        return .watching
    }

    // Watches for delete and rename too: a folder that is removed and made again is another folder, and the
    // descriptor would keep following the old one. A disk that goes away revokes it.
    private func watch(_ descriptor: Int32) {
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let events = self.source?.data else { return }
                if events.contains(.revoke) {
                    self.stop()
                } else if self.isWaitingForTheTrash {
                    self.lookForTheTrash()
                } else if !events.isDisjoint(with: [.delete, .rename]) {
                    self.stop()
                    Task {
                        guard let result = await self.start() else { return }
                        self.onRestart?(result)
                    }
                } else if events.contains(.write) {
                    self.changed()
                }
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source
    }

    func changed() {
        // The end of one of Peel's own moves asks too, and it may come after the watch ended.
        guard source != nil, !isWaitingForTheTrash else { return }
        guard !isListing else {
            needsAnotherLook = true
            return
        }
        isListing = true
        Task { [trash, known, listing] in
            defer {
                isListing = false
                if needsAnotherLook {
                    needsAnotherLook = false
                    changed()
                }
            }
            let look = OwnTrashMoves.shared.look()
            guard
                let names = await WatchedFolder.list(trash, listing: listing),
                // Nil while Peel is moving something itself: the end of that move looks again.
                let arrived = OwnTrashMoves.shared.arrivals(names, known: known, in: trash, since: look)
            else { return }
            self.known = names
            // What Peel put there, from this process or from `peel` in Terminal, is no app the user threw away.
            let placedByPeel = arrived.isEmpty ? [] : await RemovalLog().placesInTheTrash()
            for name in arrived {
                let url = trash.appending(path: name, directoryHint: .isDirectory)
                guard !placedByPeel.contains(PathPattern.comparablePath(of: url)) else { continue }
                if AppInspector.isNamedAsAnApp(url) {
                    onArrived(TrashedApp(url: url, cameInAFolder: false))
                } else {
                    for app in await AppCatalog.apps(inAFolderThrownAway: url) {
                        onArrived(TrashedApp(url: app, cameInAFolder: true))
                    }
                }
            }
        }
    }

}
