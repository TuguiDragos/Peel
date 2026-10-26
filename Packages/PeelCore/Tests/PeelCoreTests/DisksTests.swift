import Foundation
@testable import PeelCore
import Testing

struct DisksTests {
    @Test func tellsADiskImageFromTheDiskMacOSStartedFrom() throws {
        let directory = try TemporaryDirectory()
        let volume = try ScratchVolume(fileSystem: "APFS", mountedAt: directory.url.appending(path: "Image"))

        let image = try #require(Disks.volume(mountedAt: volume.url.path(percentEncoded: false)))
        let startup = try #require(Disks.volume(mountedAt: "/"))
        #expect(Disks.isADiskImage(image))
        #expect(!Disks.isADiskImage(startup))
    }

    @Test func aFolderWhereNoVolumeIsMountedIsNoDisk() throws {
        let directory = try TemporaryDirectory()

        #expect(Disks.volume(mountedAt: directory.url.path(percentEncoded: false)) == nil)
        #expect(!Disks.isOnAnotherDisk(URL(filePath: "/Volumes/org.example.NotConnected/Apps/Extern.app")))
        #expect(!Disks.isOnAnotherDisk(URL(filePath: "/Applications/Extern.app")))
    }
}
