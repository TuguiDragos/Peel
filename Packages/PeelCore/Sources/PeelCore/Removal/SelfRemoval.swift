import Darwin
public import Foundation
internal import PeelPrivileged
import ServiceManagement

/// Moves Peel's own files to the Trash, and then the Peel folder, which holds History.
public enum SelfRemoval {
    /// What Remove Peel asks of the helper, the work Peel keeps running and the login item. Tests stand in for each.
    public struct Steps {
        let helperIsRegistered: () async -> Bool
        let helperIsEnabled: () async -> Bool
        let helperMayBeChanged: () async -> Bool
        let helperAnswers: () async -> Bool
        let moveLedger: () async -> PrivilegedHelper.LedgerMove
        let ledger: URL
        /// Unregisters the helper, answering why it couldn't be, or nil.
        let uninstallHelper: () async -> String?
        let pauseWork: () async -> Void
        let resumeWork: () async -> Void
        /// Unregisters Peel as a login item, answering whether Peel still opens at login.
        let unregisterLoginItem: () async -> Bool

        public init(
            helperIsRegistered: @escaping () async -> Bool,
            helperIsEnabled: @escaping () async -> Bool,
            uninstallHelper: @escaping () async -> String?,
            work: StandingWork
        ) {
            self.init(
                helperIsRegistered: helperIsRegistered,
                helperIsEnabled: helperIsEnabled,
                helperMayBeChanged: { await PrivilegedHelper.currentAvailability() },
                helperAnswers: { await PrivilegedHelper.isResponding() },
                moveLedger: { await PrivilegedHelper.moveLedgerToTrash() },
                ledger: PrivilegedHelper.ledgerFolder,
                uninstallHelper: uninstallHelper,
                pauseWork: { await work.pause() },
                resumeWork: { await work.resume() },
                unregisterLoginItem: {
                    // Unregistering a login item that was never registered fails too, so what counts is whether it is
                    // still there.
                    try? await SMAppService.mainApp.unregister()
                    return [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
                }
            )
        }

        init(
            helperIsRegistered: @escaping () async -> Bool,
            helperIsEnabled: @escaping () async -> Bool,
            helperMayBeChanged: @escaping () async -> Bool,
            helperAnswers: @escaping () async -> Bool,
            moveLedger: @escaping () async -> PrivilegedHelper.LedgerMove,
            ledger: URL,
            uninstallHelper: @escaping () async -> String?,
            pauseWork: @escaping () async -> Void,
            resumeWork: @escaping () async -> Void,
            unregisterLoginItem: @escaping () async -> Bool
        ) {
            self.helperIsRegistered = helperIsRegistered
            self.helperIsEnabled = helperIsEnabled
            self.helperMayBeChanged = helperMayBeChanged
            self.helperAnswers = helperAnswers
            self.moveLedger = moveLedger
            self.ledger = ledger
            self.uninstallHelper = uninstallHelper
            self.pauseWork = pauseWork
            self.resumeWork = resumeWork
            self.unregisterLoginItem = unregisterLoginItem
        }
    }

    public enum Outcome: Equatable {
        case stayed(Stay)
        /// Peel's app is in the Trash. `stayed` is what didn't go with it, the helper's ledger included.
        case moved(app: TrashedItem, stayed: [TrashFailure], opensAtLogin: Bool)
    }

    public enum Stay: Equatable {
        /// This account can't change the helper, which serves every administrator of this Mac.
        case helperIsNotThisAccounts
        /// The helper is still registered. `reason` says why its uninstall failed, when it did say.
        case helperStayed(reason: String?, ledger: PrivilegedHelper.LedgerMove)
        case appStayed(failures: [TrashFailure], ledger: PrivilegedHelper.LedgerMove)
    }

    /// Removes Peel: the helper, after it has moved Peel's links and its ledger, then the login item, then `urls`
    /// through `move`. The work Peel keeps running is paused from the first step, since it would write Peel's files
    /// again, and resumed when Peel stays.
    public static func remove(
        _ urls: [URL],
        links: [URL],
        app: URL,
        folder: URL,
        steps: Steps,
        using service: TrashService,
        recording record: (TrashResult) async -> Void
    ) async -> Outcome {
        if await steps.helperIsRegistered(), await !steps.helperMayBeChanged() {
            return .stayed(.helperIsNotThisAccounts)
        }
        await steps.pauseWork()
        var ledger = PrivilegedHelper.LedgerMove.none
        var movedLinks = TrashResult()
        if await steps.helperIsRegistered() {
            (movedLinks, ledger) = await beforeTheHelperGoes(
                links: links,
                helperIsEnabled: await steps.helperIsEnabled(),
                using: service,
                answers: steps.helperAnswers,
                moveLedger: steps.moveLedger,
                ledger: steps.ledger
            )
            let failure = await steps.uninstallHelper()
            // A helper still registered would point into the Trash, so Peel moves only once the helper is gone.
            guard await !steps.helperIsRegistered() else {
                await steps.resumeWork()
                if !movedLinks.trashed.isEmpty {
                    await record(TrashResult(trashed: movedLinks.trashed))
                }
                return .stayed(.helperStayed(reason: failure, ledger: ledger))
            }
        }
        let opensAtLogin = await steps.unregisterLoginItem()
        let result = await move(
            urls, app: app, folder: folder, movedFirst: movedLinks.trashed, using: service, recording: record
        )
        guard let moved = result.trashed.first(where: { $0.originalURL == app }) else {
            await steps.resumeWork()
            return .stayed(.appStayed(failures: result.failures, ledger: ledger))
        }
        var stayed = result.failures + movedLinks.failures
        if case .stayed(let failure) = ledger {
            stayed.append(failure)
        }
        return .moved(app: moved, stayed: stayed, opensAtLogin: opensAtLogin)
    }

    /// Moves `app` to the Trash, then the rest of `urls` once it has moved, and then `folder`, all but the Terminal
    /// settings the person's `.zshrc` and `~/.ssh/config` read, which go on working without Peel. `record` writes
    /// History into `folder` first, with `movedFirst`, what the helper moved before it went, so the record goes with
    /// it. Nothing is written after that, or the folder would be created again.
    public static func move(
        _ urls: [URL],
        app: URL,
        folder: URL,
        movedFirst: [TrashedItem] = [],
        using service: TrashService,
        recording record: (TrashResult) async -> Void
    ) async -> TrashResult {
        let files = urls.filter { $0 != app }
        var result = await service.trash(
            apps: urls.filter { $0 == app },
            thenFiles: { stayed in stayed.isEmpty ? files : [] },
            usingHelperFor: [],
            lettingTheirProgramsRun: [app]
        )
        result.trashed.insert(contentsOf: movedFirst, at: 0)
        await record(result)
        guard
            result.trashed.contains(where: { $0.originalURL == app }),
            FileManager.default.fileExists(atPath: folder.path(percentEncoded: false))
        else { return result }
        let terminal = ShellFile.url(in: folder).deletingLastPathComponent()
        let moved: TrashResult
        if terminal.isMissing {
            moved = await service.trash([folder])
        } else {
            do {
                let rest = try gathered(in: folder, leaving: terminal)
                moved = await service.trashOwnFiles(rest)
            } catch {
                moved = TrashResult(failures: [TrashFailure(url: folder, reason: .failed(error.localizedDescription))])
            }
        }
        result.trashed += moved.trashed
        result.failures += moved.failures
        return result
    }

    /// Ends this account's app extensions still running from `app` in the Trash, which a rename leaves running.
    @discardableResult
    public static func endExtensions(runningFrom app: URL) -> [pid_t] {
        let bundle = PathComponents.of(PathPattern.comparablePath(of: PathPattern.canonical(app)))
        var pids = [pid_t](repeating: 0, count: 8_192)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        return pids.prefix(max(count, 0)).filter { pid in
            guard pid > 0, pid != getpid(), isThisAccounts(pid), let program = RunningProgram.path(of: pid) else {
                return false
            }
            let names = PathComponents.of(PathPattern.comparablePath(of: URL(filePath: program)))
            guard names.count > bundle.count, names.starts(with: bundle),
                  names.dropFirst(bundle.count).contains(where: { $0.hasSuffix(".appex") })
            else { return false }
            return kill(pid, SIGTERM) == 0
        }
    }

    private static func isThisAccounts(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size && info.pbi_uid == getuid()
    }

    /// Has the helper take Peel's own links in the root folders and its ledger before it is unregistered, asking it
    /// once first: a helper that cannot start would keep each request waiting, so then nothing is sent and both stay.
    public static func beforeTheHelperGoes(
        links: [URL],
        helperIsEnabled: Bool,
        using service: TrashService,
        answers: () async -> Bool = { await PrivilegedHelper.isResponding() },
        moveLedger: () async -> PrivilegedHelper.LedgerMove = { await PrivilegedHelper.moveLedgerToTrash() },
        ledger: URL = PrivilegedHelper.ledgerFolder
    ) async -> (links: TrashResult, ledger: PrivilegedHelper.LedgerMove) {
        guard helperIsEnabled, await answers() else {
            let unanswered = TrashFailure.Reason.failed(PrivilegedHelper.unavailable)
            let left = helperIsEnabled ? links.map { TrashFailure(url: $0, reason: unanswered) } : []
            return (
                TrashResult(failures: left),
                ledger.isThere ? .stayed(TrashFailure(url: ledger, reason: unanswered)) : .none
            )
        }
        return (await service.trash(links, usingHelperFor: Set(links)), await moveLedger())
    }

    /// Gathers everything in `folder` but `kept` into a folder named Peel inside it, so the Trash shows Peel's files
    /// as one item. An entry that cannot be gathered is answered on its own.
    private static func gathered(in folder: URL, leaving kept: URL) throws -> [URL] {
        let manager = FileManager.default
        let entries = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != kept.lastPathComponent }
        let together = folder.appending(path: "Peel", directoryHint: .isDirectory)
        guard (try? manager.createDirectory(at: together, withIntermediateDirectories: false)) != nil else {
            return entries
        }
        let left = entries.filter { entry in
            (try? manager.moveItem(at: entry, to: together.appending(path: entry.lastPathComponent))) == nil
        }
        return [together] + left
    }
}
