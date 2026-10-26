import Foundation
@testable import PeelCore
import Testing

struct SpotlightIndexTests {
    @Test func readsWhatMdutilPrints() {
        #expect(SpotlightIndex.isIndexing(mdutil: "/:\n\tIndexing enabled. \n") == true)
        #expect(SpotlightIndex.isIndexing(mdutil: "/Volumes/Backup:\n\tIndexing disabled.\n") == false)
        #expect(SpotlightIndex.isIndexing(mdutil: "/Volumes/Backup:\n\tIndexing and searching disabled.\n") == false)
        let neverIndexed = "/Volumes/Backup:\n\tIndexing and searching disabled because of \".metadata_never_index\" "
            + "file at root of volume.\n"
        #expect(SpotlightIndex.isIndexing(mdutil: neverIndexed) == false)
        #expect(SpotlightIndex.isIndexing(mdutil: "/Users/someone:\n\tError: unknown indexing state.\n") == nil)
        #expect(SpotlightIndex.isIndexing(mdutil: "Error: invalid path `/nowhere'.\n") == nil)
    }

    @Test func asksMdutilAboutAVolumeAndNothingElse() async throws {
        let directory = try TemporaryDirectory()

        #expect(await SpotlightIndex.isIndexing(URL(filePath: "/System/Volumes/Data")) != nil)
        #expect(await SpotlightIndex.isIndexing(directory.url) == nil)
    }

    @Test func theStartupDiskIsAskedThroughTheVolumeThatHoldsThePersonsFiles() throws {
        let directory = try TemporaryDirectory()

        let home = SpotlightIndex.disks(in: .home, home: directory.url)
        let everywhere = SpotlightIndex.disks(in: .computer, home: directory.url)

        #expect(home.map(\.volume.path) == ["/System/Volumes/Data"])
        #expect(everywhere.first?.volume.path == "/System/Volumes/Data")
        #expect(Set(everywhere.map(\.volume)).count == everywhere.count)
    }
}
