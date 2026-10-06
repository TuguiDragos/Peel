import Darwin
import Foundation
internal import PeelPrivileged

/// The files other processes hold open, read from every process this account may look at (`proc_pidinfo(2)`): an
/// app's agent, a tool's daemon, a server. Of another account's processes, root's included, only the program each
/// runs is seen, never the files it holds open.
struct OpenFiles {
    private let files: [(names: [String], process: String)]

    /// Each regular file held open for reading or writing, and the program each process runs, which it holds as long
    /// as it runs. A watch (`O_EVTONLY`, as Finder keeps on what it shows) and a folder are no hold on what is inside.
    init(excluding excluded: pid_t? = getpid()) {
        var pids = [pid_t](repeating: 0, count: 8_192)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        var files: [(names: [String], process: String)] = []
        for pid in pids.prefix(max(count, 0)) where pid > 0 && pid != excluded {
            let paths = Self.paths(openBy: pid) + [Self.program(of: pid)].compactMap(\.self)
            guard !paths.isEmpty else { continue }
            let process = Self.name(of: pid)
            files += paths.map { (PathComponents.of($0), process) }
        }
        self.files = files
    }

    func holders(of url: URL) -> [String] {
        let names = PathComponents.of(PathPattern.canonical(url).path(percentEncoded: false))
        return Set(files.filter { $0.names.starts(with: names) }.map(\.process)).sorted()
    }

    private static func paths(openBy pid: pid_t) -> [String] {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / MemoryLayout<proc_fdinfo>.size)
        let filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, size)
        guard filled > 0 else { return [] }
        return descriptors.prefix(Int(filled) / MemoryLayout<proc_fdinfo>.size).compactMap { descriptor in
            guard descriptor.proc_fdtype == PROX_FDTYPE_VNODE else { return nil }
            var info = vnode_fdinfowithpath()
            let expected = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, expected) == expected,
                  info.pfi.fi_openflags & UInt32(O_EVTONLY) == 0,
                  mode_t(info.pvip.vip_vi.vi_stat.vst_mode) & S_IFMT == S_IFREG
            else { return nil }
            return withUnsafeBytes(of: info.pvip.vip_path) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
        }
    }

    /// The program a process runs, unless it is an app extension: macOS starts and ends those on their app's behalf,
    /// so the person could not quit one to let its app go.
    private static func program(of pid: pid_t) -> String? {
        guard let path = path(of: pid) else { return nil }
        return PathComponents.of(path).contains { $0.hasSuffix(".appex") } ? nil : path
    }

    /// The process's name, or, for another account's process, which macOS does not name, its program's.
    static func name(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else {
            return path(of: pid).map { URL(filePath: $0).lastPathComponent } ?? "process \(pid)"
        }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
