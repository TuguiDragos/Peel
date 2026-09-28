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
        /// Registered or submitted by an app, and known only while it is loaded.
        case app
        /// Loaded from a file outside the folders launchd reads by itself, and known only while it is loaded: launchd
        /// forgets it at the next logout or restart.
        case otherFile
    }

    public enum State: Sendable, Hashable {
        case running(pid: Int32)
        case loaded
        case notLoaded
        case unknown
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
    /// False when only a name points to the owner (`BackgroundItemOwnership.Owner.isConfirmed`).
    public var isOwnerConfirmed = true
    /// True for a file launchd can't load: not a property list, or one without a `Label`. It is named by its file,
    /// and nothing but moving it is offered.
    public var isUnreadable = false
    /// What in the job's command is worth a second look, if anything.
    public var unusualCommand: UnusualCommand?

    /// Includes the file's path, because two files can declare one label (a per-user copy beside the
    /// system-wide one), and each file needs a row of its own.
    public var id: String { "\(kind.rawValue)/\(label)/\(plistURL?.path(percentEncoded: false) ?? "")" }

    /// Starting, stopping, enabling, and disabling a daemon goes through the privileged helper.
    public var requiresPrivileges: Bool { kind == .daemon }

    /// True for Peel's own privileged helper. The helper refuses to act on its own label, so this job is
    /// installed and uninstalled only from Peel's Settings.
    public var isPeelsHelper: Bool { kind == .daemon && label == HelperIdentity.helperIdentifier }

    /// True when the label starts with `com.apple.`.
    public var declaresAnAppleLabel: Bool { label.hasPrefix("com.apple.") }

    /// True when the label is Apple's, or one macOS gives a job of its own. macOS keeps its jobs under
    /// `/System/Library` and `/Library/Apple/System/Library`, never where the scan reads, so a listed job with
    /// such a label did not come with macOS. Peel shows it and never acts on it.
    public var usesALabelOfMacOS: Bool {
        declaresAnAppleLabel || SystemDaemons.shipped.contains(label) || SystemAgents.shipped.contains(label)
    }

    public var removalRequiresPrivileges: Bool { source == .systemLibrary }

    /// True for a job Peel sees only while it is loaded, so once stopped it would leave the list and could not be
    /// started again from here.
    public var isSeenOnlyWhileLoaded: Bool { source == .app || source == .otherFile }

    public var canMoveToTrash: Bool { !isSeenOnlyWhileLoaded && plistURL != nil && !usesALabelOfMacOS }
}
