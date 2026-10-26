import Darwin
import Foundation
internal import PeelPrivileged

/// The files other processes hold open, read from every process this account may look at (`proc_pidinfo(2)`): an
/// app's agent, a tool's daemon, a server. Of another account's processes, root's included, only the program each
/// runs is seen, never the files it holds open.
struct OpenFiles {
    private enum Hold { case reads, writes, runs }

    /// Whose a process is: this account's, another user's of this Mac, or the system's, root's and the services'.
    enum Owner { case thisAccount, anotherUser, system }

    private typealias File = (
        names: [String], process: String, pid: pid_t, hold: Hold, owner: Owner, daemon: BuildDaemon?
    )

    private let files: [File]
    /// The program each process that holds something runs, by its identifier.
    private let programs: [pid_t: String]
    /// The program the excluded process runs. Its open files are no hold, but where it runs from is.
    private let excludedProgram: [String]?

    /// Each regular file held open for reading or writing, and the program each process runs, which it holds as long
    /// as it runs. A watch (`O_EVTONLY`, as Finder keeps on what it shows) and a folder are no hold on what is inside.
    init(excluding excluded: pid_t? = getpid()) {
        excludedProgram = excluded.flatMap(RunningProgram.path(of:)).map(PathComponents.of)
        var pids = [pid_t](repeating: 0, count: 8_192)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        var files: [File] = []
        var programs: [pid_t: String] = [:]
        for pid in pids.prefix(max(count, 0)) where pid > 0 && pid != excluded && !Self.isACopyOfThisProcess(pid) {
            let path = RunningProgram.path(of: pid)
            let owner = kill(pid, 0) != 0 && errno == EPERM ? Self.owner(ofAccount: Self.uid(of: pid)) : .thisAccount
            let runs = (path.flatMap(Self.program(at:)).map { [$0] } ?? [])
                + (owner == .thisAccount ? Self.scripts(runBy: pid, program: path) : [])
            let paths = Self.paths(openBy: pid) + runs.map { (path: $0, hold: Hold.runs) }
            guard !paths.isEmpty else { continue }
            programs[pid] = path
            let process = Self.name(of: pid, program: path)
            let isJava = path.map { URL(filePath: $0).lastPathComponent == "java" } == true
            let daemon = owner == .thisAccount && isJava
                ? Self.arguments(of: pid).flatMap(BuildDaemon.running(with:)) : nil
            files += paths.map { (PathComponents.of($0.path), process, pid, $0.hold, owner, daemon) }
        }
        self.files = files
        self.programs = programs
    }

    /// How long a reading is trusted: a removal of many items takes seconds, and a program can start meanwhile.
    static let lifetime: Duration = .seconds(1)

    /// A reading of the open files that is made again once it is older than `lifetime`.
    struct Fresh {
        private var reading = OpenFiles()
        private var read = ContinuousClock.now

        mutating func refusal(of url: URL, lettingItsProgramsRun: Bool) -> TrashFailure.Reason? {
            if ContinuousClock.now - read > OpenFiles.lifetime {
                reading = OpenFiles()
                read = .now
            }
            return reading.refusal(of: url, lettingItsProgramsRun: lettingItsProgramsRun)
        }
    }

    /// The programs that hold `url`. An app is code, which loses nothing when it moves, so a program that only reads
    /// inside it, as Safari reads an app's Safari extension, holds nothing: what runs from it or writes in it does.
    func holders(of url: URL, lettingItsProgramsRun: Bool = false) -> [String] {
        Set(holding(url, lettingItsProgramsRun: lettingItsProgramsRun).map(\.process)).sorted()
    }

    func processes(holding url: URL, lettingItsProgramsRun: Bool = false) -> Set<pid_t> {
        Set(holding(url, lettingItsProgramsRun: lettingItsProgramsRun).map(\.pid))
    }

    /// Why `url` can't move while it is held, or nil when nothing holds it.
    func refusal(of url: URL, lettingItsProgramsRun: Bool) -> TrashFailure.Reason? {
        let names = PathComponents.of(PathPattern.canonical(url).path(percentEncoded: false))
        if !lettingItsProgramsRun, let excludedProgram, excludedProgram.starts(with: names) { return .peelRunsFromIt }
        return Self.refusal(heldBy: holding(url, lettingItsProgramsRun: lettingItsProgramsRun).map { file in
            Holder(
                process: file.process, owner: file.owner,
                isMacOSsOwn: programs[file.pid].map(Self.isMacOSsOwn) ?? false, daemon: file.daemon
            )
        })
    }

    struct Holder {
        let process: String
        let owner: Owner
        let isMacOSsOwn: Bool
        var daemon: BuildDaemon? = nil
    }

    /// Why an item held by `holders` can't move, each kind of holder with the step that lets it go.
    static func refusal(heldBy holders: [Holder]) -> TrashFailure.Reason? {
        guard !holders.isEmpty else { return nil }
        // macOS's own programs are named only when nothing else holds the item, since nobody quits them.
        let named = holders.filter { !$0.isMacOSsOwn }
        guard !named.isEmpty else { return .inUseByMacOS(by: Set(holders.map(\.process)).sorted()) }
        let processes = { (owner: Owner) in Set(named.filter { $0.owner == owner }.map(\.process)).sorted() }
        if case let users = processes(.anotherUser), !users.isEmpty { return .openForAnotherUser(by: users) }
        if case let system = processes(.system), !system.isEmpty { return .heldByAnotherAccount(by: system) }
        let daemons = named.compactMap(\.daemon)
        if daemons.count == named.count { return .heldByABuildTool(by: Set(daemons.map(\.rawValue)).sorted()) }
        return .heldOpen(by: Set(named.map(\.process)).sorted())
    }

    /// The scripts a process runs when its program is one that runs a script named as an argument (Node.js, Deno,
    /// Bun, Python, Ruby or Perl): it loads from beside each as long as it runs, as a program runs from its own file.
    private static func scripts(runBy pid: pid_t, program: String?) -> [String] {
        guard let name = program.map({ URL(filePath: $0).lastPathComponent }),
              ["node", "deno", "bun", "ruby", "perl"].contains(name) || name.hasPrefix("python")
        else { return [] }
        return (arguments(of: pid) ?? []).dropFirst().filter { $0.hasPrefix("/") }.map {
            PathPattern.canonical(URL(filePath: $0)).path(percentEncoded: false)
        }
    }

    /// The arguments a process of this account was started with, as `sysctl` gives them (`KERN_PROCARGS2`): their
    /// count, the program's path and the zero bytes after it, then each argument, ended by a zero byte.
    static func arguments(of pid: pid_t) -> [String]? {
        var maximum: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var name = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&name, u_int(name.count), &maximum, &size, nil, 0) == 0, maximum > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(maximum))
        size = buffer.count
        name = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&name, u_int(name.count), &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size
        else { return nil }
        let count = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < count, index < size {
            let end = buffer[index..<size].firstIndex(of: 0) ?? size
            arguments.append(String(decoding: buffer[index..<end], as: UTF8.self))
            index = end + 1
        }
        return arguments
    }

    /// A user account starts at 501 on macOS, and the accounts below it are the system's services; `nobody` is -2.
    static func owner(ofAccount uid: uid_t?) -> Owner {
        guard let uid, uid >= 501, uid != uid_t(bitPattern: -2) else { return .system }
        return .anotherUser
    }

    /// The account a process runs as, which `sysctl` tells of any process, root's included.
    static func uid(of pid: pid_t) -> uid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var name = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ucred.cr_uid
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

    /// Whether the program at `path` is one of macOS's own, which nobody quits: on the sealed system volume or in its
    /// cryptexes, in `/usr/libexec`, `/usr/sbin`, `/sbin` or `/Library/Apple`. An app in the system's Applications
    /// folders and a command in `/bin` or `/usr/bin` are the person's to quit.
    static func isMacOSsOwn(_ path: String) -> Bool {
        let isInside = { (folder: String) in PathComponents.isPath(path, inside: folder) }
        let cryptexes = "/System/Volumes/Preboot/Cryptexes"
        let apps = [
            "/System/Applications", "/System/Library/CoreServices/Applications",
            "/System/Cryptexes/App/System/Applications", "\(cryptexes)/App/System/Applications",
        ]
        guard !apps.contains(where: isInside) else { return false }
        if isInside("/System/Volumes") { return isInside(cryptexes) }
        return ["/System", "/usr/libexec", "/usr/sbin", "/sbin", "/Library/Apple"].contains(where: isInside)
    }

    /// The program at `path`, which a process runs, unless it is an app extension: macOS starts those on their app's
    /// behalf, so the person could not quit one to let its app go.
    private static func program(at path: String) -> String? {
        PathComponents.of(path).contains { $0.hasSuffix(".appex") } ? nil : path
    }

    /// The name of the program the process runs. The process's own name is the fallback: the kernel keeps only its
    /// first 32 bytes (`2 * MAXCOMLEN`).
    static func name(of pid: pid_t) -> String {
        name(of: pid, program: RunningProgram.path(of: pid))
    }

    private static func name(of pid: pid_t, program path: String?) -> String {
        if let path { return URL(filePath: path).lastPathComponent }
        var buffer = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "process \(pid)" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
