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
        HelperRequest.caller(user: account, approval: approval)
    }

    private static var account: uid_t? { NSXPCConnection.current()?.effectiveUserIdentifier }

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
        let result = HelperOperations.moveToTrash(
            account: Self.account, version: version, approval: approval, paths: paths,
            caller: Self.caller(approval:),
            policy: { PrivilegedPathPolicy(homeDirectory: $0.homeDirectory, ownTool: Self.ownTool) }
        )
        finish(result.moved, result.failed)
        lifetime.requestFinished()
    }

    func restoreItem(
        version: Int,
        approval: Data,
        fromTrashPath trashPath: String,
        toPath destination: String,
        withReply finish: @escaping @Sendable (String?) -> Void
    ) {
        lifetime.requestStarted()
        tracked(finish)(HelperOperations.putBack(
            account: Self.account, version: version, approval: approval, from: trashPath, to: destination,
            caller: Self.caller(approval:),
            policy: { PrivilegedPathPolicy(homeDirectory: $0.homeDirectory) }
        ))
    }

    func moveLedgerToTrash(version: Int, withReply finish: @escaping @Sendable (String?) -> Void) {
        lifetime.requestStarted()
        tracked(finish)(HelperOperations.moveLedgerToTrash(
            account: Self.account, version: version, caller: Self.caller(approval:),
            policy: { PrivilegedPathPolicy(homeDirectory: $0.homeDirectory) }
        ))
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
        let account = Self.account
        let arguments: [String]
        switch HelperOperations.daemonArguments(
            account: account, version: version, approval: approval, command: command, label: label,
            caller: Self.caller(approval:)
        ) {
        case .success(let given): arguments = given
        case .failure(let refused): return reply(refused.rawValue)
        }
        Task { reply(await HelperOperations.launchctl(arguments, for: account)) }
    }
}
