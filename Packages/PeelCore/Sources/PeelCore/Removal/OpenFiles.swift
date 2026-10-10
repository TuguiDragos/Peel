import Darwin
import Foundation
internal import PeelPrivileged

/// The files other processes hold open, read from every process this account may look at (`proc_pidinfo(2)`): an
/// app's agent, a tool's daemon, a server. Of another account's processes, root's included, only the program each
/// runs is seen, never the files it holds open.
struct OpenFiles {
    private enum Hold { case reads, writes, runs }

    private typealias File = (names: [String], process: String, hold: Hold, isAnotherAccounts: Bool)

    private let files: [File]
    /// The program the excluded process runs. Its open files are no hold, but where it runs from is.
    private let excludedProgram: [String]?

    /// Each regular file held open for reading or writing, and the program each process runs, which it holds as long
    /// as it runs. A watch (`O_EVTONLY`, as Finder keeps on what it shows) and a folder are no hold on what is inside.
    init(excluding excluded: pid_t? = getpid()) {
        excludedProgram = excluded.flatMap(RunningProgram.path(of:)).map(PathComponents.of)
        var pids = [pid_t](repeating: 0, count: 8_192)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        var files: [File] = []
        for pid in pids.prefix(max(count, 0)) where pid > 0 && pid != excluded && !Self.isACopyOfThisProcess(pid) {
            let program = Self.program(of: pid).map { [(path: $0, hold: Hold.runs)] } ?? []
            let paths = Self.paths(openBy: pid) + program
            guard !paths.isEmpty else { continue }
            let process = Self.name(of: pid)
            let isAnotherAccounts = kill(pid, 0) != 0 && errno == EPERM
            files += paths.map { (PathComponents.of($0.path), process, $0.hold, isAnotherAccounts) }
        }
        self.files = files
    }

    /// The programs that hold `url`. An app is code, which loses nothing when it moves, so a program that only reads
    /// inside it, as Safari reads an app's Safari extension, holds nothing: what runs from it or writes in it does.
    func holders(of url: URL, lettingItsProgramsRun: Bool = false) -> [String] {
        Set(holding(url, lettingItsProgramsRun: lettingItsProgramsRun).map(\.process)).sorted()
    }

    /// Why `url` can't move while it is held, or nil when nothing holds it.
    func refusal(of url: URL, lettingItsProgramsRun: Bool) -> TrashFailure.Reason? {
        let names = PathComponents.of(PathPattern.canonical(url).path(percentEncoded: false))
        if !lettingItsProgramsRun, let excludedProgram, excludedProgram.starts(with: names) { return .peelRunsFromIt }
        let holding = holding(url, lettingItsProgramsRun: lettingItsProgramsRun)
        let others = Set(holding.filter(\.isAnotherAccounts).map(\.process)).sorted()
        if !others.isEmpty { return .heldByAnotherAccount(by: others) }
        let holders = Set(holding.map(\.process)).sorted()
        return holders.isEmpty ? nil : .heldOpen(by: holders)
    }

    private func holding(_ url: URL, lettingItsProgramsRun: Bool) -> [File] {
        let names = PathComponents.of(PathPattern.canonical(url).path(percentEncoded: false))
        let isAnApp = url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
        return files.filter { file in
            guard file.names.starts(with: names) else { return false }
            switch file.hold {
            case .reads: return !isAnApp
            case .writes: return true
            case .runs: return !lettingItsProgramsRun
            }
        }
    }

    private static func paths(openBy pid: pid_t) -> [(path: String, hold: Hold)] {
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
            return (path, info.pfi.fi_openflags & UInt32(FWRITE) != 0 ? .writes : .reads)
        }
    }

    /// A process this one starts is a copy of it until the program it starts takes its place, and meanwhile holds
    /// only this process's files.
    private static func isACopyOfThisProcess(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_ppid == UInt32(getpid()) else {
            return false
        }
        return RunningProgram.path(of: pid) == RunningProgram.path(of: getpid())
    }

    /// The program a process runs, unless it is an app extension: macOS starts and ends those on their app's behalf,
    /// so the person could not quit one to let its app go.
    private static func program(of pid: pid_t) -> String? {
        guard let path = RunningProgram.path(of: pid) else { return nil }
        return PathComponents.of(path).contains { $0.hasSuffix(".appex") } ? nil : path
    }

    /// The process's name, or, for another account's process, which macOS does not name, its program's.
    static func name(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else {
            return RunningProgram.path(of: pid).map { URL(filePath: $0).lastPathComponent } ?? "process \(pid)"
        }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
