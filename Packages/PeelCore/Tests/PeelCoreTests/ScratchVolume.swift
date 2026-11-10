import Foundation

/// A small disk of its own for a test, formatted with a file system the startup disk does not use, made with `hdiutil`
/// and mounted at a folder the test chooses, out of Finder's sight. It is detached when the test lets go of it.
final class ScratchVolume {
    private(set) var url: URL
    private let image: TemporaryDirectory

    /// `fileSystem` is a name `hdiutil create -fs` takes, such as `ExFAT` or `MS-DOS FAT32`.
    init(fileSystem: String, mountedAt url: URL) throws {
        image = try TemporaryDirectory()
        self.url = url
        let file = image.url.appending(path: "disk.dmg")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try DiskImageTool.hdiutil("create", "-size", "64m", "-fs", fileSystem, "-volname", "Scratch", "-type", "UDIF", file.path)
        try DiskImageTool.hdiutil("attach", "-nobrowse", "-noautoopen", "-noverify", "-mountpoint", url.path, file.path)
    }

    deinit {
        _ = try? DiskImageTool.hdiutil("detach", "-force", url.path)
    }

    /// The same disk, detached and mounted again at `place`, as a disk renamed or plugged in again lands elsewhere. It
    /// is unmounted without force, since a forced unmount skips writing out what the file system still holds.
    func remount(at place: URL) throws {
        try DiskImageTool.hdiutil("detach", url.path)
        try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
        let file = image.url.appending(path: "disk.dmg")
        try DiskImageTool.hdiutil("attach", "-nobrowse", "-noautoopen", "-noverify", "-mountpoint", place.path, file.path)
        url = place
    }
}
