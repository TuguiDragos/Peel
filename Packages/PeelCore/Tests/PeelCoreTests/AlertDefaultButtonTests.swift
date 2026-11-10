import Foundation
import Testing

struct AlertDefaultButtonTests {
    @Test func anAlertWithOtherButtonsKeepsReturnOnOK() throws {
        let root = LineLengthTests.repository.path(percentEncoded: false)
        var found: [String] = []
        for file in try LineLengthTests.swiftFiles()
        where file.path(percentEncoded: false).dropFirst(root.count).hasPrefix("Peel/") {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where line.contains(#"Button("OK") {}"#) {
                guard let start = lines[..<index].lastIndex(where: { $0.contains(".alert(") }) else { continue }
                let hasOtherButtons = lines[(start + 1)..<index].contains { $0.contains("Button(") }
                let next = index + 1 < lines.count ? lines[index + 1] : ""
                if hasOtherButtons, !next.contains(".keyboardShortcut(.defaultAction)") {
                    found.append("\(file.path(percentEncoded: false).dropFirst(root.count)):\(index + 1)")
                }
            }
        }
        #expect(found.isEmpty, "Return would press the first other button, not OK: \(found)")
    }

    /// A button takes Return or Escape, never both, so an OK that is the cancel button closes nothing with Return.
    @Test func noOKIsTheCancelButton() throws {
        let root = LineLengthTests.repository.path(percentEncoded: false)
        var found: [String] = []
        for file in try LineLengthTests.swiftFiles()
        where file.path(percentEncoded: false).dropFirst(root.count).hasPrefix("Peel/") {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where line.contains(#"Button("OK", role: .cancel)"#) {
                found.append("\(file.path(percentEncoded: false).dropFirst(root.count)):\(index + 1)")
            }
        }
        #expect(found.isEmpty, "Return can't close these alerts: \(found)")
    }

    @Test func removingPeelOrItsHelperLeavesEscapeToCancel() throws {
        let settings = LineLengthTests.repository.appending(path: "Peel/Views/Settings/SettingsView.swift")
        let lines = try String(contentsOf: settings, encoding: .utf8).components(separatedBy: "\n")
        for title in ["Remove Peel from this Mac?", "Uninstall Peel’s helper?"] {
            let start = try #require(lines.firstIndex { $0.contains(title) })
            let cancel = try #require(lines[start...].firstIndex { $0.contains(#"Button("Cancel", role: .cancel)"#) })
            #expect(!lines[cancel + 1].contains(".keyboardShortcut(.defaultAction)"), "\(title)")
        }
    }
}
