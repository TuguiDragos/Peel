import Darwin
import Foundation
import Observation
import PeelCore

@Observable
final class TrashMonitor {
    enum Status {
        case off
        case watching
        case needsFullDiskAccess
    }

    private(set) var status = Status.off
    var onApplicationTrashed: ((URL) -> Void)?

    private var source: (any DispatchSourceFileSystemObject)?
    private var knownApplications: Set<String> = []
    /// One listing at a time, and one more when events arrived while it ran: the Trash can hold thousands of
    /// items, and the event comes in on the main queue.
    private var isListing = false
    private var needsAnotherLook = false

    private var trashURL: URL {
        .homeDirectory.appending(path: ".Trash", directoryHint: .isDirectory)
    }

    func start() {
        guard source == nil else { return }
        let descriptor = open(trashURL.path(percentEncoded: false), O_EVTONLY)
        let failure = errno
        guard descriptor >= 0, let applications = applicationsInTrash() else {
            if descriptor >= 0 { close(descriptor) }
            // Only a refusal from macOS means Full Disk Access is missing. No Trash yet, or no descriptors left,
            // leaves the watch off instead.
            status = descriptor >= 0 || [EPERM, EACCES].contains(failure) ? .needsFullDiskAccess : .off
            return
        }
        knownApplications = applications
        // The setting is about apps the user moves to the Trash, so Peel's own moves are told apart, and the
        // Trash is looked at again once one ends.
        OwnTrashMoves.shared.whenSettled { [weak self] in
            Task { @MainActor in self?.trashChanged() }
        }

        // Watches for delete and rename too: a Trash folder that is removed and made again is another folder,
        // and the descriptor would keep following the old one, so no event would arrive while the status
        // still read `watching`.
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.source?.data.contains(.write) == true {
                    self.trashChanged()
                }
                if self.source?.data.isDisjoint(with: [.delete, .rename]) == false {
                    self.restart()
                }
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source
        status = .watching
    }

    /// The folder it was watching is gone, so the watch starts again on whatever is there now.
    private func restart() {
        stop()
        start()
    }

    func stop() {
        source?.cancel()
        source = nil
        status = .off
    }

    private func trashChanged() {
        // The end of one of Peel's own moves asks too, and it may come after the watch was turned off.
        guard status == .watching else { return }
        guard !isListing else {
            needsAnotherLook = true
            return
        }
        isListing = true
        Task { [trashURL] in
            defer {
                isListing = false
                if needsAnotherLook {
                    needsAnotherLook = false
                    trashChanged()
                }
            }
            let look = OwnTrashMoves.shared.look()
            guard
                let applications = await Self.applications(in: trashURL),
                // Nil while Peel is moving something itself: the end of that move looks again.
                let arrived = OwnTrashMoves.shared.arrivals(applications, known: knownApplications, in: trashURL, since: look)
            else { return }
            knownApplications = applications
            // What Peel put there, from this process or from `peel` in Terminal, is no app the person threw away.
            let placedByPeel = arrived.isEmpty ? [] : await RemovalLog().placesInTheTrash()
            for name in arrived {
                let url = trashURL.appending(path: name, directoryHint: .isDirectory)
                guard !placedByPeel.contains(PathPattern.comparablePath(of: url)) else { continue }
                onApplicationTrashed?(url)
            }
        }
    }

    private func applicationsInTrash() -> Set<String>? {
        Self.names(in: trashURL)
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
