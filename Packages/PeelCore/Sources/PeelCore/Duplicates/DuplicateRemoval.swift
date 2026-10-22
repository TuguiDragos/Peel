public import Foundation

public enum DuplicateRemoval {
    /// Moves the selected folders, then the selected copies, to the Trash as one removal: each only while it and an
    /// unselected one of its group are still what the scan compared, checked right before its own move, since a sync
    /// client, Finder, or another window can change the kept one meanwhile.
    @concurrent
    public static func trash(
        _ selection: Set<URL>,
        folders: Set<URL> = [],
        from scan: DuplicateScan,
        using trashService: TrashService
    ) async -> TrashResult {
        // The scan never offers a file on its own when it sits inside an offered folder, so the two selections
        // never ask for the same bytes.
        var urls: [URL] = []
        var selectedFolders: [URL: (folder: DuplicateFolder, kept: [DuplicateFolder])] = [:]
        for group in scan.folderGroups {
            let selected = group.folders.filter { folders.contains($0.url) }
            guard !selected.isEmpty else { continue }
            let kept = group.folders.filter { !folders.contains($0.url) }
            for folder in selected {
                urls.append(folder.url)
                selectedFolders[folder.url] = (folder, kept)
            }
        }
        var selectedFiles: [URL: (file: DuplicateFile, kept: [DuplicateFile])] = [:]
        for group in scan.groups {
            let selected = group.files.filter { selection.contains($0.url) }
            guard !selected.isEmpty else { continue }
            let kept = group.files.filter { !selection.contains($0.url) }
            for file in selected {
                urls.append(file.url)
                selectedFiles[file.url] = (file, kept)
            }
        }
        let checkedFolders = selectedFolders
        let checkedFiles = selectedFiles
        return await trashService.trash(urls, refusing: { url in
            if let entry = checkedFolders[url] {
                guard entry.kept.contains(where: FolderDuplicates.holdsTheSameContents) else { return .lastCopy }
                return FolderDuplicates.holdsTheSameContents(entry.folder) ? nil : .changedSinceScan
            }
            guard let entry = checkedFiles[url] else { return nil }
            guard entry.kept.contains(where: { FileIdentity.of($0.url)?.holdsTheSameContents(as: $0.identity) == true })
            else { return .lastCopy }
            return FileIdentity.of(url)?.holdsTheSameContents(as: entry.file.identity) == true ? nil : .changedSinceScan
        })
    }
}
