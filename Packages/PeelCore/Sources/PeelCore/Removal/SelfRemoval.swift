public import Foundation

/// Moves Peel's own files to the Trash, and then the Peel folder, which holds History.
public enum SelfRemoval {
    /// Moves `urls` to the Trash, and then `folder` if `app` moved. `record` writes History into `folder` first,
    /// so the record goes with it. Nothing is written after that, or the folder would be created again.
    public static func move(
        _ urls: [URL],
        app: URL,
        folder: URL,
        using service: TrashService,
        recording record: (TrashResult) async -> Void
    ) async -> TrashResult {
        var result = await service.trash(urls)
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
