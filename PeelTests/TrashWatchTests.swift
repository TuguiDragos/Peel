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
        var arrived: [TrashedApp] = []
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

        #expect(arrived.map(\.url.lastPathComponent) == ["Example.app"])
        #expect(arrived.map(\.cameInAFolder) == [false])
    }

    @Test func tellsOfAnAppThrownAwayInsideItsFolder() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let trash = folder.appending(path: "Trash", directoryHint: .isDirectory)
        let suite = folder.appending(path: "Staged/Example Suite", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: suite.appending(path: "Example Suite.app"), withIntermediateDirectories: true
        )
        let linked = folder.appending(path: "Installed/Linked Suite", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: linked.appending(path: "Linked Suite.app"), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        var arrived: [TrashedApp] = []
        let watch = TrashWatch(trash: trash, waitsIn: folder) { arrived.append($0) }
        defer { watch.stop() }
        guard case .watching = watch.start() else {
            Issue.record("the watch did not start")
            return
        }

        try FileManager.default.createSymbolicLink(
            at: trash.appending(path: "Linked Suite"), withDestinationURL: linked
        )
        try FileManager.default.moveItem(at: suite, to: trash.appending(path: "Example Suite"))
        for _ in 0..<200 where arrived.isEmpty {
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(arrived.map(\.url.lastPathComponent) == ["Example Suite.app"])
        #expect(arrived.map(\.cameInAFolder) == [true])
    }

    @Test func tellsOfAnAppThatComesWithATrashItWaitedFor() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let trash = folder.appending(path: ".Trashes/501", directoryHint: .isDirectory)
        let staged = folder.appending(path: "Staged/Example.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var arrived: [TrashedApp] = []
        let watch = TrashWatch(trash: trash, waitsIn: folder) { arrived.append($0) }
        defer { watch.stop() }
        guard case .watching = watch.start() else {
            Issue.record("a missing Trash was not waited for")
            return
        }

        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: staged, to: trash.appending(path: "Example.app"))
        for _ in 0..<200 where arrived.isEmpty {
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(watch.isActive)
        #expect(arrived.map(\.url.lastPathComponent) == ["Example.app"])
    }

    @Test func goesOnWatchingATrashDeletedAndMadeAgain() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let trash = folder.appending(path: "Trash", directoryHint: .isDirectory)
        let staged = folder.appending(path: "Staged/Example.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var arrived: [TrashedApp] = []
        let watch = TrashWatch(trash: trash, waitsIn: folder) { arrived.append($0) }
        defer { watch.stop() }
        guard case .watching = watch.start() else {
            Issue.record("the watch did not start")
            return
        }

        try FileManager.default.removeItem(at: trash)
        for _ in 0..<200 where !watch.isWaitingForTheTrash {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(watch.isWaitingForTheTrash)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: staged, to: trash.appending(path: "Example.app"))
        for _ in 0..<200 where arrived.isEmpty {
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(arrived.map(\.url.lastPathComponent) == ["Example.app"])
    }

    @Test func findsATrashMadeInsideTrashesWhenAskedToLookAgain() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let trash = folder.appending(path: ".Trashes/501", directoryHint: .isDirectory)
        let staged = folder.appending(path: "Staged/Example.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: trash.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var arrived: [TrashedApp] = []
        let watch = TrashWatch(trash: trash, waitsIn: folder) { arrived.append($0) }
        defer { watch.stop() }
        guard case .watching = watch.start() else {
            Issue.record("a missing Trash was not waited for")
            return
        }

        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: staged, to: trash.appending(path: "Example.app"))
        // As `TrashMonitor` does when the list of apps changes: nothing in `.Trashes` can be watched.
        watch.lookForTheTrash()
        for _ in 0..<200 where arrived.isEmpty {
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(watch.isActive)
        #expect(arrived.map(\.url.lastPathComponent) == ["Example.app"])
    }

    @Test func aTrashClosedByPermissionsIsNoMatterOfFullDiskAccess() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let trash = folder.appending(path: "Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let path = trash.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
            try? FileManager.default.removeItem(at: folder)
        }
        let watch = TrashWatch(trash: trash, waitsIn: folder) { _ in }
        defer { watch.stop() }

        #expect(watch.start() == .closedByPermissions)
        #expect(TrashMonitor.Status(.closedByPermissions) == .closedByPermissions)
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
