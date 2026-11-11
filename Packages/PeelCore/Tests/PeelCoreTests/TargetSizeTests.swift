import Foundation
import Testing

struct TargetSizeTests {
    /// A link that stands on its own is a control, at least 20 by 20 points, which WCAG 2.5.8 leaves aside only
    /// for a link inside a sentence.
    @Test func everyLinkOfItsOwnTakesTheSmallestTarget() throws {
        let root = LineLengthTests.repository.path(percentEncoded: false)
        var small: [String] = []
        for file in try LineLengthTests.swiftFiles()
        where file.path(percentEncoded: false).dropFirst(root.count).hasPrefix("Peel/") {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where line.contains("Link(destination:") {
                let label = lines[index..<min(lines.count, index + 4)]
                if !label.contains(where: { $0.contains(".minimumTarget()") || $0.contains(".creditTarget()") }) {
                    small.append("\(file.path(percentEncoded: false).dropFirst(root.count)):\(index + 1)")
                }
            }
        }
        #expect(small.isEmpty, "These links are as small as their words: \(small)")
    }
}
