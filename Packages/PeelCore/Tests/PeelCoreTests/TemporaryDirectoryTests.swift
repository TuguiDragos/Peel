import Foundation
import Testing

struct TemporaryDirectoryTests {
    @Test func onlyTemporaryDirectoryNamesTheTemporaryFolder() throws {
        let this = URL(filePath: #filePath)
        let folder = this.deletingLastPathComponent()
        let walk = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
        var found: [String] = []
        for case let file as URL in walk where file.pathExtension == "swift"
            && ![this.lastPathComponent, "TemporaryDirectory.swift"].contains(file.lastPathComponent) {
            let lines = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated()
            where ["temporaryDirectory", "NSTemporaryDirectory", "mkdtemp"].contains(where: { line.contains($0) }) {
                found.append("\(file.lastPathComponent):\(index + 1)")
            }
        }
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }
}
