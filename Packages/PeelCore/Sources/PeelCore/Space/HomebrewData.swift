import Foundation
internal import PeelPrivileged

/// What the formulas Homebrew installed keep in its `var` folder, which `brew uninstall` leaves: it warns about a
/// formula's `etc` folder and says nothing of `var` (`uninstall.rb`). The services' logs there are an area of their
/// own, and `homebrew` is Homebrew's own.
enum HomebrewData {
    /// Where Homebrew is: the prefix of the `brew` chosen in Settings, `/opt/homebrew`, which nothing else uses, and
    /// `/usr/local` while Homebrew's Cellar is there, since other programs install there too.
    static func prefixes(home: URL, root: URL) -> [URL] {
        let chosen = HomebrewChoice(url: HomebrewChoice.url(inHome: home)).load()
            .map { $0.deletingLastPathComponent().deletingLastPathComponent() }
        let local = root.appending(path: "usr/local", directoryHint: .isDirectory)
        let prefixes = [
            chosen,
            root.appending(path: "opt/homebrew", directoryHint: .isDirectory),
            local.appending(path: "Cellar").isRealFolder ? local : nil,
        ]
        var seen: Set<String> = []
        return prefixes.compactMap(\.self).filter { seen.insert(PathPattern.comparablePath(of: $0)).inserted }
    }

    /// The note on each place no installed formula of its own Homebrew names, and none on the places of a Homebrew
    /// whose formulas' files can't all be read.
    static func notes(on places: [URL]) -> [URL: SpaceItem.PlaceNote] {
        var notes: [URL: SpaceItem.PlaceNote] = [:]
        let byPrefix = Dictionary(grouping: places) { $0.deletingLastPathComponent().deletingLastPathComponent() }
        for (prefix, folders) in byPrefix {
            guard let named = foldersNamedByInstalledFormulae(in: prefix) else { continue }
            for folder in folders where !named.contains(folder.lastPathComponent) {
                notes[folder] = .namedByNoInstalledFormula
            }
        }
        return notes
    }

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
