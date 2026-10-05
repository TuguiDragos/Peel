import Foundation
import Testing

struct LineLengthTests {
    static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    static let folders = ["Peel", "PeelCLI", "PeelFinder", "PeelHelper", "PeelUITests", "Scripts", "Packages/PeelCore"]

    /// What counts is a line without its string literals, so a sentence is never split and can be searched for.
    @Test func everyLineFitsIn120Columns() throws {
        var long: [String] = []
        for file in try Self.swiftFiles() {
            let widths = Self.codeWidths(of: try String(contentsOf: file, encoding: .utf8))
            let name = file.path(percentEncoded: false).dropFirst(Self.repository.path(percentEncoded: false).count)
            for (index, width) in widths.enumerated() where width > 120 {
                long.append("\(name):\(index + 1) is \(width) columns")
            }
        }
        #expect(long.isEmpty, "\(long.count) lines:\n\(long.prefix(40).joined(separator: "\n"))")
    }

    @Test func aStringLiteralDoesNotCount() {
        let literal = String(repeating: "word ", count: 40)
        let interpolated = "        let text = \"\(literal)\\(value(\"\(literal)\"))\(literal)\""
        let raw = "        let raw = #\"\(literal)\"quoted\"\(literal)\"#"
        let multiline = "        let lines = \"\"\"\n\(literal)\n        \"\"\""
        let strings = [interpolated, raw, multiline].joined(separator: "\n")
        #expect(Self.codeWidths(of: strings) == [19, 18, 20, 0, 0])
        let comment = "        // A quote \" in a comment opens no string, \(literal)"
        let code = "        let total = " + Array(repeating: "first + second", count: 10).joined(separator: " + ")
        #expect(Self.codeWidths(of: [comment, code].joined(separator: "\n")).allSatisfy { $0 > 120 })
    }

    static func swiftFiles() throws -> [URL] {
        var files: [URL] = []
        for folder in folders {
            let root = repository.appending(path: folder, directoryHint: .isDirectory)
            let walk = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            for case let url as URL in walk {
                if ["build", ".build"].contains(url.lastPathComponent) {
                    walk.skipDescendants()
                } else if url.pathExtension == "swift" {
                    files.append(url)
                }
            }
        }
        return files
    }

    /// The width of each line once its string literals are taken out, interpolations and raw strings included.
    static func codeWidths(of text: String) -> [Int] {
        let scalars = Array(text.unicodeScalars)
        var isLiteral = [Bool](repeating: false, count: scalars.count)
        var index = 0

        func starts(_ prefix: String, at position: Int) -> Bool {
            let prefix = Array(prefix.unicodeScalars)
            return position + prefix.count <= scalars.count
                && Array(scalars[position..<position + prefix.count]) == prefix
        }

        func hashes(at position: Int) -> Int {
            var count = 0
            while position + count < scalars.count, scalars[position + count] == "#" { count += 1 }
            return count
        }

        // Reads code up to the end, or up to the parenthesis that closes an interpolation.
        func code(inInterpolation: Bool) {
            var depth = 0
            while index < scalars.count {
                if starts("//", at: index) {
                    while index < scalars.count, scalars[index] != "\n" { index += 1 }
                } else if starts("/*", at: index) {
                    var nesting = 0
                    repeat {
                        if starts("/*", at: index) { nesting += 1; index += 2 }
                        else if starts("*/", at: index) { nesting -= 1; index += 2 }
                        else { index += 1 }
                    } while nesting > 0 && index < scalars.count
                } else if scalars[index] == "\"" || (scalars[index] == "#" && starts("\"", at: index + hashes(at: index))) {
                    string()
                } else if scalars[index] == "(" {
                    depth += 1
                    index += 1
                } else if scalars[index] == ")" {
                    if inInterpolation, depth == 0 { return }
                    depth -= 1
                    index += 1
                } else {
                    index += 1
                }
            }
        }

        func string() {
            let start = index
            let pounds = hashes(at: index)
            index += pounds
            let isMultiline = starts("\"\"\"", at: index)
            let quote = isMultiline ? "\"\"\"" : "\""
            let end = quote + String(repeating: "#", count: pounds)
            index += quote.count
            while index < scalars.count {
                if scalars[index] == "\\", hashes(at: index + 1) >= pounds {
                    index += 1 + pounds
                    if index < scalars.count, scalars[index] == "(" {
                        index += 1
                        code(inInterpolation: true)
                    }
                    index += 1
                } else if starts(end, at: index) {
                    index += end.unicodeScalars.count
                    break
                } else if !isMultiline, scalars[index] == "\n" {
                    break
                } else {
                    index += 1
                }
            }
            for position in start..<min(index, scalars.count) { isLiteral[position] = true }
        }

        code(inInterpolation: false)
        var widths: [Int] = []
        var line = String.UnicodeScalarView()
        for (position, scalar) in scalars.enumerated() {
            if scalar == "\n" {
                widths.append(String(line).count)
                line = String.UnicodeScalarView()
            } else if !isLiteral[position] {
                line.append(scalar)
            }
        }
        widths.append(String(line).count)
        return widths
    }
}
