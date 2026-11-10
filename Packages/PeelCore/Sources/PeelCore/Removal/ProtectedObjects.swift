import Darwin
import Foundation
import Synchronization

/// The protected folders, known by device and inode rather than by path. A rule that compares paths as text
/// can be fooled by another spelling of the same folder: a different case, a link, `/private`, or a letter
/// the disk folds. So `RemovalGuard` asks the same questions again of the objects themselves, read from the
/// disk once for the protected folders and once for each folder an item sits in.
struct ProtectedObjects: Sendable {
    typealias Object = FileIdentity.Link
    /// Reads the object at a path, through a link or not.
    typealias Read = @Sendable (_ path: String, _ followingLinks: Bool) -> Object?

    /// Nothing at or inside one of these may be removed.
    private let trees: Set<Object>
    /// These folders may not be removed themselves, but what is inside them may be.
    private let folders: Set<Object>
    /// Every folder that contains a tree, since removing one would take the tree with it.
    private let holders: Set<Object>
    /// Cached answers to whether a folder is, or sits inside, a tree. A removal can take hundreds of items from
    /// one folder, and each answer costs two `stat` calls per folder on the way up, so answers are kept for as
    /// long as this guard lives.
    private let known = Answers()
    private let read: Read

    private final class Answers: Sendable {
        let isInsideATree = Mutex<[String: Bool]>([:])
    }

    /// Many trees sit in the same folders, so each path is read once.
    init(
        trees: some Sequence<String>, folders: some Sequence<String>,
        read: @escaping Read = ProtectedObjects.object(at:followingLinks:)
    ) {
        var objects: [String: Set<Object>] = [:]
        func objectsAt(_ path: String) -> Set<Object> {
            if let known = objects[path] { return known }
            let found = Self.objects(at: path, reading: read)
            objects[path] = found
            return found
        }
        let trees = Set(trees)
        self.trees = Set(trees.flatMap(objectsAt))
        holders = Set(Set(trees.flatMap(Self.ancestors)).flatMap(objectsAt))
        self.folders = Set(Set(folders).flatMap(objectsAt))
        self.read = read
    }

    /// Why the item may not be removed: it is a tree or sits inside one, it is a protected folder, or it holds a
    /// tree. `located` is the path as the kernel names it, so its folders are the real ones. An item that does not
    /// exist yet has no inode: only the folders above it are checked, and the rules that read paths judge the rest.
    func refusal(of located: String) -> GuardRefusal? {
        if let item = read(located, false) {
            if trees.contains(item) { return .protectedLocation }
            if folders.contains(item) { return .staysItself }
            if holders.contains(item) { return .holdsProtectedData }
        }
        return isInsideATree((located as NSString).deletingLastPathComponent) ? .protectedLocation : nil
    }

    private func isInsideATree(_ folder: String) -> Bool {
        if let answer = known.isInsideATree.withLock({ $0[folder] }) { return answer }
        let answer = ([folder] + Self.ancestors(of: folder)).contains {
            !Self.objects(at: $0, reading: read).isDisjoint(with: trees)
        }
        known.isInsideATree.withLock { $0[folder] = answer }
        return answer
    }

    /// Returns every folder above `path`, splitting on the slash alone as `NSString` does. A `String` treats a
    /// slash followed by a combining mark as one character, so a prefix test would miss where a folder ends.
    static func ancestors(of path: String) -> [String] {
        var ancestors: [String] = []
        var folder = (path as NSString).deletingLastPathComponent
        while folder != "/", !folder.isEmpty {
            ancestors.append(folder)
            folder = (folder as NSString).deletingLastPathComponent
        }
        return ancestors
    }

    /// The link itself and what it leads to: the link is what would move, and the target is what would be lost.
    private static func objects(at path: String, reading read: Read) -> Set<Object> {
        Set([read(path, false), read(path, true)].compactMap(\.self))
    }

    static func object(at path: String, followingLinks: Bool) -> Object? {
        var info = stat()
        guard (followingLinks ? stat(path, &info) : lstat(path, &info)) == 0 else { return nil }
        return Object(device: info.st_dev, inode: info.st_ino)
    }
}
