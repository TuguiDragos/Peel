import Foundation

/// What `pkgutil` prints as property lists, for the stand-ins the tests pass in its place.
enum PkgutilAnswer {
    /// `pkgutil --pkgs-plist`: the identifiers of the installed packages.
    static func packages(_ identifiers: String...) -> String {
        xml(identifiers)
    }

    /// `pkgutil --file-info-plist <path>`: the packages whose receipts list `path`.
    static func fileInfo(_ path: String, packages: String...) -> String {
        xml(["path": path, "path-info": packages.map { ["pkgid": $0] }] as [String: Any])
    }

    private static func xml(_ plist: Any) -> String {
        let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        return String(decoding: data, as: UTF8.self)
    }
}
