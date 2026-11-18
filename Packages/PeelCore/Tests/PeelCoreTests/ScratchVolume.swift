import Darwin
import Foundation
import Synchronization

/// A small disk of its own for a test, formatted with a file system the startup disk does not use, made with `hdiutil`
/// and mounted at a folder the test chooses, out of Finder's sight. It is detached when the test lets go of it.
final class ScratchVolume {
    private(set) var url: URL
    private let image: TemporaryDirectory

    /// FAT and exFAT take their serial from the clock, so disks made in the same second would share it, and with it
    /// the volume's UUID.
    private static let serials = Atomic<UInt32>(.random(in: .min ... .max))

    /// `fileSystem` is a name `hdiutil create -fs` takes, such as `ExFAT` or `MS-DOS FAT32`. Two exFAT disks given one
    /// `serial` answer one volume UUID, as a disk and its clone do. A disk ignores its owners, as macOS mounts an
    /// external disk, unless `owners` says otherwise.
    init(
        fileSystem: String, mountedAt url: URL, serial: UInt32? = nil, owners: Bool = false, size: String = "64m"
    ) throws {
        image = try TemporaryDirectory()
        self.url = url
        let file = image.url.appending(path: "disk.dmg")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try DiskImageTool.hdiutil(
            ["create", "-size", size, "-fs", fileSystem] + Self.serial(for: fileSystem, given: serial)
                + ["-volname", "Scratch", "-type", "UDIF", file.path]
        )
        try DiskImageTool.hdiutil(
            ["attach", "-nobrowse", "-noautoopen", "-noverify"] + (owners ? ["-owners", "on"] : [])
                + ["-mountpoint", url.path, file.path]
        )
    }

    private static func serial(for fileSystem: String, given: UInt32?) -> [String] {
        guard fileSystem.hasPrefix("MS-DOS") || fileSystem == "ExFAT" else { return [] }
        var serial = given ?? 0
        while serial == 0 {
            serial = serials.wrappingAdd(1, ordering: .relaxed).newValue
        }
        return ["-fsargs", "-I \(serial)"]
    }

    deinit {
        _ = try? DiskImageTool.hdiutil("detach", "-force", url.path)
    }

    /// The same disk, detached and mounted again at `place`, as a disk renamed or plugged in again lands elsewhere, or,
    /// `readOnly`, as the disk image an app came on is mounted. It is unmounted without force, since a forced unmount
    /// skips writing out what the file system still holds.
    func remount(at place: URL, readOnly: Bool = false) throws {
        do {
            try DiskImageTool.hdiutil("detach", url.path)
        } catch let failure as DiskImageTool.Failure {
            throw DiskImageTool.Failure(
                command: failure.command, status: failure.status, said: failure.said + "\nIn use: " + holders()
            )
        }
        try attach(at: place, readOnly: readOnly)
    }

    /// What keeps the disk from being detached without force: what this process holds open on it, read at once, then
    /// what `lsof` names, which sees no process of another account.
    private func holders() -> String {
        let here = Self.openInThisProcess(under: [url.path, "/private" + url.path])
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: "/usr/sbin/lsof")
        process.arguments = ["-w", "+f", "--", url.path]
        process.standardOutput = output
        try? process.run()
        let said = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return "this process: \(here)\nlsof: \(String(decoding: said, as: UTF8.self))"
    }

    private static func openInThisProcess(under places: [String]) -> [String] {
        let pid = getpid()
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / MemoryLayout<proc_fdinfo>.size)
        let filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, size)
        guard filled > 0 else { return [] }
        return descriptors.prefix(Int(filled) / MemoryLayout<proc_fdinfo>.size).compactMap { descriptor in
            guard descriptor.proc_fdtype == PROX_FDTYPE_VNODE else { return nil }
            var info = vnode_fdinfowithpath()
            let expected = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, expected) == expected else {
                return nil
            }
            let path = withUnsafeBytes(of: info.pvip.vip_path) {
                String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
            }
            guard places.contains(where: { path.hasPrefix($0) }) else { return nil }
            return info.pfi.fi_openflags & UInt32(O_EVTONLY) != 0 ? "\(path) (watched)" : path
        }
    }

    /// The disk plugged in again at `place`, once something took it away.
    func attach(at place: URL, readOnly: Bool = false) throws {
        try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
        let file = image.url.appending(path: "disk.dmg")
        try DiskImageTool.hdiutil(
            ["attach", "-nobrowse", "-noautoopen", "-noverify"] + (readOnly ? ["-readonly"] : [])
                + ["-mountpoint", place.path, file.path]
        )
        url = place
    }
}
