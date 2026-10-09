import Foundation

public enum HelperIdentity {
    public static let appIdentifier = "com.tuguidragos.Peel"
    public static let helperIdentifier = "com.tuguidragos.Peel.Helper"
    public static let machServiceName = "com.tuguidragos.Peel.Helper"
    public static let launchdPlistName = "com.tuguidragos.Peel.Helper.plist"
    /// Raise it whenever the helper changes, so Peel never works with a helper of another version. The helper
    /// refuses requests that carry any other version.
    public static let protocolVersion = 15
}

/// The complete set of privileged operations. The helper validates every argument itself.
///
/// Each call carries the protocol version of the app making it. Any administrator can write to
/// `/Applications`, so an older copy of Peel, signed by the same team but with older checks, can be put
/// there. The helper answers only the version it was installed with, and only a build no older than its own, so
/// that copy gets nothing from it.
@objc public protocol PeelHelperProtocol {
    func protocolVersion(withReply reply: @escaping @Sendable (Int) -> Void)

    /// Replies with two dictionaries keyed by original path: where each moved item now is in the user's
    /// Trash, and why each other item failed.
    func moveItemsToTrash(
        version: Int,
        atPaths paths: [String],
        withReply reply: @escaping @Sendable ([String: String], [String: String]) -> Void
    )

    /// Runs `launchctl` with `command` for the system daemon `label`. Replies with nil on success, or a
    /// failure description.
    func runDaemonCommand(
        version: Int,
        command: String,
        label: String,
        withReply reply: @escaping @Sendable (String?) -> Void
    )

    /// Moves an item back from the user's Trash, when the helper's own ledger says it moved that item from
    /// exactly there. Replies with nil on success, or a failure description.
    func restoreItem(
        version: Int,
        fromTrashPath trashPath: String,
        toPath destination: String,
        withReply reply: @escaping @Sendable (String?) -> Void
    )

    /// Moves the helper's own ledger to the user's Trash, for Remove Peel just before it unregisters the helper.
    /// Replies with nil once it is there or when there is none, or a failure description.
    func moveLedgerToTrash(version: Int, withReply reply: @escaping @Sendable (String?) -> Void)
}

public enum DaemonCommand: String, Sendable {
    case bootstrap
    case bootout
    case kickstart
    case enable
    case disable
}
