import Foundation
import Testing

struct LinkedTextTests {
    @Test func noTextHoldsALinkOnlyAPointerCanFollow() throws {
        let root = LineLengthTests.repository.path(percentEncoded: false)
        let patterns = try [
            #"(?<![A-Za-z0-9_])Text\(\s*(?:LocalizedStringResource\(\s*)?"(?:[^"\\\n]|\\.)*\]\((?!inflect: true\))"#,
            #"(?<![A-Za-z0-9_])Text\(\s*\(?\s*(?:try\??\s*)?AttributedString\(markdown:"#,
        ].map { try NSRegularExpression(pattern: $0) }
        var found: [String] = []
        for file in try LineLengthTests.swiftFiles()
        where file.path(percentEncoded: false).dropFirst(root.count).hasPrefix("Peel/") {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            let code = lines.map { $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") ? "" : $0 }
                .joined(separator: "\n")
            let whole = NSRange(code.startIndex..., in: code)
            for pattern in patterns {
                for match in pattern.matches(in: code, range: whole) {
                    let start = try #require(Range(match.range, in: code)).lowerBound
                    let line = code[..<start].count { $0 == "\n" } + 1
                    found.append("\(file.path(percentEncoded: false).dropFirst(root.count)):\(line)")
                }
            }
        }
        #expect(
            found.isEmpty,
            "A link inside a Text takes no press from VoiceOver or the keyboard; show the sentence with LinkedText: \(found)"
        )
    }
}
