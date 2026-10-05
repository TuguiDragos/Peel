import Foundation

/// Where the tools' own configuration files say a cache Developer lists has moved: the files each tool reads, which
/// its own `config set` writes, read here and never by running a tool. A value counts only when it names a place
/// without the environment the tool runs in, such as an absolute path or one from the home folder.
struct ToolSettings: Sendable {
    /// npm's `cache` in `~/.npmrc`.
    let npmCache: URL?
    /// Yarn 1's cache root: `--cache-folder` or `cache-folder` in `~/.yarnrc`, then `cache-folder` in `~/.npmrc`.
    let yarnCacheRoot: URL?
    /// Yarn 2 and later's `globalFolder` in `~/.yarnrc.yml`.
    let yarnGlobalFolder: URL?
    /// pnpm's store folders: `storeDir` in the `config.yaml` pnpm 11 reads, and `store-dir` in the `rc` file and in
    /// `~/.npmrc` pnpm 10 reads.
    let pnpmStoreFolders: [URL]
    /// Go's module cache: `GOMODCACHE` in the file `go env -w` writes, else `pkg/mod` in the first folder of its
    /// `GOPATH`.
    let goModuleCache: URL?
    /// Go's build cache: `GOCACHE` in the same file.
    let goBuildCache: URL?

    init(home: URL) {
        let npmrc = Self.text(at: home.appending(path: ".npmrc"))
        let yarnrc = Self.text(at: home.appending(path: ".yarnrc"))
        let pnpm = home.appending(path: "Library/Preferences/pnpm", directoryHint: .isDirectory)
        let goEnvironment = Self.text(at: home.appending(path: "Library/Application Support/go/env"))

        npmCache = npmrc.flatMap { Self.iniValue(of: "cache", in: $0) }.flatMap { Self.npmPlace($0, home: home) }

        // An argument in `.yarnrc` is taken as typed on the command line, so only an absolute one names a place. A
        // setting there is taken from the folder of the file, and one in `.npmrc` as npm takes a path.
        let argument = yarnrc.flatMap { Self.yarnrcValue(of: "--cache-folder", in: $0) }.flatMap(Self.absolute)
        let setting = yarnrc.flatMap { Self.yarnrcValue(of: "cache-folder", in: $0) }
            .map { Self.folder($0, from: home) }
        let fromNpm = npmrc.flatMap { Self.iniValue(of: "cache-folder", in: $0) }
            .flatMap { Self.npmPlace($0, home: home) }
        yarnCacheRoot = argument ?? setting ?? fromNpm

        yarnGlobalFolder = Self.text(at: home.appending(path: ".yarnrc.yml"))
            .flatMap { Self.yamlValue(of: "globalFolder", in: $0) }
            .flatMap { Self.replacingHome(in: $0, home: home, defaults: true) }
            .map { Self.folder($0, from: home) }

        let pnpmEleven = Self.text(at: pnpm.appending(path: "config.yaml"))
            .flatMap { Self.yamlValue(of: "storeDir", in: $0) }
            .flatMap { $0.contains("${") ? nil : Self.place($0, home: home) }
        let pnpmTen = [Self.text(at: pnpm.appending(path: "rc")), npmrc].compactMap { text in
            text.flatMap { Self.iniValue(of: "store-dir", in: $0) }.flatMap { Self.npmPlace($0, home: home) }
        }
        pnpmStoreFolders = [pnpmEleven].compactMap(\.self) + pnpmTen

        // Go takes an empty value as unset, and a relative one as an error.
        let goValue = { (key: String) in
            goEnvironment.flatMap { Self.goEnvironmentValue(of: key, in: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        let goPath = goValue("GOPATH")?.split(separator: ":", omittingEmptySubsequences: false).first
            .flatMap { $0.isEmpty ? nil : String($0) + "/pkg/mod" }
        goModuleCache = (goValue("GOMODCACHE") ?? goPath).flatMap(Self.absolute)
        goBuildCache = goValue("GOCACHE").flatMap(Self.absolute)
    }

    /// A configuration file is a few lines; a megabyte is far beyond any real one.
    private static func text(at url: URL) -> String? {
        BoundedRead.data(at: url, maximum: 1_048_576).map { String(decoding: $0, as: UTF8.self) }
    }

    private static func absolute(_ path: String) -> URL? {
        path.hasPrefix("/") ? URL(filePath: path, directoryHint: .isDirectory).standardized : nil
    }

    /// A path as a tool takes it from its configuration file: relative to the folder the file is in.
    private static func folder(_ path: String, from base: URL) -> URL {
        URL(filePath: path, directoryHint: .isDirectory, relativeTo: base).absoluteURL.standardized
    }

    /// An absolute path, or one that starts from the home folder with `~/`.
    private static func place(_ path: String, home: URL) -> URL? {
        guard path.hasPrefix("~/") else { return absolute(path) }
        return home.appending(path: String(path.dropFirst(2)), directoryHint: .isDirectory).standardized
    }

    /// A path as npm and pnpm 10 take it (`@npmcli/config`'s `parse-field.js`): `${NAME}` from the environment, then
    /// `~/` from the home folder. A relative path is taken from the folder the tool runs in, which is not known here.
    private static func npmPlace(_ value: String, home: URL) -> URL? {
        replacingHome(in: value, home: home, defaults: false).flatMap { place($0, home: home) }
    }

    /// `value` with `${HOME}` taken as the home folder, or nil when it names another variable, whose value is the
    /// environment's the tool runs in. npm writes `${HOME?}` for an empty value when unset, and Yarn, with `defaults`,
    /// `${HOME:-fallback}` and `${HOME-fallback}` for a fallback: the home folder is always set.
    static func replacingHome(in value: String, home: URL, defaults: Bool) -> String? {
        guard !value.contains("\\") else { return nil }
        var homePath = home.path(percentEncoded: false)
        while homePath.count > 1, homePath.hasSuffix("/") { homePath.removeLast() }
        var result = ""
        var rest = Substring(value)
        while let start = rest.range(of: "${") {
            result += rest[..<start.lowerBound]
            guard let end = rest[start.upperBound...].firstIndex(of: "}") else { return nil }
            let expression = rest[start.upperBound..<end]
            let namesHome = defaults
                ? expression == "HOME" || expression.hasPrefix("HOME:-") || expression.hasPrefix("HOME-")
                : expression == "HOME" || expression == "HOME?"
            guard namesHome, !expression.contains("$") else { return nil }
            result += homePath
            rest = rest[rest.index(after: end)...]
        }
        return result + rest
    }

    // MARK: - The formats

    /// The value of a top-level `key` in an INI file as npm reads `.npmrc` (`ini` 7, `decode`): the last one before
    /// any `[section]`. A quoted value is decoded, and an unquoted one ends at the first `;` or `#` not escaped.
    static func iniValue(of key: String, in text: String) -> String? {
        var found: String?
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let content = line.drop { $0.isWhitespace }
            if content.isEmpty || content.first == ";" || content.first == "#" { continue }
            // Every line after a section belongs to it.
            if line.first == "[", let close = line.firstIndex(of: "]"),
               line[line.index(after: close)...].allSatisfy(\.isWhitespace) {
                break
            }
            guard let equals = line.firstIndex(of: "="), iniUnquoted(line[..<equals]) == key else { continue }
            found = iniUnquoted(line[line.index(after: equals)...])
        }
        return found
    }

    private static func iniUnquoted(_ raw: Substring) -> String {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if value.count > 1, value.hasPrefix("\""), value.hasSuffix("\"") {
            return jsonString(value) ?? value
        }
        if value.count > 1, value.hasPrefix("'"), value.hasSuffix("'") {
            return String(value.dropFirst().dropLast())
        }
        var result = ""
        var isEscaped = false
        for character in value {
            if isEscaped {
                result += ";#\\".contains(character) ? String(character) : "\\" + String(character)
                isEscaped = false
            } else if character == ";" || character == "#" {
                break
            } else if character == "\\" {
                isEscaped = true
            } else {
                result.append(character)
            }
        }
        return (isEscaped ? result + "\\" : result).trimmingCharacters(in: .whitespaces)
    }

    /// The value of a top-level `key` in Yarn 1's `.yarnrc` (its `lockfile/parse.js`): `key value` on one line, the
    /// value a quoted string or a word that ends at a space, a colon or a comma. The last one counts.
    static func yarnrcValue(of key: String, in text: String) -> String? {
        var found: String?
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            guard let (name, rest) = yarnToken(line), name == key,
                  let (value, _) = yarnToken(rest.drop { $0 == " " })
            else { continue }
            found = value
        }
        return found
    }

    /// The string a line starts with in Yarn 1's syntax, and what follows it. A line that starts with a space is
    /// inside a block, and one that starts with `#` is a comment.
    private static func yarnToken(_ text: Substring) -> (String, Substring)? {
        if text.first == "\"" {
            guard let end = closingQuote(in: text), let string = jsonString(String(text[...end])) else { return nil }
            return (string, text[text.index(after: end)...])
        }
        guard let first = text.first, first.isASCII, first.isLetter || "/.-".contains(first) else { return nil }
        let end = text.firstIndex { " :,".contains($0) } ?? text.endIndex
        return (String(text[..<end]), text[end...])
    }

    /// The value of a top-level `key: value` line of a YAML file: a plain, single quoted or double quoted scalar,
    /// with a comment after it or not. A nested block, a flow collection or anything else is no path, and gives nil.
    static func yamlValue(of key: String, in text: String) -> String? {
        var found: String?
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            guard line.hasPrefix(key + ":") else { continue }
            let value = line.dropFirst(key.count + 1)
            guard value.isEmpty || value.first == " " || value.first == "\t" else { continue }
            found = yamlScalar(Substring(value.trimmingCharacters(in: .whitespaces)))
        }
        return found
    }

    private static func yamlScalar(_ value: Substring) -> String? {
        if value.first == "\"" {
            guard let end = closingQuote(in: value), isComment(value[value.index(after: end)...]) else { return nil }
            return jsonString(String(value[...end]))
        }
        if value.first == "'" {
            // A quote inside is written twice.
            var result = ""
            var index = value.index(after: value.startIndex)
            while index < value.endIndex {
                let next = value.index(after: index)
                if value[index] != "'" {
                    result.append(value[index])
                    index = next
                } else if next < value.endIndex, value[next] == "'" {
                    result.append("'")
                    index = value.index(after: next)
                } else {
                    return isComment(value[next...]) ? result : nil
                }
            }
            return nil
        }
        guard let first = value.first, !"[]{}&*!|>%@`#,?\"'".contains(first) else { return nil }
        let plain = value.range(of: " #").map { value[..<$0.lowerBound] } ?? value
        return plain.trimmingCharacters(in: .whitespaces)
    }

    /// The double quote that closes the string `text` opens, past any quote a backslash escapes.
    private static func closingQuote(in text: Substring) -> Substring.Index? {
        var index = text.index(after: text.startIndex)
        while index < text.endIndex {
            if text[index] == "\\" {
                index = text.index(after: index)
                guard index < text.endIndex else { return nil }
            } else if text[index] == "\"" {
                return index
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func isComment(_ rest: Substring) -> Bool {
        let rest = rest.drop { $0 == " " || $0 == "\t" }
        return rest.isEmpty || rest.first == "#"
    }

    /// The value of `KEY` in the file `go env -w` writes, as Go reads it (`cmd/go/internal/cfg`, `readEnvFile`): a
    /// line `KEY=value` whose name starts with a capital letter, the value taken as written. The last one counts.
    static func goEnvironmentValue(of key: String, in text: String) -> String? {
        var found: String?
        for line in text.split(separator: "\n") {
            guard let first = line.first, first.isASCII, first.isUppercase, let equals = line.firstIndex(of: "="),
                  line[..<equals] == key
            else { continue }
            found = String(line[line.index(after: equals)...])
        }
        return found
    }

    private static func jsonString(_ quoted: String) -> String? {
        try? JSONSerialization.jsonObject(with: Data(quoted.utf8), options: .fragmentsAllowed) as? String
    }
}
