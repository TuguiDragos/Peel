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
    }

    /// Why Peel will not start, stop or switch `item`, or nil. These go by label, so a label macOS itself uses
    /// would reach macOS's own job. The helper refuses one for a daemon, and the same answer holds here for an
    /// agent, which `launchctl` runs without the helper.
    static func refusal(for item: BackgroundItem) -> Failure? {
        item.usesALabelOfMacOS ? .launchctl(HelperRefusal.invalidRequest.rawValue) : nil
    }

    @concurrent
    public static func stop(_ item: BackgroundItem) async throws(Failure) {
        if let refusal = refusal(for: item) { throw refusal }
        if item.requiresPrivileges {
            try await runPrivileged(.bootout, for: item)
        } else {
            try await run(["bootout", target(of: item)])
        }
    }

    /// How an item is started: loaded from its file with `bootstrap` when launchd does not have it, or
    /// otherwise started by label with `kickstart`.
    enum Start: Sendable, Equatable {
        case bootstrap(URL)
        case kickstart
        /// The job's file carries the quarantine mark, so launchd on macOS 27 and later would refuse to load it.
        /// A job that is already loaded is still started with `kickstart`.
        case blockedByQuarantine
    }

    static func plan(toStart item: BackgroundItem, isRefusedByLaunchd: (URL) -> Bool = Quarantine.stopsLaunchd) -> Start {
        guard item.state == .notLoaded, let plist = item.plistURL else { return .kickstart }
        return isRefusedByLaunchd(plist) ? .blockedByQuarantine : .bootstrap(plist)
    }

    @concurrent
    public static func start(_ item: BackgroundItem) async throws(Failure) {
        if let refusal = refusal(for: item) { throw refusal }
        switch plan(toStart: item) {
        case .blockedByQuarantine:
            throw .quarantinedPlist
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

    @concurrent
    public static func setEnabled(_ isEnabled: Bool, for item: BackgroundItem) async throws(Failure) {
        if let refusal = refusal(for: item) { throw refusal }
        if item.requiresPrivileges {
            try await runPrivileged(isEnabled ? .enable : .disable, for: item)
        } else {
            try await run([isEnabled ? "enable" : "disable", target(of: item)])
        }
    }

    /// Moves the job's property list to the Trash, then unloads the job. The move comes first, so a refused move
    /// never leaves the job stopped with its file still in place. A refused move comes back in the result, to be
    /// written down like any other refusal.
    @concurrent
    @discardableResult
    public static func moveToTrash(_ item: BackgroundItem, exclusions: Exclusions = .none) async throws(Failure) -> TrashResult {
        try await moveToTrash(
            item,
            isHelperEnabled: PrivilegedHelper.status == .enabled,
            trash: TrashService(exclusions: exclusions),
            stop: { try? await stop($0) }
        )
    }

    static func moveToTrash(
        _ item: BackgroundItem,
        isHelperEnabled: Bool,
        trash: TrashService,
        stop: (BackgroundItem) async -> Void
    ) async throws(Failure) -> TrashResult {
        guard item.canMoveToTrash, let plist = item.plistURL else { throw .noFileToMove }
        if item.removalRequiresPrivileges, !isHelperEnabled {
            throw .requiresPrivileges
        }
        let result = await trash.trash([plist], usingHelperFor: item.removalRequiresPrivileges ? [plist] : [])
        // `TrashService` stops a job only when `PrivilegedPathPolicy.isValidLabel` accepts its label. The user
        // chose this job, so it is also stopped here by its own label. A job that is already gone is not a failure.
        if !result.trashed.isEmpty, item.state != .notLoaded {
            await stop(item)
        }
        return result
    }

    private static func run(_ arguments: [String]) async throws(Failure) {
        let result = await Launchctl.run(arguments)
        guard result.status == 0 else {
            throw .launchctl(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func runPrivileged(_ command: DaemonCommand, for item: BackgroundItem) async throws(Failure) {
        guard PrivilegedHelper.status == .enabled else { throw .requiresPrivileges }
        if let failure = await PrivilegedHelper.runDaemonCommand(command, label: item.label) {
            throw .launchctl(failure.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func domain(of item: BackgroundItem) -> String {
        item.kind == .agent ? "gui/\(getuid())" : "system"
    }

    private static func target(of item: BackgroundItem) -> String {
        "\(domain(of: item))/\(item.label)"
    }
}
