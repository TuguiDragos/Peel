import Foundation
import Testing

/// A hosted test runs Peel's own code, which keeps its memory of apps in the Peel folder of this Mac unless it is given
/// one, so every library a test makes takes a memory of its own.
struct AppMemoryInTestsTests {
    @Test func everyAppLibraryATestMakesKeepsItsMemoryOutOfThePeelFolder() throws {
        let this = URL(filePath: #filePath)
        let folder = this.deletingLastPathComponent()
        let walk = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
        var found: [String] = []
        for case let file as URL in walk where file.pathExtension == "swift" && file != this {
            let text = try String(contentsOf: file, encoding: .utf8)
            for call in Self.calls(of: "AppLibrary(", in: text) where !call.text.contains("appMemory:") {
                found.append("\(file.lastPathComponent):\(call.line)")
            }
            for call in Self.calls(of: "AppMemory(", in: text) where !call.text.contains("url:") {
                found.append("\(file.lastPathComponent):\(call.line)")
            }
        }
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }

    /// Each call of `name` in `text`, its arguments up to the parenthesis that closes them, and its line.
    private static func calls(of name: String, in text: String) -> [(text: Substring, line: Int)] {
        var calls: [(text: Substring, line: Int)] = []
        var searchFrom = text.startIndex
        while let start = text.range(of: name, range: searchFrom..<text.endIndex) {
            var depth = 1
            var end = start.upperBound
            while end < text.endIndex, depth > 0 {
                if text[end] == "(" { depth += 1 } else if text[end] == ")" { depth -= 1 }
                end = text.index(after: end)
            }
            calls.append((text[start.lowerBound..<end], text[..<start.lowerBound].count { $0 == "\n" } + 1))
            searchFrom = start.upperBound
        }
        return calls
    }
}
