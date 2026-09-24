/// Reads a path name by name. `String` compares `Character`s, and a slash followed by a combining mark is one
/// `Character`: `split(separator: "/")` then leaves that slash inside a name, where the kernel still reads it as a
/// separator, and `hasPrefix("…/Keychains/")` misses a file whose name begins with the mark. So a path is split at
/// each slash byte, and one path is inside another when its names begin with the other's names. Names are compared
/// as strings, so two spellings of the same letter (composed or not) still match, as they do on the disk.
public enum PathComponents {
    /// The folder and file names in `path`, split at each slash byte. Empty names are left out.
    public static func of(_ path: some StringProtocol) -> [String] {
        path.utf8.split(separator: UInt8(ascii: "/")).map { String(decoding: $0, as: UTF8.self) }
    }

    /// True when `path` is `folder` or sits somewhere inside it.
    public static func isPath(_ path: some StringProtocol, atOrInside folder: some StringProtocol) -> Bool {
        of(path).starts(with: of(folder))
    }

    /// True when `path` sits somewhere inside `folder`, and is not `folder` itself.
    public static func isPath(_ path: some StringProtocol, inside folder: some StringProtocol) -> Bool {
        let names = of(path), folderNames = of(folder)
        return names.count > folderNames.count && names.starts(with: folderNames)
    }
}
