@testable import Peel
import PeelCore
import Testing

struct SpaceLibraryTests {
    @Test func readsTheDiskAgainWithoutScanning() async {
        let space = SpaceLibrary()

        await space.readDisk()

        #expect(space.disk.map { $0.storage.total > 0 } == true)
        #expect(space.report == nil)
    }
}
