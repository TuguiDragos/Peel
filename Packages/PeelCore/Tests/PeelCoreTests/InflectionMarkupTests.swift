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

    @Test func digitsRollOnlyThroughTheRuleThatAsksReduceMotion() throws {
        let call = ".numeric" + "Text("
        let root = LineLengthTests.repository.path(percentEncoded: false)
        var found: [String] = []
        let rule = ["Motion.swift", "MotionTests.swift"]
        for file in try LineLengthTests.swiftFiles() where !rule.contains(file.lastPathComponent) {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains(call) { found.append(String(file.path(percentEncoded: false).dropFirst(root.count))) }
        }
        #expect(found.isEmpty, "SwiftUI rolls digits under Reduce Motion too; use numberTransition(value:)")
    }

    @Test func aPathThePersonSeesOrCopiesEndsWithoutASlash() throws {
        let raw = ".path(percentEncoded: false)"
        let shown = ["Text(verbatim:", "setString(", "explanation)\""]
        let root = LineLengthTests.repository.path(percentEncoded: false)
        var found: [String] = []
        for file in try LineLengthTests.swiftFiles() where file.path(percentEncoded: false).contains("/Peel/Views/") {
            let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
            for (index, line) in lines.enumerated() where line.contains(raw) && shown.contains(where: line.contains) {
                found.append("\(file.path(percentEncoded: false).dropFirst(root.count)):\(index + 1)")
            }
        }
        #expect(found.isEmpty, "A folder's URL keeps its slash in path(percentEncoded:); use fullPath: \(found)")
    }

    @Test func aCommandForThePersonNeverNamesBrewByHand() throws {
        let command = try Regex("[`\"](sudo )?brew (upgrade|uninstall|reinstall|install|update|unpin|info|services stop)")
        let root = LineLengthTests.repository.path(percentEncoded: false)
        var found: [String] = []
        for file in try LineLengthTests.swiftFiles() where !file.path(percentEncoded: false).contains("Tests/") {
            let lines = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                if line.contains(command) {
                    found.append("\(file.path(percentEncoded: false).dropFirst(root.count)):\(index + 1)")
                }
            }
        }
        #expect(found.isEmpty, "Terminal may find another Homebrew under `brew`; use Homebrew.wordForTerminal: \(found)")
    }
}
