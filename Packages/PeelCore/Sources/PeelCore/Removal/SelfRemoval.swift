public import Foundation

/// Moves Peel's own files to the Trash, and then the Peel folder, which holds History.
public enum SelfRemoval {
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
