import Darwin
import Foundation
import PeelPrivileged

public enum BackgroundItemActions {
    public enum Failure: Error, Sendable, Hashable {
        case requiresPrivileges
        /// The job has no file Peel may move: an app submitted it, or its label is Apple's.
        case noFileToMove
        case launchctl(String)
        case trash(TrashFailure.Reason)
        /// On macOS 27 and later, launchd refuses to load a job whose property list carries the quarantine mark
        /// that macOS puts on downloads.
        case quarantinedPlist
        /// launchd does not load a job that is disabled (`bootstrap` answers error 5), so it is enabled first.
        case disabled
        case turnedOffInSystemSettings
        /// Peel doesn't act on the job as it is now, such as one excluded since the list was read: the page offers
        /// nothing for a job like that, so this is what changed after.
        case notControlled
    }

    /// Why Peel will not start, stop or switch `item`, or nil. These go by label, so a label macOS itself uses
    /// would reach macOS's own job.
    static func refusal(for item: BackgroundItem) -> Failure? {
        item.canBeControlled ? nil : .notControlled
    }

    /// How long Stop waits for the job's process to end, as long as `launchctl` itself gets.
    static let exitWait: TimeInterval = 30

    @concurrent
    public static func stop(_ item: BackgroundItem) async throws(Failure) {
        try await stop(item, waitingUpTo: exitWait) { await Launchctl.run($0) }
    }

    /// Takes the job out of launchd, then waits up to `limit` for the process launchd still names for it to end:
    /// `bootout` returns at once, while launchd keeps a job whose process ignores the signal until its ExitTimeOut
    /// and only then kills it, and the job read meanwhile would still show as running.
    static func stop(
        _ item: BackgroundItem,
        waitingUpTo limit: TimeInterval,
        launchctl: ([String]) async -> (status: Int32, output: String),
        untilEnded: (pid_t, TimeInterval) async -> Bool = { await ProcessEnds.ends($0, within: $1) }
    ) async throws(Failure) {
        if let refusal = refusal(for: item) { throw refusal }
        do throws(Failure) {
            if item.requiresPrivileges {
                try await runPrivileged(.bootout, for: item)
            } else {
                try await run(["bootout", target(of: item)], with: launchctl)
            }
        } catch {
            if !(await isGone(item, asking: launchctl)) { throw error }
            return
        }
        let printed = await launchctl(["print", target(of: item)])
        guard case .details(let details) = Launchctl.answer(status: printed.status, output: printed.output),
              let process = details.pid
        else { return }
        _ = await untilEnded(process, limit)
    }

    /// How an item is started: loaded from its file with `bootstrap` when launchd does not have it, or
    /// otherwise started by label with `kickstart`.
    enum Start: Sendable, Equatable {
        case bootstrap(URL)
        case kickstart
        /// The job's file carries the quarantine mark, so launchd on macOS 27 and later would refuse to load it.
        /// A job that is already loaded is still started with `kickstart`.
        case blockedByQuarantine
        case needsEnabling
    }

    static func plan(
        toStart item: BackgroundItem,
        isRefusedByLaunchd: (URL) -> Bool = Quarantine.stopsLaunchd
    ) -> Start {
        guard !item.startsAtOnce, let plist = item.plistURL else { return .kickstart }
        if item.isDisabled { return .needsEnabling }
        return isRefusedByLaunchd(plist) ? .blockedByQuarantine : .bootstrap(plist)
    }

    /// `item` as launchd has it now. The page read it earlier, and a job loaded since then answers `bootstrap` with
    /// error 5, while one gone since then answers `kickstart` with error 113.
    static func asItIsNow(_ item: BackgroundItem, isGone: Bool) -> BackgroundItem {
        var now = item
        if isGone {
            now.state = .notLoaded
        } else if item.state == .notLoaded {
            now.state = .loaded
        }
        return now
    }

    /// Asks macOS again: the page read the job's status earlier.
    static func refusal(toStart item: BackgroundItem) -> Failure? {
        if let refusal = refusal(for: item) { return refusal }
        return LoginItemsStatus.of(item)?.letsItRun == false ? .turnedOffInSystemSettings : nil
    }

    @concurrent
    public static func start(_ item: BackgroundItem) async throws(Failure) {
        if let refusal = refusal(toStart: item) { throw refusal }
        switch plan(toStart: asItIsNow(item, isGone: await isGone(item))) {
        case .blockedByQuarantine:
            throw .quarantinedPlist
        case .needsEnabling:
            throw .disabled
        case .bootstrap(let plist):
            if item.requiresPrivileges {
                try await runPrivileged(.bootstrap, for: item)
            } else {
                try await run(["bootstrap", domain(of: item), plist.path(percentEncoded: false)])
            }
        case .kickstart:
            if item.requiresPrivileges {
                try await runPrivileged(.kickstart, for: item)
            } else {
                try await run(["kickstart", target(of: item)])
            }
        }
    }

    /// Stops the running job and starts it again at once (`launchctl kickstart -k`).
    @concurrent
    public static func restart(_ item: BackgroundItem) async throws(Failure) {
        if let refusal = refusal(toStart: item) { throw refusal }
        if item.requiresPrivileges {
            try await runPrivileged(.restart, for: item)
        } else {
            try await run(["kickstart", "-k", target(of: item)])
        }
    }

    /// Why Peel will not switch `item` on or off, or nil. Only System Settings turns off a job ServiceManagement
    /// manages, and a job whose row would leave the list once disabled is never disabled from here.
    static func refusal(toSwitch item: BackgroundItem, on isEnabled: Bool) -> Failure? {
        if let refusal = refusal(for: item) { return refusal }
        return !isEnabled && !item.mayBeDisabled ? .notControlled : nil
    }

    @concurrent
    public static func setEnabled(_ isEnabled: Bool, for item: BackgroundItem) async throws(Failure) {
        if let refusal = refusal(toSwitch: item, on: isEnabled) { throw refusal }
        if item.requiresPrivileges {
            try await runPrivileged(isEnabled ? .enable : .disable, for: item)
        } else {
            try await run([isEnabled ? "enable" : "disable", target(of: item)])
        }
    }

    /// What moving a job to the Trash did.
    public struct Moved: Sendable {
        /// What moved and what was refused, to be written down like any other removal.
        public let result: TrashResult
        /// Why launchd still runs the job whose file moved. Nothing loads it again, but it runs until the Mac restarts.
        public let stillRunning: Failure?
    }

    /// Moves the job's property list to the Trash, then unloads the job. The move comes first, so a refused move
    /// never leaves the job stopped with its file still in place.
    @concurrent
    public static func moveToTrash(
        _ item: BackgroundItem, exclusions: Exclusions = .none
    ) async throws(Failure) -> Moved {
        // The file's move and the job's stop after it share one administrator's approval.
        try await PrivilegedHelper.withOneConsent { () async throws(Failure) -> Moved in
            try await moveToTrash(
                item,
                isHelperEnabled: PrivilegedHelper.status == .enabled,
                trash: TrashService(exclusions: exclusions)
            ) { item in
                do throws(Failure) {
                    try await stop(item)
                    return nil
                } catch {
                    return error
                }
            }
        }
    }

    static func moveToTrash(
        _ item: BackgroundItem,
        isHelperEnabled: Bool,
        trash: TrashService,
        stop: (BackgroundItem) async -> Failure?
    ) async throws(Failure) -> Moved {
        guard item.canMoveToTrash, let plist = item.plistURL else { throw .noFileToMove }
        // Asked now, with the exclusions this move goes by: the app may have been excluded since the job was read.
        if trash.excludes(ownerOf: item) {
            let refused = TrashFailure(url: plist, reason: .guarded(.excluded))
            return Moved(result: TrashResult(failures: [refused]), stillRunning: nil)
        }
        if item.removalRequiresPrivileges, !isHelperEnabled {
            throw .requiresPrivileges
        }
        let result = await trash.trash([plist], usingHelperFor: item.removalRequiresPrivileges ? [plist] : [])
        // `TrashService` stops a job only when `PrivilegedPathPolicy.isValidLabel` accepts its label. The user
        // chose this job, so it is also stopped here by its own label; a row named by its file has none Peel read.
        guard !result.trashed.isEmpty, item.state != .notLoaded, !item.isNamedByItsFile else {
            return Moved(result: result, stillRunning: nil)
        }
        return Moved(result: result, stillRunning: await stop(item))
    }

    /// Whether launchd no longer has `item`: `launchctl print` exits with 113 for a job it does not have, in either
    /// domain and whoever asks. A job that went away by itself needed no stopping.
    static func isGone(
        _ item: BackgroundItem,
        asking launchctl: ([String]) async -> (status: Int32, output: String) = { await Launchctl.run($0) }
    ) async -> Bool {
        await launchctl(["print", target(of: item)]).status == 113
    }

    private static func run(
        _ arguments: [String],
        with launchctl: ([String]) async -> (status: Int32, output: String) = { await Launchctl.run($0) }
    ) async throws(Failure) {
        let result = await launchctl(arguments)
        guard result.status == 0 else {
            throw .launchctl(Launchctl.withoutAdviceToRunAsRoot(result.output))
        }
    }

    private static func runPrivileged(_ command: DaemonCommand, for item: BackgroundItem) async throws(Failure) {
        guard PrivilegedHelper.status == .enabled else { throw .requiresPrivileges }
        if let failure = await PrivilegedHelper.runDaemonCommand(command, label: item.label) {
            throw .launchctl(failure.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func domain(of item: BackgroundItem) -> String {
        guard item.kind == .agent else { return "system" }
        return item.loadsInTheBackgroundSession ? "user/\(getuid())" : "gui/\(getuid())"
    }

    static func target(of item: BackgroundItem) -> String {
        "\(domain(of: item))/\(item.label)"
    }
}
