import Foundation
import Testing

struct AlertDefaultButtonTests {
    @Test func anAlertWithOtherButtonsKeepsReturnOnOK() throws {
        let root = LineLengthTests.repository.path(percentEncoded: false)
        var found: [String] = []
        for file in try LineLengthTests.swiftFiles()
        where file.path(percentEncoded: false).dropFirst(root.count).hasPrefix("Peel/") {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where line.contains(#"Button("OK", role: .cancel)"#) {
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
}
