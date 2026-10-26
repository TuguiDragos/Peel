import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct ExtensionLibraryTests {
    private final class Reads {
        var count = 0
        var library: ExtensionLibrary?
        var wereShownAsAScan: [Bool] = []
    }

    @Test func readsAgainWithoutShowingAScan() async {
        let reads = Reads()
        let library = ExtensionLibrary { _ in
            reads.count += 1
            reads.wereShownAsAScan.append(reads.library?.isScanning == true)
            return ExtensionScan(extensions: [], unanswered: reads.count > 1 ? [.systemExtension] : [])
        }
        reads.library = library

        await library.readAgain()
        #expect(reads.count == 0, "nothing is read again before the page was read once")

        await library.refresh()
        await library.readAgain()

        #expect(library.unanswered == [.systemExtension])
        #expect(reads.wereShownAsAScan == [true, false], "a read again is announced to nobody")
    }
}
