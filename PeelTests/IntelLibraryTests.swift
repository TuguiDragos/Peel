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
        let library = IntelLibrary { _, _ in
            reads.count += 1
            reads.wereShownAsAScan.append(reads.library?.isScanning == true)
            return IntelScan(findings: [], unreadable: reads.count > 1 ? [unread] : [])
        }
        reads.library = library

        await library.readAgain(installedApps: [])
        #expect(reads.count == 0, "nothing is read again before the page was read once")

        await library.refresh(installedApps: [])
        await library.readAgain(installedApps: [])

        #expect(library.scan?.unreadable == [unread])
        #expect(reads.wereShownAsAScan == [true, false], "a read again is announced to nobody")
    }
}
