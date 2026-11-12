import CryptoKit
public import Foundation

public enum DuplicateRemoval {
    /// Moves the selected folders, then the selected copies, to the Trash as one removal: each only while it and an
    /// unselected one of its group are still what the scan compared, checked right before its own move, since a sync
    /// client, Finder, or another window can change the kept one meanwhile. Their bytes are read again first, with no
    /// memory, since what the scan remembered can be wrong, and each moves only while one that stays holds the same.
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
        let (folders, files) = await MoveCount.reading {
            (
                await readAgain(Set(selectedFolders.values.flatMap { [$0.folder] + $0.kept })),
                await readAgain(Set(selectedFiles.values.flatMap { [$0.file.url] + $0.kept.map(\.url) }))
            )
        }
        return await trashService.trash(urls, refusing: { url in
            if let entry = checkedFolders[url] {
                guard entry.kept.contains(where: FolderDuplicates.holdsTheSameContents) else { return .lastCopy }
                guard FolderDuplicates.holdsTheSameContents(entry.folder),
                      let read = folders[url], FolderDuplicates.entries(of: entry.folder) == read.entries
                else { return .changedSinceScan }
                let alike = entry.kept.contains { kept in
                    guard let other = folders[kept.url] else { return false }
                    return other.contents == read.contents && FolderDuplicates.entries(of: kept) == other.entries
                }
                return alike ? nil : .lastCopy
            }
            guard let entry = checkedFiles[url] else { return nil }
            guard entry.kept.contains(where: { FileIdentity.of($0.url)?.holdsTheSameContents(as: $0.identity) == true })
            else { return .lastCopy }
            guard FileIdentity.of(url)?.holdsTheSameContents(as: entry.file.identity) == true,
                  let read = files[url], FileIdentity.of(url) == read.identity
            else { return .changedSinceScan }
            let alike = entry.kept.contains { kept in
                guard let other = files[kept.url] else { return false }
                return other.digest == read.digest && FileIdentity.of(kept.url) == other.identity
            }
            return alike ? nil : .lastCopy
        })
    }

    private static func readAgain(
        _ folders: Set<DuplicateFolder>
    ) async -> [URL: (contents: SHA256.Digest, entries: SHA256.Digest)] {
        var read: [URL: (contents: SHA256.Digest, entries: SHA256.Digest)] = [:]
        for folder in folders {
            read[folder.url] = await FolderDuplicates.readAgain(folder)
        }
        return read
    }

    private static func readAgain(_ urls: Set<URL>) async -> [URL: (identity: FileIdentity, digest: ContentDigest)] {
        let files = urls.compactMap { url in FileIdentity.of(url).map { (url: url, identity: $0) } }
        let read = await FileDigest.many(files) { file, isGivenUp in
            FileDigest.full(of: file.url, identity: file.identity, isGivenUp: isGivenUp)
        }
        return Dictionary(read.map { ($0.item.url, ($0.item.identity, $0.digest)) }) { first, _ in first }
    }
}
