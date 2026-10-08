public import Foundation

/// Moves Peel's own files to the Trash, and then the Peel folder, which holds History.
public enum SelfRemoval {
    /// Moves `app` to the Trash, then the rest of `urls` once it has moved, and then `folder`. `record` writes
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
            lettingTheirProgramsRun: []
        )
        result.trashed.insert(contentsOf: movedFirst, at: 0)
        await record(result)
        guard
            result.trashed.contains(where: { $0.originalURL == app }),
            FileManager.default.fileExists(atPath: folder.path(percentEncoded: false))
        else { return result }
        let moved = await service.trash([folder])
        result.trashed += moved.trashed
        result.failures += moved.failures
        return result
    }
}
