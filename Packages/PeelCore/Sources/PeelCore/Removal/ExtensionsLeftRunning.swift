import Darwin
import Foundation
internal import PeelPrivileged

/// This account's app extensions still running from apps in the Trash, where nobody can quit them: moving an app
/// leaves them running.
enum ExtensionsLeftRunning {
    /// Ends those running from `apps`, in one pass over the processes, and returns once each has ended or `limit`
    /// has passed, with their identifiers.
    @discardableResult
    static func end(runningFrom apps: [URL], within limit: TimeInterval = 2) async -> [pid_t] {
        let ended = signal(runningFrom: apps)
        await withTaskGroup(of: Void.self) { group in
            for identifier in ended {
                group.addTask { _ = await ProcessEnds.ends(identifier, within: limit) }
            }
        }
        return ended
    }

    private static func signal(runningFrom apps: [URL]) -> [pid_t] {
        let bundles = apps.map { PathComponents.of(PathPattern.comparablePath(of: PathPattern.canonical($0))) }
        guard !bundles.isEmpty else { return [] }
        var pids = [pid_t](repeating: 0, count: 8_192)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        return pids.prefix(max(count, 0)).filter { pid in
            guard pid > 0, pid != getpid(), isThisAccounts(pid), let program = RunningProgram.path(of: pid) else {
                return false
            }
            let names = PathComponents.of(PathPattern.comparablePath(of: URL(filePath: program)))
            let isAnExtension = bundles.contains { bundle in
                names.count > bundle.count && names.starts(with: bundle)
                    && names.dropFirst(bundle.count).contains(where: { $0.hasSuffix(".appex") })
            }
            return isAnExtension && kill(pid, SIGTERM) == 0
        }
    }

    private static func isThisAccounts(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size && info.pbi_uid == getuid()
    }
}
