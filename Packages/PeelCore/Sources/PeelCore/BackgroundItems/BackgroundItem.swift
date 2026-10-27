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
    public internal(set) var source: Source
    public let plistURL: URL?
    public let program: String?
    /// Whether launchd starts the job as it loads it, and again after it exits; nil when nothing Peel can read says.
    public let runsAtLoad: Bool?
    public let keepsAlive: Bool?
    public let ownerBundleIdentifier: String?
    public let ownerName: String?
    /// Where the app that owns the job is, or nil when no app does or it is gone.
    public let ownerURL: URL?
    /// True when no installed app claims the job and its program is gone from disk, or it names none of its own.
    /// The full rule is `BackgroundItemOwnership.isOrphan(label:program:owner:)`.
    public let isOrphan: Bool
    public internal(set) var state: State
    public let isDisabled: Bool
    /// False when only a name points to the owner (`BackgroundItemOwnership.Owner.isConfirmed`).
    public var isOwnerConfirmed = true
    /// True for a file launchd can't load: not a property list, or one without a `Label`.
    public var isUnreadable = false
    /// True for a file macOS lets only its owner read, as launchd does as root: what Peel knows of its job comes from
    /// launchd, and until launchd says which job it loaded from the file, the row is named by the file.
    public var isClosedToPeel = false
    /// True for a row named by its file, since Peel couldn't read the label inside: nothing but moving it is offered.
    public var isNamedByItsFile = false
    /// What in the job's command is worth a second look, if anything.
    public var unusualCommand: UnusualCommand?
    /// True for an agent that loads in the Background session, which launchd keeps in the user domain rather than
    /// the GUI one: started, stopped and asked about there.
    public var loadsInTheBackgroundSession = false
    /// True while an app's job runs from inside a Trash: its app was moved there, and macOS starts it from there at
    /// each login until the Trash is emptied.
    public var runsFromTheTrash = false
    /// True for a job launchd runs for a system extension, whose program sits in `/Library/SystemExtensions`: macOS
    /// runs it, and only System Settings changes it.
    public var isSystemExtension = false
    /// True for a job ServiceManagement manages: the person turns it on and off in System Settings > General > Login
    /// Items & Extensions, so Peel never disables it.
    public var isManagedByServiceManagement = false
    /// False for an app's job that, once disabled, would leave the list at the next restart: launchd keeps only its
    /// label, which neither starts with its app's identifier nor is declared in its app's bundle.
    public var staysListedWhenDisabled = true
    /// True for a job launchd runs from a file no longer on disk, removed while it was loaded: launchd forgets it at
    /// the next logout or restart, and nothing loads it again.
    public var isFileGone = false
    /// True for a job of an app the person excluded in Settings, which Peel lists and never acts on.
    public var isExcluded = false
    /// True for a job its app gave launchd itself, as an update's installer is given, rather than registered with
    /// ServiceManagement: System Settings doesn't list it, and launchd forgets it at the next logout or restart.
    public var isSubmittedByItsApp = false
    public var anotherFileIsLoaded = false

    public var isOwnerInstalled: Bool { ownerURL != nil }

    /// True for a job an app submitted that is still loaded after the app went, its program gone or not named by
    /// launchctl: the app that would unregister it is gone, so only taking it out of launchd removes it.
    public var isLeftByAGoneApp: Bool { source == .app && !isOwnerInstalled && (isOrphan || program == nil) }

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

    /// True when Peel may start, stop, enable and disable the job: never under a label of macOS, for a system
    /// extension or for an excluded app, an agent only under a label `launchctl` reads whole, and a daemon only under a
    /// label the helper takes, which also leaves out the helper itself.
    public var canBeControlled: Bool {
        !usesALabelOfMacOS && !isSystemExtension && !isExcluded
            && (requiresPrivileges ? PrivilegedPathPolicy.allowsDaemon(label) : isReadWholeByLaunchctl)
    }

    /// `launchctl` reads a service's name up to the next slash, so a label with one reaches another job.
    private var isReadWholeByLaunchctl: Bool {
        !label.utf8.contains { $0 == 0x2F || $0 < 0x20 || $0 == 0x7F }
    }

    /// True for a name Peel never passes to `launchctl`: one the helper refuses for a daemon, or one `launchctl` would
    /// misread for an agent. Apple's names have notes of their own.
    public var hasAnUnusableLabel: Bool {
        !label.hasPrefix("com.apple.")
            && (requiresPrivileges ? !PrivilegedPathPolicy.isValidLabel(label) : !isReadWholeByLaunchctl)
    }

    /// True for a job Peel can only take out of launchd, which nothing loads again by itself: one loaded from a file
    /// elsewhere, still there or gone. Disabled, it would leave the list with nothing to enable it from.
    public var canOnlyBeStopped: Bool { canBeControlled && source == .otherFile }

    /// True when Peel may disable the job: not one ServiceManagement manages, and one whose row Enable stays on.
    public var mayBeDisabled: Bool { canBeControlled && !isManagedByServiceManagement && staysListedWhenDisabled }

    public var removalRequiresPrivileges: Bool { source == .systemLibrary }

    /// True for a job Peel sees only while it is loaded, so once stopped it would leave the list and could not be
    /// started again from here.
    public var isSeenOnlyWhileLoaded: Bool { source == .app || source == .otherFile }

    public var canMoveToTrash: Bool {
        !isSeenOnlyWhileLoaded && plistURL != nil && !usesALabelOfMacOS && !isExcluded
    }
}
