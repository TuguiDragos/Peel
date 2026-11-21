import Darwin
import Foundation
@testable import PeelCore
import Synchronization
import Testing

/// A small disk of its own for a test, formatted with a file system the startup disk does not use, made with `hdiutil`
/// and mounted at a folder the test chooses, out of Finder's sight. It is detached when the test lets go of it.
final class ScratchVolume {
    private(set) var url: URL
    private let image: TemporaryDirectory
    /// True from when the disk is mounted for its test until the test takes it away itself, or leaves it to the
    /// cleanup of leftovers.
    private var isMeantToBeMounted = false

    /// FAT and exFAT take their serial from the clock, so disks made in the same second would share it, and with it
    /// the volume's UUID.
    private static let serials = Atomic<UInt32>(.random(in: .min ... .max))

    /// `fileSystem` is a name `hdiutil create -fs` takes, such as `ExFAT` or `MS-DOS FAT32`. Two exFAT disks given one
    /// `serial` answer one volume UUID, as a disk and its clone do. A disk ignores its owners, as macOS mounts an
    /// external disk, unless `owners` says otherwise.
    init(
        fileSystem: String, mountedAt url: URL, serial: UInt32? = nil, owners: Bool = false, size: String = "64m"
    ) throws {
        _ = Self.detachTheLeftoversOnce
        image = try TemporaryDirectory()
        self.url = url
        try Data((Self.identity(of: getpid()) ?? "").utf8).write(to: image.url.appending(path: Self.ownerFile))
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
        try requireMounted()
        isMeantToBeMounted = true
    }

    /// Throws unless the disk is mounted where the test asked: a test that wrote before it was would write into the
    /// folder under it.
    private func requireMounted() throws {
        guard isAttached else {
            throw DiskImageTool.Failure(
                command: "hdiutil attach", status: 0, said: "the disk is not mounted at \(url.path)"
            )
        }
    }

    private static func serial(for fileSystem: String, given: UInt32?) -> [String] {
        guard fileSystem.hasPrefix("MS-DOS") || fileSystem == "ExFAT" else { return [] }
        var serial = given ?? 0
        while serial == 0 {
            serial = serials.wrappingAdd(1, ordering: .relaxed).newValue
        }
        return ["-fsargs", "-I \(serial)"]
    }

    /// True when the disk went away while its test still counted on it.
    var leftUnderItsTest: Bool { isMeantToBeMounted && !isAttached }

    deinit {
        // What a test found on a disk that went away under it means nothing, so the test says the disk left.
        if leftUnderItsTest {
            Issue.record("the disk at \(url.path) was no longer mounted when its test ended")
        }
        _ = try? DiskImageTool.eject(url.path)
    }

    /// Takes the disk away, as unplugging it does, until `attach(at:)` brings it back. Answers what the tool said.
    @discardableResult
    func eject() throws -> String {
        isMeantToBeMounted = false
        return try DiskImageTool.eject(url.path)
    }

    /// Where a disk names the process that made it, since a process stopped before its tests end never detaches them.
    private static let ownerFile = "owner"

    /// A process as no other can be: its pid and when it started, or nil when it no longer runs.
    private static func identity(of pid: pid_t) -> String? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return "\(pid) \(info.pbi_start_tvsec).\(info.pbi_start_tvusec)"
    }

    private static let detachTheLeftoversOnce: Void = detachTheLeftovers()

    /// Detaches the disks whose process no longer runs, and no other: those of a process still running, another
    /// suite's included, stay.
    static func detachTheLeftovers() {
        guard let answer = try? DiskImageTool.hdiutil("info", "-plist"),
              let info = try? PropertyListSerialization.propertyList(from: answer, format: nil) as? [String: Any],
              let images = info["images"] as? [[String: Any]]
        else { return }
        let left = mountPointsOfLeftovers(
            among: images, owner: { try? String(contentsOf: $0, encoding: .utf8) }, identity: identity(of:)
        )
        for place in left {
            _ = try? DiskImageTool.eject(place)
        }
    }

    /// Where the disks of processes that no longer run are mounted now, `owner` reading the file that names a disk's
    /// process. A record with nothing mounted is passed over: macOS 27 goes on listing an image after it left, under
    /// device names another disk may have by then.
    static func mountPointsOfLeftovers(
        among images: [[String: Any]], owner: (URL) -> String?, identity: (pid_t) -> String?
    ) -> [String] {
        images.flatMap { image -> [String] in
            guard let path = image["image-path"] as? String, path.hasSuffix("/disk.dmg"),
                  let recorded = owner(URL(filePath: path).deletingLastPathComponent().appending(path: ownerFile)),
                  let pid = pid_t(recorded.prefix { $0 != " " }), identity(pid) != recorded
            else { return [] }
            let entities = image["system-entities"] as? [[String: Any]] ?? []
            return entities.compactMap { $0["mount-point"] as? String }
        }
    }

    /// Records the disk as made by a process that ended, as a suite stopped in the middle leaves it.
    func leaveAsIfItsProcessEnded() throws {
        try Data("999999 0.0".utf8).write(to: image.url.appending(path: Self.ownerFile))
        isMeantToBeMounted = false
    }

    var isAttached: Bool {
        var info = statfs()
        guard statfs(url.path(percentEncoded: false), &info) == 0 else { return false }
        let mount = withUnsafeBytes(of: info.f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return PathPattern.comparablePath(of: URL(filePath: mount))
            == PathPattern.comparablePath(of: url.resolvingSymlinksInPath())
    }

    /// The same disk, detached and mounted again at `place`, as a disk renamed or plugged in again lands elsewhere, or,
    /// `readOnly`, as the disk image an app came on is mounted. It is unmounted without force, since a forced unmount
    /// skips writing out what the file system still holds.
    func remount(at place: URL, readOnly: Bool = false) throws {
        do {
            try DiskImageTool.eject(url.path, force: false)
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
        try requireMounted()
        isMeantToBeMounted = true
    }
}
