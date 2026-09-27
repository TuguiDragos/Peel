import Darwin
import Foundation
import PeelPrivileged

final class HelperService: NSObject, PeelHelperProtocol {
    /// Tracks each request from its start until its reply is sent, so the helper never exits in the middle of one.
    private let lifetime: HelperLifetime

    init(lifetime: HelperLifetime) {
        self.lifetime = lifetime
    }

    /// The account behind the connection the message came on, and its home folder. Nil when that account is not
    /// an administrator or its home folder cannot be found. It is asked for each message, so an account that stops
    /// being an administrator is refused from its next request. It says whose connection it is, not which process
    /// sent the message: `xpc_connection_create(3)` warns that a client can hand its connection to another process.
    private static func caller() -> HelperRequest.Caller? {
        guard
            let user = NSXPCConnection.current()?.effectiveUserIdentifier,
            UserAuthorization.isAdministrator(user),
            let home = UserAuthorization.homeDirectory(of: user)
        else { return nil }
        return HelperRequest.Caller(user: user, homeDirectory: home)
    }

    private func tracked(_ finish: @escaping @Sendable (String?) -> Void) -> @Sendable (String?) -> Void {
        { [lifetime] answer in
            finish(answer)
            lifetime.requestFinished()
        }
    }

    func protocolVersion(withReply reply: @escaping @Sendable (Int) -> Void) {
        reply(HelperIdentity.protocolVersion)
    }

    func moveItemsToTrash(version: Int, atPaths paths: [String], withReply finish: @escaping @Sendable ([String: String], [String: String]) -> Void) {
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
            caller = try HelperRequest.admit(version: version, items: paths.count, caller: Self.caller).get()
        } catch {
            return refuse(error.rawValue)
        }

        let policy = PrivilegedPathPolicy(homeDirectory: caller.homeDirectory)
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
        guard let ledger = HelperLedger(), let result = TrashMover.moveRecorded(items, into: trash, ledger: ledger, movedBy: caller.user) else {
            return refuse(HelperRefusal.cannotKeepRecord.rawValue)
        }
        reply(result.moved, failed.merging(result.failed) { refused, _ in refused })
    }

    func restoreItem(version: Int, fromTrashPath trashPath: String, toPath destination: String, withReply finish: @escaping @Sendable (String?) -> Void) {
        lifetime.requestStarted()
        let reply = tracked(finish)
        let caller: HelperRequest.Caller
        do {
            let paths = [trashPath, destination]
            caller = try HelperRequest.admit(version: version, paths: paths, caller: Self.caller).get()
        } catch {
            return reply(error.rawValue)
        }

        let policy = PrivilegedPathPolicy(homeDirectory: caller.homeDirectory)
        guard
            let trash = policy.openTrash(ownedBy: caller.user),
            let trashed = policy.openInTrash(trashPath, trash: trash)
        else { return reply(HelperRefusal.notInTrash.rawValue) }

        switch policy.openDestination(destination, for: trashed) {
        case .failure(let rejection):
            reply(rejection.explanation)
        case .success(let target):
            // The request comes from History's record, which any process the user runs can rewrite. So the item
            // goes back only if the ledger shows the helper moved it, and only to the path recorded there.
            guard
                let ledger = HelperLedger(),
                case .success(let origin) = Result(catching: { try ledger.origin(of: trashed, movedBy: caller.user) })
            else {
                return reply(HelperRefusal.cannotReadRecord.rawValue)
            }
            guard origin == target.path else { return reply(HelperRefusal.notMovedByHelper.rawValue) }
            switch TrashMover.rename(trashed, to: target.name, in: target.parent) {
            case .success:
                ledger.forget([trashed])
                reply(nil)
            case .failure(let error):
                reply(error.localizedDescription)
            }
        }
    }

    func moveLedgerToTrash(version: Int, withReply finish: @escaping @Sendable (String?) -> Void) {
        lifetime.requestStarted()
        let reply = tracked(finish)
        let caller: HelperRequest.Caller
        do {
            caller = try HelperRequest.admit(version: version, caller: Self.caller).get()
        } catch {
            return reply(error.rawValue)
        }
        guard let trash = PrivilegedPathPolicy(homeDirectory: caller.homeDirectory).openTrash(ownedBy: caller.user) else {
            return reply(HelperRefusal.noTrash.rawValue)
        }
        switch HelperLedger.moveFolder(into: trash) {
        case .success: reply(nil)
        case .failure(let error): reply(error.localizedDescription)
        }
    }

    func runDaemonCommand(version: Int, command: String, label: String, withReply finish: @escaping @Sendable (String?) -> Void) {
        lifetime.requestStarted()
        let reply = tracked(finish)
        if case .failure(let refusal) = HelperRequest.admit(version: version, caller: Self.caller) {
            return reply(refusal.rawValue)
        }
        guard let command = DaemonCommand(rawValue: command), PrivilegedPathPolicy.allowsDaemon(label) else {
            return reply(HelperRefusal.invalidRequest.rawValue)
        }
        let target = "system/\(label)"
        // The job's file is found by the `Label` inside it, since a file's name does not always match its label.
        let plist = command == .bootstrap ? SystemDaemons.file(declaring: label) : nil
        if command == .bootstrap, plist == nil {
            reply(HelperRefusal.missingConfiguration.rawValue)
            return
        }
        let arguments = switch command {
        case .bootstrap: ["bootstrap", "system", plist ?? ""]
        case .bootout: ["bootout", target]
        case .kickstart: ["kickstart", target]
        case .enable: ["enable", target]
        case .disable: ["disable", target]
        }

        // 30 seconds: `bootout` waits for the job to exit, and the helper must never wait on `launchctl` forever.
        Task {
            switch await Subprocess.run("/bin/launchctl", arguments, timeout: 30) {
            case .success(let output): reply(output.status == 0 ? nil : output.text + output.errorText)
            case .failure(let failure): reply(failure.explanation)
            }
        }
    }
}
