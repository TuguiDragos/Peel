import Foundation
import Testing

struct ScanAnnouncementTests {
    @Test func everyViewAnnouncesItsScanOutsideWhatScanStateBuildsAgain() throws {
        let root = LineLengthTests.repository.path(percentEncoded: false)
        var found: [String] = []
        for file in try LineLengthTests.swiftFiles()
        where file.path(percentEncoded: false).dropFirst(root.count).hasPrefix("Peel/") {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard let announcement = text.range(of: ".announcesScan("), let state = text.range(of: ".scanState(") else {
                continue
            }
            if announcement.lowerBound < state.lowerBound {
                found.append(String(file.path(percentEncoded: false).dropFirst(root.count)))
            }
        }
        #expect(
            found.isEmpty,
            "ScanState builds its content again when the first scan ends, which loses an announcement inside it: \(found)"
        )
    }

    @Test func anAppsPageSaysWhyNothingMovesRatherThanNothingFound() throws {
        for name in ["Peel/Views/AppDetailView.swift", "Peel/Views/MultipleAppsView.swift"] {
            let text = try String(contentsOf: LineLengthTests.repository.appending(path: name), encoding: .utf8)
            let call = try #require(text.range(of: ".announcesScan(")).upperBound
            let arguments = text[call...].prefix { $0 != ")" }
            #expect(arguments.contains("couldNotLook:"), "\(name) lists the apps it can't move and says Nothing found.")
        }
    }
}
