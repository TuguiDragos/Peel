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

    /// `pkgutil --pkg-info-plist <identifier>`: where the package installed what it lists.
    static func packageInfo(_ identifier: String, volume: String = "/", location: String) -> String {
        xml(["pkgid": identifier, "volume": volume, "install-location": location])
    }

    private static func xml(_ plist: Any) -> String {
        let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        return String(decoding: data, as: UTF8.self)
    }
}
