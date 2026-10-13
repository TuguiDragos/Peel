import Foundation
import Testing

struct InflectionMarkupTests {
    @Test func noPlainLocalizedStringCarriesInflection() throws {
        let call = "String(localized:"
        let markup = "](inflect: true)"
        let root = LineLengthTests.repository.path(percentEncoded: false)
        var found: [String] = []
        for file in try LineLengthTests.swiftFiles() {
            let lines = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                let plain = line.replacingOccurrences(of: "Attributed" + call, with: "")
                if plain.contains(call), plain.contains(markup) {
                    found.append("\(file.path(percentEncoded: false).dropFirst(root.count)):\(index + 1)")
                }
            }
        }
        #expect(found.isEmpty, "String(localized:) shows inflection markup as written; use String(inflecting:): \(found)")
    }
}
