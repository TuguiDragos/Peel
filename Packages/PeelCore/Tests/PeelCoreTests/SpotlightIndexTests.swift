import Foundation
@testable import PeelCore
import Testing

struct SpotlightIndexTests {
    @Test func readsWhatMdutilPrints() {
        #expect(SpotlightIndex.state(mdutil: "/:\n\tIndexing enabled. \n") == .indexing)
        #expect(SpotlightIndex.state(mdutil: "/System/Volumes/Data:\n\tIndex is read-only.\n") == .readOnly)
        #expect(SpotlightIndex.state(mdutil: "/Volumes/Backup:\n\tIndexing disabled.\n") == .notIndexing)
        #expect(SpotlightIndex.state(mdutil: "/Volumes/Backup:\n\tIndexing and searching disabled.\n") == .notIndexing)
        let neverIndexed = "/Volumes/Backup:\n\tIndexing and searching disabled because of \".metadata_never_index\" "
            + "file at root of volume.\n"
        #expect(SpotlightIndex.state(mdutil: neverIndexed) == .notIndexing)
        #expect(SpotlightIndex.state(mdutil: "/Users/someone:\n\tError: unknown indexing state.\n") == nil)
        #expect(SpotlightIndex.state(mdutil: "Error: invalid path `/nowhere'.\n") == nil)
    }

    @Test func asksMdutilAboutAVolumeAndNothingElse() async throws {
        let directory = try TemporaryDirectory()

        #expect(await SpotlightIndex.state(URL(filePath: "/System/Volumes/Data")) != nil)
        #expect(await SpotlightIndex.state(directory.url) == nil)
    }

    @Test func aDiskImageMountedReadOnlyIsNotSearched() throws {
        let directory = try TemporaryDirectory()
        let place = directory.url.appending(path: "Installer", directoryHint: .isDirectory)
        let disk = try ScratchVolume(fileSystem: "HFS+", mountedAt: place)
        #expect(SpotlightIndex.isSearched(place))

        try disk.remount(at: place, readOnly: true)

        #expect(!SpotlightIndex.isSearched(place))
        #expect(SpotlightIndex.isSearched(URL(filePath: "/System/Volumes/Data", directoryHint: .isDirectory)))
        withExtendedLifetime(disk) {}
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
