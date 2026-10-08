import Darwin
import Foundation
import Observation
import PeelCore

/// Watches the Trash for apps the user moves there: the home's Trash, and the Trash of each other disk Peel lists
/// apps on, where an app thrown away from that disk lands.
@Observable
final class TrashMonitor {
    enum Status {
        /// Not asked to watch, or stopped.
        case off
        case watching
        case needsFullDiskAccess
        /// Asked to watch, and the Trash could not be watched.
        case unavailable
    }

    /// The home Trash's watch, the one macOS keeps behind Full Disk Access.
    private(set) var status = Status.off
    var onApplicationTrashed: ((URL) -> Void)?

    @ObservationIgnored private var home: TrashWatch?
    @ObservationIgnored private var volumeTrashes: [URL] = []
    /// A disk's Trash is watched from the first time Peel lists an app on the disk until the disk goes away, so an
    /// app thrown away from it is seen even when it was the last one there.
    @ObservationIgnored private var volumes: [URL: TrashWatch] = [:]

    func start() {
        guard home == nil else { return }
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
        switch watch.start() {
        case .watching:
            home = watch
            status = .watching
        case .refused:
            OwnTrashMoves.shared.whenSettled(nil)
            status = .needsFullDiskAccess
            return
        case .unavailable:
            OwnTrashMoves.shared.whenSettled(nil)
            status = .unavailable
            return
        }
        watch.onRestart = { [weak self] result in
            guard result != .watching else { return }
            self?.stop()
            self?.status = result == .refused ? .needsFullDiskAccess : .unavailable
        }
        startVolumes()
    }

    func stop() {
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
            if let watch = volumes[trash], watch.isActive {
                // A Trash can appear inside `.Trashes`, which cannot be opened, so no event says when it does.
                // The list of apps changing, as it does when one leaves its folder, is when to look again.
                watch.lookForTheTrash()
            } else {
                let volume = trash.deletingLastPathComponent().deletingLastPathComponent()
                let watch = TrashWatch(trash: trash, waitsIn: volume) { [weak self] in
                    self?.onApplicationTrashed?($0)
                }
                _ = watch.start()
                volumes[trash] = watch
            }
        }
    }
}

/// One Trash folder, watched for apps arriving. A Trash can be missing: a disk's appears only once something there
/// first goes to the Trash, and the home's is made again only then after it is deleted. Until it is there, the folder
/// it appears in is watched: the top of the disk, where `.Trashes` appears, or the home folder.
@MainActor
private final class TrashWatch {
    enum Start {
        case watching
        /// macOS refused to let Peel look, which for the home's Trash means Full Disk Access is missing.
        case refused
        case unavailable
    }

    let trash: URL
    private let waitingPlace: URL
    private let onArrived: (URL) -> Void
    /// Told what came of starting again after the folder watched went away.
    var onRestart: ((Start) -> Void)?
    private var source: (any DispatchSourceFileSystemObject)?
    private var isWaitingForTheTrash = false
    private var known: Set<String> = []
    /// One listing at a time, and one more when events arrived while it ran: the Trash can hold thousands of
    /// items, and the event comes in on the main queue.
    private var isListing = false
    private var needsAnotherLook = false

    var isActive: Bool { source != nil }

    init(trash: URL, waitsIn waitingPlace: URL, onArrived: @escaping (URL) -> Void) {
        self.trash = trash
        self.waitingPlace = waitingPlace
        self.onArrived = onArrived
    }

    /// `appeared` is true for a Trash that appeared while it was waited for: whatever is in it came with it.
    func start(appeared: Bool = false) -> Start {
        guard source == nil else { return .watching }
        let descriptor = open(trash.path(percentEncoded: false), O_EVTONLY)
        let failure = errno
        if descriptor < 0, failure == ENOENT {
            return waitForTheTrash()
        }
        guard descriptor >= 0, let applications = Self.names(in: trash) else {
            if descriptor >= 0 { close(descriptor) }
            // Only a refusal from macOS means Full Disk Access is missing. No Trash yet, or no descriptors left,
            // leaves the watch off instead.
            return descriptor >= 0 || [EPERM, EACCES].contains(failure) ? .refused : .unavailable
        }
        known = appeared ? [] : applications
        watch(descriptor)
        if appeared {
            changed()
        }
        return .watching
    }

    func stop() {
        source?.cancel()
        source = nil
        isWaitingForTheTrash = false
    }

    /// Looks again for a Trash that was waited for.
    func lookForTheTrash() {
        guard isWaitingForTheTrash else { return }
        stop()
        onRestart?(start(appeared: true))
    }

    private func waitForTheTrash() -> Start {
        let descriptor = open(waitingPlace.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else { return .unavailable }
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
                    self.onRestart?(self.start())
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
        Task { [trash, known] in
            defer {
                isListing = false
                if needsAnotherLook {
                    needsAnotherLook = false
                    changed()
                }
            }
            let look = OwnTrashMoves.shared.look()
            guard
                let applications = await Self.applications(in: trash),
                // Nil while Peel is moving something itself: the end of that move looks again.
                let arrived = OwnTrashMoves.shared.arrivals(applications, known: known, in: trash, since: look)
            else { return }
            self.known = applications
            // What Peel put there, from this process or from `peel` in Terminal, is no app the user threw away.
            let placedByPeel = arrived.isEmpty ? [] : await RemovalLog().placesInTheTrash()
            for name in arrived {
                let url = trash.appending(path: name, directoryHint: .isDirectory)
                guard !placedByPeel.contains(PathPattern.comparablePath(of: url)) else { continue }
                onArrived(url)
            }
        }
    }

    /// Lists the apps in the Trash off the main actor, for events. The first listing, which decides whether
    /// the watch can start at all, runs directly in `start()`.
    @concurrent
    private static func applications(in trash: URL) async -> Set<String>? {
        names(in: trash)
    }

    nonisolated private static func names(in trash: URL) -> Set<String>? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: trash.path(percentEncoded: false)) else {
            return nil
        }
        return Set(names.filter { $0.hasSuffix(".app") })
    }
}
