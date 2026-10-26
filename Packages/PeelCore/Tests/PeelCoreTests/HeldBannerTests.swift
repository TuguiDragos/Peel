import Foundation
import Testing

struct HeldBannerTests {
    @Test func everyPageThatForgetsCasksSaysWhyNothingMoves() throws {
        let views = LineLengthTests.repository.appending(path: "Peel/Views", directoryHint: .isDirectory)
        let files = FileManager.default.enumerator(at: views, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        var missing: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            if source.contains(".forgetCasksDialog("), !source.contains("RemovalsHeldBanner(") {
                missing.append(file.lastPathComponent)
            }
        }
        #expect(!files.isEmpty)
        #expect(missing.isEmpty, "no RemovalsHeldBanner in \(missing.sorted())")
    }
}
