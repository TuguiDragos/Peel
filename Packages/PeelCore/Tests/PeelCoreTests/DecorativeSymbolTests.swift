import Foundation
import Testing

struct DecorativeSymbolTests {
    /// macOS describes these by an action ("move", "copy", "build", "forward", "new folder") or by their own name, so
    /// VoiceOver says that word for an image of one that Peel doesn't label.
    static let misleading: Set = [
        "folder", "folder.fill", "questionmark.app", "doc.on.doc", "hammer", "chevron.right", "folder.badge.plus",
        "exclamationmark",
    ]
    static let ownCovers = [".accessibilityHidden(true)", ".accessibilityLabel(", ".accessibilityRepresentation"]
    static let ancestorCovers = [
        ".hidden()", ".accessibilityElement(children: .ignore)", ".accessibilityLabel(", ".accessibilityRepresentation",
    ]

    @Test func aSymbolMacOSNamesByAnActionIsNeverLeftForVoiceOver() throws {
        let root = LineLengthTests.repository.path(percentEncoded: false)
        var found: [String] = []
        for file in try LineLengthTests.swiftFiles()
        where file.path(percentEncoded: false).dropFirst(root.count).hasPrefix("Peel/") {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                guard let name = Self.symbols(in: line).first(where: Self.misleading.contains) else { continue }
                let indent = Self.indent(of: line)
                let before = lines[max(0, index - 3)...index].joined(separator: "\n")
                if before.contains("icon:") || before.contains("label:") || before.contains("Label {") { continue }
                let own = Self.ownModifiers(of: index, in: lines)
                if own.contains(where: { line in Self.ownCovers.contains { line.contains($0) } }) { continue }
                // A modifier of another branch of the same `if` or `switch` covers nothing here.
                let following = lines[(index + 1)..<min(lines.count, index + 30)].prefix { line in
                    let code = line.trimmingCharacters(in: .whitespaces)
                    return Self.indent(of: line) >= indent
                        || !(code.hasPrefix("} else") || code.hasPrefix("case ") || code.hasPrefix("default:"))
                }
                let ancestors = following.filter { Self.indent(of: $0) < indent }
                if ancestors.contains(where: { line in Self.ancestorCovers.contains { line.contains($0) } }) {
                    continue
                }
                found.append("\(file.path(percentEncoded: false).dropFirst(root.count)):\(index + 1) \(name)")
            }
        }
        #expect(found.isEmpty, "VoiceOver would say macOS's word for these symbols: \(found)")
    }

    @Test func aNoticeTellsVoiceOverItsKindWhicheverSymbolItDraws() throws {
        let text = try String(
            contentsOf: LineLengthTests.repository.appending(path: "Peel/Views/Notice.swift"), encoding: .utf8
        )
        #expect(text.contains(".accessibilityRepresentation { Image(systemName: kindSymbol) }"))
        #expect(!text.contains(".accessibilityHidden("))
    }

    @Test func aFilterThatFillsItsSymbolTellsVoiceOverItIsOn() throws {
        let root = LineLengthTests.repository.path(percentEncoded: false)
        var silent: [String] = []
        for file in try LineLengthTests.swiftFiles()
        where file.path(percentEncoded: false).dropFirst(root.count).hasPrefix("Peel/") {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains("decrease.circle.fill"), !text.contains("filter](inflect: true) on") {
                silent.append(String(file.path(percentEncoded: false).dropFirst(root.count)))
            }
        }
        #expect(silent.isEmpty, "Only the filled symbol says these lists are filtered: \(silent)")
    }

    @Test func aMissingAppsStandInTellsVoiceOverItIsNotInstalled() throws {
        let root = LineLengthTests.repository.path(percentEncoded: false)
        var found: [String] = []
        for file in try LineLengthTests.swiftFiles()
        where file.path(percentEncoded: false).dropFirst(root.count).hasPrefix("Peel/") {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where Self.symbols(in: line).contains("questionmark.app") {
                let says = Self.ownModifiers(of: index, in: lines).contains { $0.contains(#"Text("Not installed")"#) }
                if !says { found.append("\(file.path(percentEncoded: false).dropFirst(root.count)):\(index + 1)") }
            }
        }
        #expect(found.isEmpty, "The only sign that the app isn't on this Mac says nothing to VoiceOver: \(found)")
    }

    /// The modifiers written on the image at `index` itself, each on a line of its own below it.
    private static func ownModifiers(of index: Int, in lines: [String]) -> ArraySlice<String> {
        let indent = indent(of: lines[index])
        return lines[(index + 1)..<min(lines.count, index + 30)].prefix { line in
            let code = line.trimmingCharacters(in: .whitespaces)
            return Self.indent(of: line) > indent && (code.hasPrefix(".") || code.hasPrefix("//"))
        }
    }

    /// The symbols an image on this line may draw: its name, or each name a condition chooses between.
    private static func symbols(in line: String) -> [String] {
        guard let start = line.range(of: "Image(systemName: ") else { return [] }
        let argument = line[start.upperBound...].prefix { $0 != ")" }
        return argument.matches(of: /"([^"]*)"/).map { String($0.1) }
    }

    private static func indent(of line: String) -> Int {
        line.prefix { $0 == " " }.count
    }
}
