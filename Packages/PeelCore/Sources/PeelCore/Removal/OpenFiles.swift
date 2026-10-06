import Darwin
import Foundation
internal import PeelPrivileged

/// The files other processes hold open, read from every process this account may look at (`proc_pidinfo(2)`): an
/// app's agent, a tool's daemon, a server. Of another account's processes, root's included, only the program each
/// runs is seen, never the files it holds open.
struct OpenFiles {
    /// `holdsAnApp` is false for a file a process only reads: inside an app, that holds nothing.
    private let files: [(names: [String], process: String, holdsAnApp: Bool)]

    /// Each regular file held open for reading or writing, and the program each process runs, which it holds as long
    /// as it runs. A watch (`O_EVTONLY`, as Finder keeps on what it shows) and a folder are no hold on what is inside.
    init(excluding excluded: pid_t? = getpid()) {
        var pids = [pid_t](repeating: 0, count: 8_192)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        var files: [(names: [String], process: String, holdsAnApp: Bool)] = []
        for pid in pids.prefix(max(count, 0)) where pid > 0 && pid != excluded {
            let program = Self.program(of: pid).map { [(path: $0, holdsAnApp: true)] } ?? []
            let paths = Self.paths(openBy: pid) + program
            guard !paths.isEmpty else { continue }
            let process = Self.name(of: pid)
            files += paths.map { (PathComponents.of($0.path), process, $0.holdsAnApp) }
        }
        self.files = files
    }

    /// The programs that hold `url`. An app is code, which loses nothing when it moves, so a program that only reads
    /// inside it, as Safari reads an app's Safari extension, holds nothing: what runs from it or writes in it does.
    func holders(of url: URL) -> [String] {
        let names = PathComponents.of(PathPattern.canonical(url).path(percentEncoded: false))
        let isAnApp = url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
        return Set(files.filter { $0.names.starts(with: names) && ($0.holdsAnApp || !isAnApp) }.map(\.process)).sorted()
    }

    /// The regular files `pid` holds open, each with whether it may write to it.
    private static func paths(openBy pid: pid_t) -> [(path: String, holdsAnApp: Bool)] {
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
            let path = withUnsafeBytes(of: info.pvip.vip_path) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
            return (path, info.pfi.fi_openflags & UInt32(FWRITE) != 0)
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
