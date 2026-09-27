import Foundation

/// A small disk of its own for a test, formatted with a file system the startup disk does not use, made with `hdiutil`
/// and mounted at a folder the test chooses, out of Finder's sight. It is detached when the test lets go of it.
final class ScratchVolume {
    let url: URL
    private let image: TemporaryDirectory

    /// `fileSystem` is a name `hdiutil create -fs` takes, such as `ExFAT` or `MS-DOS FAT32`.
    init(fileSystem: String, mountedAt url: URL) throws {
        image = try TemporaryDirectory()
        self.url = url
        let file = image.url.appending(path: "disk.dmg")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Self.hdiutil("create", "-quiet", "-size", "64m", "-fs", fileSystem, "-volname", "Scratch", "-type", "UDIF", file.path)
        try Self.hdiutil("attach", "-quiet", "-nobrowse", "-noautoopen", "-noverify", "-mountpoint", url.path, file.path)
    }

    deinit {
        try? Self.hdiutil("detach", "-quiet", "-force", url.path)
    }

    private static func hdiutil(_ arguments: String...) throws {
        let process = try Process.run(URL(filePath: "/usr/bin/hdiutil"), arguments: arguments)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: arguments.joined(separator: " ")]) }
    }
}
