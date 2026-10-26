import Foundation
import Testing

struct SystemSettingsStepTests {
    /// On macOS 27, Login Items & Extensions shows Network Extensions only under By Category, so every step that
    /// leads there says to choose it.
    @Test func everyWayToNetworkExtensionsChoosesByCategory() throws {
        let root = LineLengthTests.repository.path(percentEncoded: false)
        var found: [String] = []
        for file in try LineLengthTests.swiftFiles() {
            let path = String(file.path(percentEncoded: false).dropFirst(root.count))
            guard !path.contains("Tests/") else { continue }
            let lines = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated()
            where line.contains("\"") && line.contains("Network Extensions") && !line.contains("By Category") {
                found.append("\(path):\(index + 1)")
            }
        }
        #expect(found.isEmpty, "\(found)")
    }
}
