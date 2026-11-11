import Darwin
public import Foundation

/// What the helper does for each request, apart from XPC: the account behind it and the tools it works with come in,
/// so the rules it keeps can be tested. `account` is the account behind the connection, for a request refused before
/// it is known whose it is.
public enum HelperOperations {
    /// The account behind a request, given the administrator's approval the request carries.
    public typealias Caller = (_ approval: Data) -> Result<HelperRequest.Caller, HelperRefusal>

    /// Moves `paths` to the caller's Trash, each recorded before anything moves: where each moved item went, and why
    /// each other one didn't.
    public static func moveToTrash(
        account: uid_t?,
        version: Int,
        approval: Data,
        paths: [String],
        caller: Caller,
        policy: (HelperRequest.Caller) -> PrivilegedPathPolicy,
        ledger: () -> HelperLedger? = { HelperLedger() }
    ) -> (moved: [String: String], failed: [String: String]) {
        let request = "Move to the Trash"
        func refusal(_ reason: HelperRefusal, for user: uid_t?) -> (moved: [String: String], failed: [String: String]) {
            HelperLog.note(request, for: user, "refused. \(reason.rawValue)")
            let failed = paths.prefix(HelperRequest.maximumItems).map { ($0, reason.rawValue) }
            return ([:], Dictionary(failed) { first, _ in first })
        }
        let admitted: HelperRequest.Caller
        switch HelperRequest.admit(version: version, items: paths.count, caller: { caller(approval) }) {
        case .success(let account): admitted = account
        case .failure(let refused): return refusal(refused, for: account)
        }
        let policy = policy(admitted)
        guard let trash = policy.openTrash(ownedBy: admitted.user) else { return refusal(.noTrash, for: admitted.user) }
        let deadline = ContinuousClock.now + .seconds(HelperRequest.timeToMove)

        var failed: [String: String] = [:]
        var items: [(path: String, item: OpenItem)] = []
        for path in paths {
            guard !HelperRequest.isTooLong(path) else {
                failed[path] = HelperRefusal.pathTooLong.rawValue
                continue
            }
            guard ContinuousClock.now < deadline else {
                failed[path] = HelperRefusal.ranOutOfTime.rawValue
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
            let ledger = ledger(),
            let result = TrashMover.moveRecorded(
                items, into: trash, ledger: ledger, movedBy: admitted.user, until: deadline
            )
        else {
            return refusal(.cannotKeepRecord, for: admitted.user)
        }
        let left = failed.merging(result.failed) { refused, _ in refused }
        HelperLog.note(request, for: admitted.user, "\(result.moved.count) moved, \(left.count) refused")
        for (path, reason) in left.sorted(by: { $0.key < $1.key }) {
            HelperLog.left(path, by: request, for: admitted.user, because: reason)
        }
        return (result.moved, left)
    }

    /// Nil once the item at `trashPath` is back at `destination`, otherwise why it isn't.
    public static func putBack(
        account: uid_t?,
        version: Int,
        approval: Data,
        from trashPath: String,
        to destination: String,
        caller: Caller,
        policy: (HelperRequest.Caller) -> PrivilegedPathPolicy,
        ledger: () -> HelperLedger? = { HelperLedger() }
    ) -> String? {
        switch HelperRequest.admit(version: version, paths: [trashPath, destination], caller: { caller(approval) }) {
        case .success(let admitted):
            let refusal = HelperPutBack.run(
                trashPath, to: destination, for: admitted.user, policy: policy(admitted), ledger: ledger
            )
            if let refusal {
                HelperLog.left(trashPath, by: "Put Back", for: admitted.user, because: refusal)
            } else {
                HelperLog.note("Put Back", for: admitted.user, "done")
            }
            return refusal
        case .failure(let refused):
            HelperLog.note("Put Back", for: account, "refused. \(refused.rawValue)")
            return refused.rawValue
        }
    }

    /// Nil once the helper's ledger is in the caller's Trash, otherwise why it isn't. No approval counts here: only an
    /// administrator's own account takes the record of what the helper moved.
    public static func moveLedgerToTrash(
        account: uid_t?,
        version: Int,
        caller: Caller,
        policy: (HelperRequest.Caller) -> PrivilegedPathPolicy,
        moveFolder: (DirectoryHandle, uid_t) -> Result<String?, POSIXError> = {
            HelperLedger.moveFolder(into: $0, givingTo: $1)
        }
    ) -> String? {
        let request = "Its ledger to the Trash"
        let admitted: HelperRequest.Caller
        switch HelperRequest.admit(version: version, caller: { caller(Data()) }) {
        case .success(let account): admitted = account
        case .failure(let refused):
            HelperLog.note(request, for: account, "refused. \(refused.rawValue)")
            return refused.rawValue
        }
        guard let trash = policy(admitted).openTrash(ownedBy: admitted.user) else {
            HelperLog.note(request, for: admitted.user, "refused. \(HelperRefusal.noTrash.rawValue)")
            return HelperRefusal.noTrash.rawValue
        }
        switch moveFolder(trash, admitted.user) {
        case .success:
            HelperLog.note(request, for: admitted.user, "done")
            return nil
        case .failure(let error):
            HelperLog.note(request, for: admitted.user, "refused. \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    /// What `launchctl` is run with for `command` on the daemon `label`, or why it isn't run.
    public static func daemonArguments(
        account: uid_t?,
        version: Int,
        approval: Data,
        command: String,
        label: String,
        caller: Caller,
        files: (String) -> [String] = { SystemDaemons.files(declaring: $0) }
    ) -> Result<[String], HelperRefusal> {
        let request = "launchctl \(command) \(label)"
        func refusal(_ reason: HelperRefusal) -> Result<[String], HelperRefusal> {
            HelperLog.note(request, for: account, "refused. \(reason.rawValue)")
            return .failure(reason)
        }
        if case .failure(let refused) = HelperRequest.admit(version: version, caller: { caller(approval) }) {
            return refusal(refused)
        }
        guard let command = DaemonCommand(rawValue: command), PrivilegedPathPolicy.allowsDaemon(label) else {
            return refusal(.invalidRequest)
        }
        let target = "system/\(label)"
        // The job's file is found by the `Label` inside it, since a file's name does not always match its label.
        let plists = command == .bootstrap ? files(label) : []
        if command == .bootstrap, plists.count != 1 {
            return refusal(plists.isEmpty ? .missingConfiguration : .declaredTwice)
        }
        let arguments = switch command {
        case .bootstrap: ["bootstrap", "system", plists[0]]
        case .bootout: ["bootout", target]
        case .kickstart: ["kickstart", target]
        case .restart: ["kickstart", "-k", target]
        case .enable: ["enable", target]
        case .disable: ["disable", target]
        }
        return .success(arguments)
    }

    /// Runs `launchctl` with `arguments` for `account`: nil once it ended well, otherwise what it said. 30 seconds,
    /// since `kickstart -k` waits for the job to exit and start again, and the helper never waits forever.
    public static func launchctl(
        _ arguments: [String],
        for account: uid_t?,
        run: @Sendable ([String]) async -> Result<Subprocess.Output, Subprocess.Failure> = {
            await Subprocess.run("/bin/launchctl", $0, timeout: 30)
        }
    ) async -> String? {
        let request = "launchctl \(arguments.joined(separator: " "))"
        switch await run(arguments) {
        case .success(let output):
            HelperLog.note(request, for: account, "exit status \(output.status)")
            return output.status == 0 ? nil : output.text + output.errorText
        case .failure(let failure):
            HelperLog.note(request, for: account, failure.explanation)
            return failure.explanation
        }
    }

    /// The interface the helper exports, with every collection in `moveItemsToTrash` limited to strings.
    /// `NSXPCConnection.h` makes this optional for property list types, and here it keeps a client from sending
    /// anything else.
    public static func exportedInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: (any PeelHelperProtocol).self)
        let trash = #selector((any PeelHelperProtocol).moveItemsToTrash(version:approval:atPaths:withReply:))
        interface.setClasses(classes(NSArray.self, NSString.self), for: trash, argumentIndex: 2, ofReply: false)
        for index in 0...1 {
            interface.setClasses(
                classes(NSDictionary.self, NSString.self), for: trash, argumentIndex: index, ofReply: true
            )
        }
        return interface
    }

    private static func classes(_ allowed: AnyClass...) -> Set<AnyHashable> {
        NSSet(array: allowed) as? Set<AnyHashable> ?? []
    }
}
