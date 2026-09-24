public import Foundation
import PeelPrivileged

public struct BackgroundItem: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case agent
        case daemon
    }

    public enum Source: Sendable, Hashable {
        case userLibrary
        case systemLibrary
        case app
    }

    public enum State: Sendable, Hashable {
        case running(pid: Int32)
        case loaded
        case notLoaded
    }

    public let label: String
    public let kind: Kind
    public let source: Source
    public let plistURL: URL?
    public let program: String?
    public let runsAtLoad: Bool
    public let keepsAlive: Bool
    public let ownerBundleIdentifier: String?
    public let ownerName: String?
    public let isOwnerInstalled: Bool
    /// True when no installed app claims the job and its program is gone from disk, or it names none of its own.
    /// The full rule is `BackgroundItemOwnership.isOrphan(label:program:owner:)`.
    public let isOrphan: Bool
    public let state: State
    public let isDisabled: Bool

    /// Includes the file's path, because two files can declare one label (a per-user copy beside the
    /// system-wide one), and each file needs a row of its own.
    public var id: String { "\(kind.rawValue)/\(label)/\(plistURL?.path(percentEncoded: false) ?? "")" }

    /// Starting, stopping, enabling, and disabling a daemon goes through the privileged helper.
    public var requiresPrivileges: Bool { kind == .daemon }

    /// True for Peel's own privileged helper. The helper refuses to act on its own label, so this job is
    /// installed and uninstalled only from Peel's Settings.
    public var isPeelsHelper: Bool { kind == .daemon && label == HelperIdentity.helperIdentifier }

    /// True when the label starts with `com.apple.`. The scan leaves out the labels of macOS's own daemons, so a
    /// listed job with an Apple label did not come with macOS. Peel shows it and never acts on it.
    public var declaresAnAppleLabel: Bool { label.hasPrefix("com.apple.") }

    public var removalRequiresPrivileges: Bool { source == .systemLibrary }

    public var canMoveToTrash: Bool { source != .app && plistURL != nil && !declaresAnAppleLabel }
}
