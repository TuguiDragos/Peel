public import Darwin
public import Foundation

/// A directory held open by a descriptor, opened one component at a time without following a symbolic
/// link. What is checked and what is then acted on are the same object: if a directory is swapped for a
/// link afterwards, nothing is redirected, because the descriptor still refers to what was checked.
///
/// It is opened for search only, and nothing here lists a directory. Without Full Disk Access, macOS refuses
/// to open `~/.Trash` for reading (`EPERM`), but allows opening it for search, and `fstatat` and renames made
/// through that descriptor.
public final class DirectoryHandle: Sendable {
    private static let flags = O_SEARCH | O_NOFOLLOW | O_CLOEXEC

    public let path: String
    let descriptor: Int32

    private init(path: String, descriptor: Int32) {
        self.path = path
        self.descriptor = descriptor
    }

    deinit { close(descriptor) }

    /// Opens a path that `realpath` has already resolved, so it holds no links of its own. A component
    /// that has become a link since then fails here rather than redirecting the operation.
    static func at(canonical path: String) -> DirectoryHandle? {
        try? open(canonical: path).get()
    }

    private static func open(canonical path: String) -> Result<DirectoryHandle, POSIXError> {
        var descriptor = Darwin.open("/", O_SEARCH | O_CLOEXEC)
        guard descriptor >= 0 else { return .failure(.last) }
        for component in PathComponents.of(path) {
            let next = component.withCString { openat(descriptor, $0, flags) }
            let failure = POSIXError.last
            close(descriptor)
            guard next >= 0 else { return .failure(failure) }
            descriptor = next
        }
        return .success(DirectoryHandle(path: path, descriptor: descriptor))
    }

    /// Opens the folder at `path`. Links in `path` are resolved once, here, and the result is then opened
    /// without following any link.
    public static func at(_ path: String) -> Result<DirectoryHandle, POSIXError> {
        guard let real = PrivilegedPathPolicy.realPath(path) else { return .failure(.last) }
        return open(canonical: real)
    }

    /// What the kernel calls this folder now, wherever it has been moved to since it was opened.
    public var currentPath: String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard fcntl(descriptor, F_GETPATH, &buffer) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// A subdirectory, opened through this descriptor and refusing a symbolic link left in its place.
    func child(_ name: String) -> DirectoryHandle? {
        let descriptor = name.withCString { openat(self.descriptor, $0, Self.flags) }
        guard descriptor >= 0 else { return nil }
        return DirectoryHandle(path: path == "/" ? "/" + name : path + "/" + name, descriptor: descriptor)
    }

    /// The owner of the directory itself, read through the descriptor.
    public func ownerIdentifier() -> uid_t? {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return nil }
        return info.st_uid
    }
}

/// Identifies an item by its device, inode, and birth time. A rename or a move within its volume keeps all
/// three, and the birth time tells apart an item that reuses a freed inode number.
public struct ItemIdentity: Codable, Hashable, Sendable {
    let device: Int64
    public let inode: UInt64
    /// When the item was made, in nanoseconds since 1970.
    public let birth: Int64

    init(_ info: stat) {
        device = Int64(info.st_dev)
        inode = UInt64(info.st_ino)
        birth = Int64(info.st_birthtimespec.tv_sec) * 1_000_000_000 + Int64(info.st_birthtimespec.tv_nsec)
    }

    /// The identity of the item at `path` itself, never of what a link there leads to.
    public init?(ofItemAt path: String) {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        self.init(info)
    }
}

/// An item named inside a `DirectoryHandle`. The item holds its parent's handle, so the parent's
/// descriptor stays open for as long as the item exists.
public final class OpenItem: Sendable {
    public let path: String
    public let name: String
    public let parent: DirectoryHandle
    /// Read through the parent's descriptor without following a link. Nil for a place nothing is in yet.
    public let identity: ItemIdentity?
    let owner: uid_t?
    let mode: mode_t?

    init(path: String, name: String, parent: DirectoryHandle, status: stat? = nil) {
        self.path = path
        self.name = name
        self.parent = parent
        identity = status.map(ItemIdentity.init)
        owner = status?.st_uid
        mode = status?.st_mode
    }

    /// The item at `path`, held through a descriptor on the folder it sits in. Links in the folder's path are
    /// resolved once, here, and the last component is never followed.
    public static func at(_ path: String) -> Result<OpenItem, POSIXError> {
        guard path.hasPrefix("/"), PrivilegedPathPolicy.isPlainlyReadable(path) else { return .failure(POSIXError(.EINVAL)) }
        let components = PathComponents.of(path)
        guard let name = components.last, !components.contains(where: { $0 == "." || $0 == ".." }) else {
            return .failure(POSIXError(.EINVAL))
        }
        return DirectoryHandle.at("/" + components.dropLast().joined(separator: "/")).flatMap { parent in
            var info = stat()
            guard name.withCString({ fstatat(parent.descriptor, $0, &info, AT_SYMLINK_NOFOLLOW) }) == 0 else { return .failure(.last) }
            return .success(OpenItem(path: (parent.path == "/" ? "" : parent.path) + "/" + name, name: name, parent: parent, status: info))
        }
    }
}

extension POSIXError {
    /// The error `errno` holds for the call that just failed. Read it before any other call can change `errno`.
    static var last: POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}
