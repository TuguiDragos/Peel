import Foundation
@testable import PeelCore
import PeelPrivileged
import Testing

/// Space's band shows the disk the home folder is on, and the startup disk too when the home is kept elsewhere: the
/// areas outside the home and macOS's own snapshots are there.
struct SpaceDisksTests {
    @Test func aHomeOnAnotherDiskShowsTheStartupDiskFirstAndThenItsOwn() async throws {
        let directory = try TemporaryDirectory()
        let disk = try ScratchVolume(fileSystem: "APFS", mountedAt: directory.url.appending(path: "Disk"))
        let away = disk.url.appending(path: "home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: away, withIntermediateDirectories: true)
        let top = try #require(PrivilegedPathPolicy.resolvedPath(disk.url.path(percentEncoded: false)))

        let both = await DiskSpace.readEach(home: away)
        let one = await DiskSpace.readEach(home: try directory.directory("home"))

        #expect(both.map(\.snapshotVolume) == [LocalSnapshots.volume, top])
        #expect(both.last?.name == "Scratch")
        #expect(one.map(\.snapshotVolume) == [LocalSnapshots.volume])
        withExtendedLifetime(disk) {}
    }

    @Test func spaceListsTheSnapshotsOfEachDiskItShows() async throws {
        let directory = try TemporaryDirectory()
        let disk = try ScratchVolume(fileSystem: "APFS", mountedAt: directory.url.appending(path: "Disk"))
        let home = disk.url.appending(path: "home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let top = try #require(PrivilegedPathPolicy.resolvedPath(disk.url.path(percentEncoded: false)))

        let report = await SpaceInventory.scan(
            home: home, root: try directory.directory("root"), minimumSize: 1, measure: LeftoverScanner.walk,
            simctlRuntimeHelp: { nil }
        )

        #expect(report.snapshots.map(\.volume) == [LocalSnapshots.volume, top])
        #expect(report.snapshots.last?.snapshots == [], "an APFS disk with none")
        withExtendedLifetime(disk) {}
    }

    @Test func aDiskThatIsNotAPFSKeepsNoSnapshots() async throws {
        let directory = try TemporaryDirectory()
        let disk = try ScratchVolume(fileSystem: "ExFAT", mountedAt: directory.url.appending(path: "Disk"))

        #expect(await LocalSnapshots.list(volume: disk.url.path(percentEncoded: false)) == [])
    }

    @Test func theCommandThatDeletesSnapshotsNamesTheirDiskAsTheShellReadsIt() {
        #expect(LocalSnapshots.deleteCommand(for: "/Volumes/My SSD") == "tmutil deletelocalsnapshots '/Volumes/My SSD'")
    }
}
