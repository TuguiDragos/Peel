import Darwin
import Foundation
@testable import PeelCore
import Testing

struct VolumeTrashesTests {
    /// An app thrown away from another disk lands in that disk's own Trash, so that is where the watch looks. An
    /// app on the home's disk lands in the home's Trash, which is watched already.
    @Test func watchesTheTrashOfEachOtherDiskAnAppIsOn() throws {
        let directory = try TemporaryDirectory()
        let disk = try ScratchVolume(fileSystem: "APFS", mountedAt: directory.url.appending(path: "Disk"))
        let app = disk.url.appending(path: "Applications/Example.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let calculator = URL(filePath: "/System/Applications/Calculator.app", directoryHint: .isDirectory)

        let folders = VolumeTrashes.folders(forAppsAt: [app, calculator, app], home: .homeDirectory)

        let trash = disk.url.appending(path: ".Trashes/\(getuid())", directoryHint: .isDirectory)
        #expect(folders.map(PathPattern.comparablePath) == [PathPattern.comparablePath(of: trash)])
    }
}
