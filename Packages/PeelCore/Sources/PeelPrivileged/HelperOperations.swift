import Darwin
public import Foundation

/// What the helper does for each request, apart from XPC: the account behind it and the tools it works with come in,
/// so the rules it keeps can be tested.
public enum HelperOperations {
    /// The account behind a request, given the administrator's approval the request carries.
    public typealias Caller = (_ approval: Data) -> Result<HelperRequest.Caller, HelperRefusal>

    /// Moves `paths` to the caller's Trash, each recorded before anything moves: where each moved item went, and why
    /// each other one didn't.
    public static func moveToTrash(
        version: Int,
        approval: Data,
        paths: [String],
        caller: Caller,
        policy: (HelperRequest.Caller) -> PrivilegedPathPolicy,
        ledger: () -> HelperLedger? = { HelperLedger() }
    ) -> (moved: [String: String], failed: [String: String]) {
        func refusal(_ reason: HelperRefusal) -> (moved: [String: String], failed: [String: String]) {
            let failed = paths.prefix(HelperRequest.maximumItems).map { ($0, reason.rawValue) }
            return ([:], Dictionary(failed) { first, _ in first })
        }
        let admitted: HelperRequest.Caller
        switch HelperRequest.admit(version: version, items: paths.count, caller: { caller(approval) }) {
        case .success(let account): admitted = account
        case .failure(let refused): return refusal(refused)
        }
        let policy = policy(admitted)
        guard let trash = policy.openTrash(ownedBy: admitted.user) else { return refusal(.noTrash) }

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
            let ledger = ledger(),
            let result = TrashMover.moveRecorded(items, into: trash, ledger: ledger, movedBy: admitted.user)
        else {
            return refusal(.cannotKeepRecord)
        }
        return (result.moved, failed.merging(result.failed) { refused, _ in refused })
    }

    /// Nil once the item at `trashPath` is back at `destination`, otherwise why it isn't.
    public static func putBack(
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
            HelperPutBack.run(trashPath, to: destination, for: admitted.user, policy: policy(admitted), ledger: ledger)
        case .failure(let refused):
            refused.rawValue
        }
    }

    /// Nil once the helper's ledger is in the caller's Trash, otherwise why it isn't. No approval counts here: only an
    /// administrator's own account takes the record of what the helper moved.
    public static func moveLedgerToTrash(
        version: Int,
        caller: Caller,
        policy: (HelperRequest.Caller) -> PrivilegedPathPolicy,
        moveFolder: (DirectoryHandle, uid_t) -> Result<String?, POSIXError> = {
            HelperLedger.moveFolder(into: $0, givingTo: $1)
        }
    ) -> String? {
        let admitted: HelperRequest.Caller
        switch HelperRequest.admit(version: version, caller: { caller(Data()) }) {
        case .success(let account): admitted = account
        case .failure(let refused): return refused.rawValue
        }
        guard let trash = policy(admitted).openTrash(ownedBy: admitted.user) else {
            return HelperRefusal.noTrash.rawValue
        }
        switch moveFolder(trash, admitted.user) {
        case .success: return nil
        case .failure(let error): return error.localizedDescription
        }
    }

    /// What `launchctl` is run with for `command` on the daemon `label`, or why it isn't run.
    public static func daemonArguments(
        version: Int,
        approval: Data,
        command: String,
        label: String,
        caller: Caller,
        files: (String) -> [String] = { SystemDaemons.files(declaring: $0) }
    ) -> Result<[String], HelperRefusal> {
        if case .failure(let refused) = HelperRequest.admit(version: version, caller: { caller(approval) }) {
            return .failure(refused)
        }
        guard let command = DaemonCommand(rawValue: command), PrivilegedPathPolicy.allowsDaemon(label) else {
            return .failure(.invalidRequest)
        }
        let target = "system/\(label)"
        // The job's file is found by the `Label` inside it, since a file's name does not always match its label.
        let plists = command == .bootstrap ? files(label) : []
        if command == .bootstrap, plists.count != 1 {
            return .failure(plists.isEmpty ? .missingConfiguration : .declaredTwice)
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
