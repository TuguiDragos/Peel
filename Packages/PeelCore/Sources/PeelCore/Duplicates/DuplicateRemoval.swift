public import Foundation

public enum DuplicateRemoval {
    /// Moves the selected folders, then the selected copies, to the Trash. A copy moves only while it and at
    /// least one unselected copy of its group are unchanged since the scan. The kept copy is checked again
    /// before each move, because a sync client, Finder, or another window can remove it while this runs.
    @concurrent
    public static func trash(
        _ selection: Set<URL>,
        folders: Set<URL> = [],
        from scan: DuplicateScan,
        using trashService: TrashService = TrashService()
    ) async -> TrashResult {
        // The scan never offers a file on its own when it sits inside an offered folder, so the two selections
        // never ask for the same bytes.
        var result = await trash(folders: folders, from: scan, using: trashService)

        for group in scan.groups {
            let selected = group.files.filter { selection.contains($0.url) }
            guard !selected.isEmpty else { continue }
            let kept = group.files.filter { !selection.contains($0.url) }

            for file in selected {
                guard kept.contains(where: { FileIdentity.of($0.url)?.holdsTheSameContents(as: $0.identity) == true }) else {
                    result.failures.append(TrashFailure(url: file.url, reason: .lastCopy))
                    continue
                }
                guard FileIdentity.of(file.url)?.holdsTheSameContents(as: file.identity) == true else {
                    result.failures.append(TrashFailure(url: file.url, reason: .changedSinceScan))
                    continue
                }
                let moved = await trashService.trash([file.url])
                result.trashed += moved.trashed
                result.failures += moved.failures
            }
        }
        return result
    }

    /// Moves the selected folders to the Trash. A folder moves only while it and at least one unselected folder
    /// of its group still hold exactly what was compared: the same entries, each the same file with the same size
    /// and times, with nothing added or removed.
    private static func trash(folders: Set<URL>, from scan: DuplicateScan, using trashService: TrashService) async -> TrashResult {
        var result = TrashResult()

        for group in scan.folderGroups {
            let selected = group.folders.filter { folders.contains($0.url) }
            guard !selected.isEmpty else { continue }
            let kept = group.folders.filter { !folders.contains($0.url) }

            for folder in selected {
                guard kept.contains(where: FolderDuplicates.holdsTheSameContents) else {
                    result.failures.append(TrashFailure(url: folder.url, reason: .lastCopy))
                    continue
                }
                guard FolderDuplicates.holdsTheSameContents(folder) else {
                    result.failures.append(TrashFailure(url: folder.url, reason: .changedSinceScan))
                    continue
                }
                let moved = await trashService.trash([folder.url])
                result.trashed += moved.trashed
                result.failures += moved.failures
            }
        }
        return result
    }
}
