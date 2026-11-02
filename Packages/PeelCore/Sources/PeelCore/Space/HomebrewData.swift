import Foundation
internal import PeelPrivileged

/// What the formulas Homebrew installed keep in its `var` folder, which `brew uninstall` leaves: it warns about a
/// formula's `etc` folder and says nothing of `var` (`uninstall.rb`). The services' logs there are an area of their
/// own, and `homebrew` is Homebrew's own.
enum HomebrewData {
    /// What `prefix/var` holds but the services' logs and Homebrew's own folder.
    static func folders(in prefix: URL) -> [URL] {
        let folder = prefix.appending(path: "var", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.filter { !["log", "homebrew"].contains($0) && !ProtectedData.isLeftByFinder($0) }.sorted()
            .map { folder.appending(path: $0) }
    }

    /// The first name under `var` each installed formula writes in its own file, which Homebrew keeps in every keg as
    /// `.brew/<formula>.rb` (`formula_installer.rb`), or nil when one of them can't be read, since a folder is then not
    /// known to be named by none.
    static func foldersNamedByInstalledFormulae(in prefix: URL) -> Set<String>? {
        let cellar = prefix.appending(path: "Cellar", directoryHint: .isDirectory)
        guard let formulae = try? FileManager.default.contentsOfDirectory(atPath: cellar.path(percentEncoded: false))
        else { return nil }
        var named: Set<String> = []
        for formula in formulae where !ProtectedData.isLeftByFinder(formula) {
            let rack = cellar.appending(path: formula, directoryHint: .isDirectory)
            guard let kegs = try? FileManager.default.contentsOfDirectory(atPath: rack.path(percentEncoded: false))
            else { return nil }
            for keg in kegs where !ProtectedData.isLeftByFinder(keg) {
                guard let data = BoundedRead.data(at: rack.appending(path: "\(keg)/.brew/\(formula).rb")) else {
                    return nil
                }
                named.formUnion(names(in: String(decoding: data, as: UTF8.self), formula: formula))
            }
        }
        return named
    }

    /// What a formula's Ruby names under `var`: `var/"mysql"` and `var/'mysql'`, and `var/name` or `var/"#{name}"`, its
    /// own name.
    static func names(in source: String, formula: String) -> Set<String> {
        guard let path = try? Regex(##"var\s*/\s*(?:"([^"#/]+)|'([^'/]+)|("#\{name\}|name\b))"##) else { return [] }
        return Set(source.matches(of: path).compactMap { match in
            if let quoted = match.output[1].substring ?? match.output[2].substring { return String(quoted) }
            return match.output[3].substring == nil ? nil : formula
        })
    }
}
