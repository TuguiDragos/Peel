public import Foundation

/// Why History can't be written now: what Peel found, and where, so that what it says names the cause.
public enum HistoryWriteProblem: Sendable, Hashable {
    /// This account can't write `folder`, the folder History is kept in, or the nearest folder there is on its way.
    case folderNotWritable(URL)
    /// The disk holding History has `free` bytes, fewer than the `needed` a safe write of History takes.
    case diskFull(free: Int64, needed: Int64)
    case freeSpaceNotKnown(URL)
    /// What stands where the journal goes doesn't open as the journal: a folder, a link, or a file too big.
    case journalUnreadable(URL)
    case journalNotWritable(URL)
    /// This account can't open `lock`, which keeps two writers of History, or of the journal, from writing over each
    /// other.
    case lockClosed(URL)
    /// `link`, History, the journal, or a lock of theirs, is a symbolic link, and Peel writes them only as files of
    /// its own.
    case aLink(URL)
}

extension HistoryWriteProblem {
    /// The problem as the refusal log keeps it beside the reason's name: a word for the case, then what it names, a
    /// line each.
    var detail: String {
        switch self {
        case .folderNotWritable(let folder): "folder\n" + folder.path(percentEncoded: false)
        case .diskFull(let free, let needed): "disk\n\(free)\n\(needed)"
        case .freeSpaceNotKnown(let folder): "free-space\n" + folder.path(percentEncoded: false)
        case .journalUnreadable(let journal): "journal\n" + journal.path(percentEncoded: false)
        case .journalNotWritable(let journal): "journal-write\n" + journal.path(percentEncoded: false)
        case .lockClosed(let lock): "lock\n" + lock.path(percentEncoded: false)
        case .aLink(let link): "link\n" + link.path(percentEncoded: false)
        }
    }

    /// The problem a refusal log stored as `detail`, or nil for one this version can't read.
    init?(detail: String) {
        let lines = detail.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 2 else { return nil }
        let path = URL(filePath: lines[1])
        switch lines[0] {
        case "folder": self = .folderNotWritable(path)
        case "disk":
            guard lines.count == 3, let free = Int64(lines[1]), let needed = Int64(lines[2]) else { return nil }
            self = .diskFull(free: free, needed: needed)
        case "free-space": self = .freeSpaceNotKnown(path)
        case "journal": self = .journalUnreadable(path)
        case "journal-write": self = .journalNotWritable(path)
        case "lock": self = .lockClosed(path)
        case "link": self = .aLink(path)
        default: return nil
        }
    }
}
