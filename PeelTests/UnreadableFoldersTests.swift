import AppKit
@testable import Peel
import SwiftUI
import Testing

struct UnreadableFoldersTests {
    @Test func namesTheFirstFourFoldersAndCountsTheRest() {
        let paths = (1...60).map { "/Volumes/Old/f\($0)x" }

        let sentence = RemovalFailureAlert.listedFolders(paths)

        #expect(sentence.contains("f4x") && !sentence.contains("f5x") && !sentence.contains("f60x"))
        #expect(sentence.contains("56"))
        #expect(RemovalFailureAlert.listedFolders(["/a", "/b"]).contains("/b"))
    }

    @Test func saysWhyInOneSentenceAndLeavesTheFoldersToShowFolders() {
        let sentences = [
            UnreadableFoldersNotice.detail(count: 2, closed: 0, needsFullDiskAccess: true),
            UnreadableFoldersNotice.detail(count: 1, closed: 0, needsFullDiskAccess: true),
            UnreadableFoldersNotice.detail(count: 2, closed: 0, needsFullDiskAccess: false),
            UnreadableFoldersNotice.detail(count: 2, closed: 1, needsFullDiskAccess: false),
            UnreadableFoldersNotice.detail(count: 2, closed: 2, needsFullDiskAccess: false),
            UnreadableFoldersNotice.detail(count: 1, closed: 1, needsFullDiskAccess: false),
        ]

        #expect(Set(sentences).count == sentences.count)
        #expect(sentences.allSatisfy { !$0.contains("\n") && !$0.contains("/") && !$0.contains("Home") })
        #expect(sentences.allSatisfy { $0.hasSuffix("may not be listed.") })
    }

    @Test func saysThePermissionsKeptPeelOutOnlyWhenTheyDid() throws {
        let some = try #require(UnreadableFoldersNotice.reason(count: 2, closed: 1, needsFullDiskAccess: false))
        let all = try #require(UnreadableFoldersNotice.reason(count: 2, closed: 2, needsFullDiskAccess: false))
        let one = try #require(UnreadableFoldersNotice.reason(count: 1, closed: 1, needsFullDiskAccess: false))

        #expect(UnreadableFoldersNotice.reason(count: 2, closed: 0, needsFullDiskAccess: false) == nil)
        #expect(Set([all, some, one]).count == 3)
        #expect(UnreadableFoldersNotice.reason(count: 2, closed: 0, needsFullDiskAccess: true)?.contains("Full Disk Access") == true)
    }

    @Test func anAlertsFirstItemsAndHowManyMore() {
        let (shown, more) = RemovalFailureAlert.first(Array(1...60))

        #expect(shown == [1, 2, 3, 4] && more == 56)
        #expect(RemovalFailureAlert.first([1, 2]) == ([1, 2], 0))
    }
}

@Observable
private final class ShownFolders {
    var folders: [URL] = []
}

@MainActor
struct UnreadableFoldersReasonTests {
    private struct Detail: View {
        let shown: ShownFolders

        var body: some View {
            UnreadableFoldersDetail(folders: shown.folders)
                .frame(width: 300)
        }
    }

    private func settle(_ host: NSView, until isDone: () -> Bool) async {
        for _ in 0..<200 where !isDone() {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func aReasonIsGivenOnlyForTheFoldersItWasFoundFor() async throws {
        let parent = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let closed = parent.appending(path: "Folder A", directoryHint: .isDirectory)
        let open = parent.appending(path: "Folder B", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: closed, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: open, withIntermediateDirectories: true)
        chmod(closed.path(percentEncoded: false), 0)
        defer {
            chmod(closed.path(percentEncoded: false), 0o755)
            try? FileManager.default.removeItem(at: parent)
        }
        let shown = ShownFolders()
        shown.folders = [open]
        let host = NSHostingView(rootView: Detail(shown: shown))
        host.layoutSubtreeIfNeeded()
        let withoutAReason = host.fittingSize.height
        shown.folders = [closed]
        await settle(host) { host.fittingSize.height > withoutAReason }
        #expect(host.fittingSize.height > withoutAReason)

        shown.folders = [open]
        host.layoutSubtreeIfNeeded()

        #expect(host.fittingSize.height == withoutAReason)
    }
}

struct CleanUpWarningTests {
    @Test func namesTheFirstFourFormulaeItUninstalls() {
        let formulae = (1...30).map { "formula\($0)x" }

        let sentence = HomebrewList.uninstalls(formulae)

        #expect(sentence.contains("formula4x") && !sentence.contains("formula5x") && !sentence.contains("formula30x"))
        #expect(sentence.contains("26"))
    }
}
