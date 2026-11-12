import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct IntelLibraryTests {
    private final class Reads {
        var count = 0
        var library: IntelLibrary?
        var wereShownAsAScan: [Bool] = []
    }

    @Test func readsAgainWithoutShowingAScan() async {
        let reads = Reads()
        let unread = URL(filePath: "/org.example/Vendor")
        let library = IntelLibrary { _, _, _ in
            reads.count += 1
            reads.wereShownAsAScan.append(reads.library?.isScanning == true)
            return IntelScan(findings: [], unreadable: reads.count > 1 ? [unread] : [])
        }
        reads.library = library

        await library.readAgain(installedApps: [], knownSizes: [:])
        #expect(reads.count == 0, "nothing is read again before the page was read once")

        await library.refresh(installedApps: [], knownSizes: [:])
        await library.readAgain(installedApps: [], knownSizes: [:])

        #expect(library.scan?.unreadable == [unread])
        #expect(reads.wereShownAsAScan == [true, false], "a read again is announced to nobody")
    }

    @Test func anAppInsideAnotherHasItsIconBeforeItsRowShows() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let helper = folder.appending(path: "Owner.app/Contents/Helpers/Helper.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: helper.appending(path: "Contents"), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        let found = IntelFinding(url: helper, kind: .insideApp, name: "Helper", owner: "Owner")
        let library = IntelLibrary { _, _, _ in IntelScan(findings: [found]) }

        await library.refresh(installedApps: [], knownSizes: [:])

        #expect(library.findings == [found])
        #expect(IconCache.icon(for: helper) !== IconCache.anyApp, "its row shows any app's icon first")
    }
}
