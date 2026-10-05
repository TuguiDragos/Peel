import Foundation

enum ElectronUpdater {
    static func feedURL(fromConfiguration text: String) -> URL? {
        let fields = topLevelFields(in: text)
        let file = "\(fields["channel"] ?? "latest")-mac.yml"

        switch fields["provider"] {
        case "generic":
            guard let base = fields["url"].flatMap(URL.init(string:)), base.scheme == "https" else { return nil }
            return base.appending(path: file)
        case "github":
            // A `host` other than github.com is a company's own server. The owner and repository were never meant
            // to leave that server, so they are not sent to github.com.
            guard fields["host"] == nil || fields["host"] == "github.com" else { return nil }
            guard let owner = fields["owner"], let repository = fields["repo"] else { return nil }
            return URL(string: "https://github.com/\(owner)/\(repository)/releases/latest/download/\(file)")
        default:
            return nil
        }
    }

    static func version(fromFeed text: String) -> String? {
        topLevelFields(in: text)["version"]
    }

    /// What is new in the release: the feed's top-level `releaseNotes`, which electron-builder writes from the app's
    /// release notes, in Markdown, as a plain, quoted or block scalar. The list it writes instead when told to keep
    /// every version's notes is not read.
    static func releaseNotes(fromFeed text: String) -> ReleaseNotes? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let key = "releaseNotes:"
        guard let start = lines.firstIndex(where: { $0.hasPrefix(key) }) else { return nil }
        let value = lines[start].dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        let notes: String
        switch value.first {
        case "|", ">":
            let block = lines[(start + 1)...].prefix { $0.isEmpty || $0.first?.isWhitespace == true }
            notes = scalar(of: block, keepingLineBreaks: value.first == "|")
        case "'":
            guard value.count >= 2, value.hasSuffix("'") else { return nil }
            notes = String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        case "\"":
            guard value.count >= 2, value.hasSuffix("\"") else { return nil }
            notes = unescaped(value.dropFirst().dropLast())
        case nil:
            return nil
        default:
            notes = value
        }
        return ReleaseNotes(notes, format: .markdown)
    }

    /// A block scalar's lines without their common indentation: kept as lines for `|`, and folded into paragraphs
    /// for `>`, where an empty line is a line break.
    private static func scalar(of block: ArraySlice<Substring>, keepingLineBreaks: Bool) -> String {
        func indentation(_ line: Substring) -> Int { line.prefix { $0 == " " }.count }
        let written = block.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let common = written.map(indentation).min() ?? 0
        let lines = block.map { String($0.dropFirst(min(common, indentation($0)))) }
        guard !keepingLineBreaks else { return lines.joined(separator: "\n") }
        return lines.reduce(into: "") { folded, line in
            if line.isEmpty {
                folded += "\n"
            } else {
                if !folded.isEmpty, folded.last != "\n" { folded += " " }
                folded += line
            }
        }
    }

    /// A double-quoted scalar's text, with YAML's escapes read: a line break, a tab, a quote, a backslash, a slash and
    /// a character by its code.
    private static func unescaped(_ quoted: Substring) -> String {
        var text = ""
        var characters = quoted.makeIterator()
        while let character = characters.next() {
            guard character == "\\", let escaped = characters.next() else {
                text.append(character)
                continue
            }
            switch escaped {
            case "n": text.append("\n")
            case "t": text.append("\t")
            case "u":
                let digits = String((0..<4).compactMap { _ in characters.next() })
                if let code = UInt32(digits, radix: 16), let scalar = Unicode.Scalar(code) {
                    text.unicodeScalars.append(scalar)
                }
            default: text.append(escaped)
            }
        }
        return text
    }

    private static func topLevelFields(in text: String) -> [String: String] {
        var fields: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) where line.first?.isWhitespace == false {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
            if !key.isEmpty, !value.isEmpty {
                fields[key] = value
            }
        }
        return fields
    }
}
