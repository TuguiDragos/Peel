import Foundation
import Testing

struct DecorativeSymbolTests {
    /// macOS describes these by an action ("move", "copy", "build", "forward", "new folder") or by their own name, so
    /// VoiceOver says that word for an image of one that Peel doesn't label.
    static let misleading: Set = [
        "folder", "folder.fill", "questionmark.app", "doc.on.doc", "hammer", "chevron.right", "folder.badge.plus",
    ]
    static let ancestorCovers = [".hidden()", ".accessibilityElement(children: .ignore)", ".accessibilityLabel("]

    @Test func aSymbolMacOSNamesByAnActionIsNeverLeftForVoiceOver() throws {
        let root = LineLengthTests.repository.path(percentEncoded: false)
        var found: [String] = []
        for file in try LineLengthTests.swiftFiles()
        where file.path(percentEncoded: false).dropFirst(root.count).hasPrefix("Peel/") {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                guard let name = Self.symbol(in: line), Self.misleading.contains(name) else { continue }
                let indent = Self.indent(of: line)
                let before = lines[max(0, index - 3)...index].joined(separator: "\n")
                if before.contains("icon:") || before.contains("label:") || before.contains("Label {") { continue }
                let following = lines[(index + 1)..<min(lines.count, index + 30)]
                let own = following.prefix { line in
                    let code = line.trimmingCharacters(in: .whitespaces)
                    return Self.indent(of: line) > indent && (code.hasPrefix(".") || code.hasPrefix("//"))
                }
                if own.contains(where: { $0.contains(".accessibilityHidden(true)") || $0.contains(".accessibilityLabel(") }) {
                    continue
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

    @Test func aNoticesOwnSymbolIsDecoration() throws {
        let text = try String(
            contentsOf: LineLengthTests.repository.appending(path: "Peel/Views/Notice.swift"), encoding: .utf8
        )
        #expect(text.contains(".accessibilityHidden(systemImage != nil)"))
    }

    private static func symbol(in line: String) -> String? {
        guard let start = line.range(of: #"Image(systemName: ""#) else { return nil }
        return line[start.upperBound...].split(separator: "\"", maxSplits: 1).first.map(String.init)
    }

    private static func indent(of line: String) -> Int {
        line.prefix { $0 == " " }.count
    }
}
