import Darwin
import Foundation
import PeelPrivileged

final class HelperService: NSObject, PeelHelperProtocol {
    /// Tracks each request from its start until its reply is sent, so the helper never exits in the middle of one.
    private let lifetime: HelperLifetime

    init(lifetime: HelperLifetime) {
        self.lifetime = lifetime
    }

    /// The account behind the connection the message came on, and its home folder, when it is an administrator or
    /// `approval` holds an administrator's approval now. It is asked for each message, so an account that stops being
    /// an administrator is refused from its next request. It says whose connection it is, not which process sent the
    /// message: `xpc_connection_create(3)` warns that a client can hand its connection to another process.
    private static func caller(approval: Data = Data()) -> Result<HelperRequest.Caller, HelperRefusal> {
        HelperRequest.caller(user: NSXPCConnection.current()?.effectiveUserIdentifier, approval: approval)
    }

    /// The `peel` tool of the app the helper runs from, found from the program the kernel says it runs.
    private static let ownTool = RunningProgram.path(of: getpid())
        .flatMap(PrivilegedPathPolicy.peelTool(besideHelperAt:))

    private func tracked(_ finish: @escaping @Sendable (String?) -> Void) -> @Sendable (String?) -> Void {
        { [lifetime] answer in
            finish(answer)
            lifetime.requestFinished()
        }
    }

    func protocolVersion(withReply reply: @escaping @Sendable (Int) -> Void) {
        reply(HelperIdentity.protocolVersion)
    }

    func moveItemsToTrash(
        version: Int,
        approval: Data,
        atPaths paths: [String],
        withReply finish: @escaping @Sendable ([String: String], [String: String]) -> Void
    ) {
        lifetime.requestStarted()
        let reply: @Sendable ([String: String], [String: String]) -> Void = { [lifetime] moved, failed in
            finish(moved, failed)
            lifetime.requestFinished()
        }
        func refuse(_ reason: String) {
            reply([:], Dictionary(paths.prefix(HelperRequest.maximumItems).map { ($0, reason) }) { first, _ in first })
        }
        let caller: HelperRequest.Caller
        do {
            caller = try HelperRequest.admit(version: version, items: paths.count) {
                Self.caller(approval: approval)
            }.get()
        } catch {
            return refuse(error.rawValue)
        }

        let policy = PrivilegedPathPolicy(homeDirectory: caller.homeDirectory, ownTool: Self.ownTool)
        guard let trash = policy.openTrash(ownedBy: caller.user) else { return refuse(HelperRefusal.noTrash.rawValue) }

        var failed: [String: String] = [:]
        var items: [(path: String, item: OpenItem)] = []
        for path in paths {
            guard !HelperRequest.isTooLong(path) else {
                failed[path] = HelperRefusal.pathTooLong.rawValue
                continue
            }
            switch policy.open(path) {
            case .failure(let rejection): failed[path] = rejection.explanation
            case .success(let item): items.append((path, item))
            }
        }
        // Recorded before anything moves, so no item reaches the Trash without a record. The helper puts
        // back only what its ledger lists.
        guard
            let ledger = HelperLedger(),
            let result = TrashMover.moveRecorded(items, into: trash, ledger: ledger, movedBy: caller.user)
        else {
            return refuse(HelperRefusal.cannotKeepRecord.rawValue)
        }
        reply(result.moved, failed.merging(result.failed) { refused, _ in refused })
    }

    func restoreItem(
        version: Int,
        approval: Data,
        fromTrashPath trashPath: String,
        toPath destination: String,
        withReply finish: @escaping @Sendable (String?) -> Void
    ) {
        lifetime.requestStarted()
        let reply = tracked(finish)
        let caller: HelperRequest.Caller
        do {
            let paths = [trashPath, destination]
            caller = try HelperRequest.admit(version: version, paths: paths) { Self.caller(approval: approval) }.get()
        } catch {
            return reply(error.rawValue)
        }

        let policy = PrivilegedPathPolicy(homeDirectory: caller.homeDirectory)
        reply(HelperPutBack.run(trashPath, to: destination, for: caller.user, policy: policy))
    }

    func moveLedgerToTrash(version: Int, withReply finish: @escaping @Sendable (String?) -> Void) {
        lifetime.requestStarted()
        let reply = tracked(finish)
        let caller: HelperRequest.Caller
        do {
            caller = try HelperRequest.admit(version: version) { Self.caller() }.get()
        } catch {
            return reply(error.rawValue)
        }
        guard let trash = PrivilegedPathPolicy(homeDirectory: caller.homeDirectory).openTrash(ownedBy: caller.user)
        else {
            return reply(HelperRefusal.noTrash.rawValue)
        }
        switch HelperLedger.moveFolder(into: trash, givingTo: caller.user) {
        case .success: reply(nil)
        case .failure(let error): reply(error.localizedDescription)
        }
    }

    func runDaemonCommand(
        version: Int,
        approval: Data,
        command: String,
        label: String,
        withReply finish: @escaping @Sendable (String?) -> Void
    ) {
        lifetime.requestStarted()
        let reply = tracked(finish)
        let admitted = HelperRequest.admit(version: version) { Self.caller(approval: approval) }
        if case .failure(let refusal) = admitted {
            return reply(refusal.rawValue)
        }
        guard let command = DaemonCommand(rawValue: command), PrivilegedPathPolicy.allowsDaemon(label) else {
            return reply(HelperRefusal.invalidRequest.rawValue)
        }
        let target = "system/\(label)"
        // The job's file is found by the `Label` inside it, since a file's name does not always match its label.
        let plists = command == .bootstrap ? SystemDaemons.files(declaring: label) : []
        if command == .bootstrap, plists.count != 1 {
            reply((plists.isEmpty ? HelperRefusal.missingConfiguration : .declaredTwice).rawValue)
            return
        }
        let arguments = switch command {
        case .bootstrap: ["bootstrap", "system", plists[0]]
        case .bootout: ["bootout", target]
        case .kickstart: ["kickstart", target]
        case .restart: ["kickstart", "-k", target]
        case .enable: ["enable", target]
        case .disable: ["disable", target]
        }

        // 30 seconds: `kickstart -k` waits for the job to exit and start again, and the helper never waits forever.
        Task {
            switch await Subprocess.run("/bin/launchctl", arguments, timeout: 30) {
            case .success(let output): reply(output.status == 0 ? nil : output.text + output.errorText)
            case .failure(let failure): reply(failure.explanation)
            }
        }
    }
}
