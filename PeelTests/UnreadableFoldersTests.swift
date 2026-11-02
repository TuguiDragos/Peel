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

    @Test func namesTheFoldersAndAddsTheAdviceOnlyWhenFullDiskAccessWouldHelp() {
        let paths = ["/Users/me/Documents/app", "/Users/me/work/pgdata"]
        let advice = UnreadableFoldersNotice.detail(naming: [], closed: 0, needsFullDiskAccess: true)

        let both = UnreadableFoldersNotice.detail(naming: paths, closed: 0, needsFullDiskAccess: true)
        let named = UnreadableFoldersNotice.detail(naming: paths, closed: 0, needsFullDiskAccess: false)

        #expect(!advice.isEmpty)
        #expect(both.contains("pgdata") && both.hasSuffix(advice))
        #expect(named.contains("pgdata") && !named.contains(advice))
    }

    @Test func saysThePermissionsKeptPeelOutOnlyWhenTheyDid() throws {
        let all = try #require(UnreadableFoldersNotice.whyNotRead(closed: 2, of: 2))
        let some = try #require(UnreadableFoldersNotice.whyNotRead(closed: 1, of: 2))
        let one = try #require(UnreadableFoldersNotice.whyNotRead(closed: 1, of: 1))

        #expect(UnreadableFoldersNotice.whyNotRead(closed: 0, of: 2) == nil)
        #expect(Set([all, some, one]).count == 3)
        #expect(UnreadableFoldersNotice.detail(naming: ["/a", "/b"], closed: 1, needsFullDiskAccess: false).hasSuffix(some))
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
