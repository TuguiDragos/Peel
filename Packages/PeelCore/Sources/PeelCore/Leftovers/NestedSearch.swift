import Foundation
internal import PeelPrivileged

/// The search inside the folders of a location that belong to somebody else, where an app's files can sit: a crash
/// reporter's data folder, macOS's help cache, or a vendor's folder shared by several apps, such as
/// `VST3/Native Instruments`, `~/Library/<Vendor>` or `/Users/Shared/<Vendor>`. An uninstall and Orphaned Files
/// look inside the same folders this way, as deep and as far.
enum NestedSearch {
    /// What the search does with one entry of a folder it lists.
    enum Step<Item> {
        /// The entry is one of the things searched for.
        case take(Item)
        /// The entry is a folder to list in turn.
        case lookInside
        case pass
    }

    struct Findings<Item> {
        var found: [Item] = []
        /// True when the search stopped at its limit, so a folder it did not reach may hold more.
        var wasCutShort = false
        /// The folders it could not list, which may hold what it searched for.
        var unreadable: [URL] = []
    }

    /// The kinds of location whose folders are looked inside. In `/Users/Shared`, everything found is held back.
    static let kinds: Set<SearchLocation.Kind> = [
        .applicationSupport, .caches, .logs, .hiddenHomeFiles, .plugIns, .sharedFolder, .library,
    ]

    /// How many levels of folders are listed below a location's own entries.
    static let depth = 2

    /// The most folders listed per location. It is far more than a busy Application Support or Caches folder needs,
    /// and each listing is cheap.
    static let folderLimit = 5_000

    /// Lists `folders`, and every folder inside them that `visit` asks to look inside, `depth` levels down and at most
    /// `limit` folders in all. `visit` is told whether a folder it asks to look inside would still be listed. A folder
    /// of Apple's own that cannot be listed is not returned, since it holds no other app's files.
    static func walk<Item>(
        inside folders: [URL],
        limit: Int,
        visit: (_ entry: URL, _ name: String, _ parent: ParentAccess, _ canLookInside: Bool) async -> Step<Item>
    ) async -> Findings<Item> {
        var findings = Findings<Item>()
        var pending = folders
        var listed = 0
        for level in 0..<depth {
            var deeper: [URL] = []
            for folder in pending {
                // A canceled scan stops here, since nobody will read what it finds.
                guard !Task.isCancelled else { return findings }
                guard listed < limit else {
                    findings.wasCutShort = true
                    return findings
                }
                listed += 1
                let names: [String]
                do {
                    // Sorted, because Apple documents the order of a listing as undefined, and with a limit on how
                    // many folders are listed, the order decides which ones.
                    names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
                        .sorted()
                } catch CocoaError.fileReadNoSuchFile {
                    continue
                } catch {
                    if !ProtectedData.isApplesName(folder.lastPathComponent) {
                        findings.unreadable.append(folder)
                    }
                    continue
                }
                ScanCount.current?.add(names.count)

                let parent = ParentAccess(folder)
                for name in names {
                    let entry = folder.appending(path: name)
                    switch await visit(entry, name, parent, level + 1 < depth) {
                    case .take(let item): findings.found.append(item)
                    case .lookInside: deeper.append(entry)
                    case .pass: break
                    }
                }
            }
            pending = deeper
        }
        return findings
    }
}
