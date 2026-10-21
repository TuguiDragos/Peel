import Foundation
@testable import Peel
import Testing

struct TrashWatchTests {
    @Test func tellsOfAnAppThrownAwayAfterItStartedWatching() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let trash = folder.appending(path: "Trash", directoryHint: .isDirectory)
        let staged = folder.appending(path: "Staged/Example.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: trash.appending(path: "Earlier.app"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var arrived: [URL] = []
        let watch = TrashWatch(trash: trash, waitsIn: folder) { arrived.append($0) }
        defer { watch.stop() }
        guard case .watching = watch.start() else {
            Issue.record("the watch did not start")
            return
        }

        try FileManager.default.moveItem(at: staged, to: trash.appending(path: "Example.app"))
        for _ in 0..<200 where arrived.isEmpty {
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(arrived.map(\.lastPathComponent) == ["Example.app"])
    }

    @Test func waitsForATrashThatIsNotThereYet() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let watch = TrashWatch(trash: folder.appending(path: "Trash"), waitsIn: folder) { _ in }
        defer { watch.stop() }

        guard case .watching = watch.start() else {
            Issue.record("a missing Trash was not waited for")
            return
        }
        #expect(watch.isActive)
    }
}
