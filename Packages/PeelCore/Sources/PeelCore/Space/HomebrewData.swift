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
    /// whose formulas' files can't all be read, nor in `/usr/local`, where other programs install too.
    static func notes(on places: [URL]) -> [URL: SpaceItem.PlaceNote] {
        var notes: [URL: SpaceItem.PlaceNote] = [:]
        let byPrefix = Dictionary(grouping: places) { $0.deletingLastPathComponent().deletingLastPathComponent() }
        for (prefix, folders) in byPrefix
        where PathComponents.of(prefix.path(percentEncoded: false)).suffix(2) != ["usr", "local"] {
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
                guard let data = BoundedRead.data(at: rack.appending(path: "\(keg)/.brew/\(formula).rb")),
                      let names = names(in: String(decoding: data, as: UTF8.self), formula: formula)
                else { return nil }
                named.formUnion(names)
            }
        }
        return named
    }

    /// The first folder under `var` each of a formula's mentions of it names, or nil when one names none this can
    /// read, as `--localstatedir=#{var}` or `working_dir var` leave the folders to the program. Read: `var/"mysql"`,
    /// `var/'mysql'`, `"#{var}/mysql"`, and the install steps `init_data_dir` or `mkdir_p` with `base: :var`
    /// (`install_steps.rb`), each with `name` or `formula_name` for the formula's own. Comment lines say nothing.
    static func names(in source: String, formula: String) -> Set<String>? {
        let code = source.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.drop { $0 == " " || $0 == "\t" }.hasPrefix("#") }
            .joined(separator: "\n")
        var names: Set<String> = []
        var read: [Range<String.Index>] = []
        for form in readableForms.compactMap({ try? Regex($0) }) {
            for match in code.matches(of: form) {
                read.append(match.range)
                let named = match.output.dropFirst().lazy.compactMap { $0.substring.map(String.init) }.first ?? "name"
                names.insert(["name", "formula_name"].contains(named) || named.hasSuffix("#{name}") ? formula : named)
            }
        }
        let isWordCharacter = { (character: Character) in character.isLetter || character.isNumber || character == "_" }
        for mention in code.ranges(of: "var") {
            let before = mention.lowerBound == code.startIndex ? nil : code[code.index(before: mention.lowerBound)]
            let after = mention.upperBound == code.endIndex ? nil : code[mention.upperBound]
            // `/var` is the system's own folder, `x.var` another object's, and `my_var` another name.
            guard before.map({ !isWordCharacter($0) && !"@$/.".contains($0) }) ?? true,
                  after.map({ !isWordCharacter($0) }) ?? true
            else { continue }
            guard read.contains(where: { $0.contains(mention.lowerBound) }) else { return nil }
        }
        return names
    }

    /// How a formula names a folder under `var`, each with the name it gives: `var/"x"`, `var/'x'`, `var/name`;
    /// `#{var}/x` or `#{var}/#{name}` inside a string; and an install step with `base: :var`.
    private static let readableForms = [
        ##"var\s*/\s*(?:"([^"#/]+)|'([^'/]+)|("#\{name\}|name\b))"##,
        ##"#\{var\}/(?:(#\{name\})|([^/"'\s#}\\]+))"##,
        ##"\b(?:init_data_dir|mkdir_p|mkdir|touch)\s*\(?\s*(?:"([^"#/]+)[^"\n]*"|(formula_name|name)\b)[^\n]*?\bbase:\s*:var\b"##,
    ]
}
