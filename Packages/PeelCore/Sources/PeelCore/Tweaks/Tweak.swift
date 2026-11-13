public import Foundation

/// A macOS setting kept in one preference key. Each tweak names the domain and key it changes. Turning it off
/// puts back what the key held before Peel changed it, or removes the key so that macOS uses its default.
public struct Tweak: Sendable, Hashable, Identifiable {
    public enum Value: Sendable, Hashable {
        case boolean(Bool)
        case number(Double)
        case text(String)
    }

    public enum Kind: Sendable, Hashable {
        /// A switch. Turning it on writes this value.
        case aSwitch(Value)
        case aSwitchForThisAppAlone(Value)
        /// A folder the user picks, written as an absolute path.
        case folder
        case name
    }

    public enum Restart: String, Sendable, Hashable {
        case none
        case dock
        case finder
        case controlCenter
        case windowManager
        /// Apps read the setting when they start, so apps already open keep the old value until they are reopened.
        case relaunchApps
        case logOut
        case terminalQuits
    }

    public enum Group: String, Sendable, Hashable, CaseIterable {
        case dock
        case screenshots
        case finder
        case typing
        case windows
        case privacy
        case terminal
    }

    public let id: String
    public let domain: String
    public let key: String
    public let kind: Kind
    public let restart: Restart
    public let group: Group
    /// True when macOS has its own control for this key (in System Settings, Finder Settings, or the Screenshot
    /// toolbar), so the user can change it back outside Peel.
    public let hasASystemControl: Bool
    /// Where Apple documents the key. An undocumented key is known from use alone, so a release of macOS can rename
    /// or ignore it without a word, and its switch would stay on while nothing changes.
    public let documentation: Documentation

    /// The switch this one works under, when its key has an effect only while that switch is on.
    public var onlyWhile: Tweak.ID? = nil
    /// The key macOS 27 moved this setting to, once it has written the move's mark in the domain.
    public var moved: Moved? = nil
    /// For the screenshot folder, the key of the Screenshot app's Save to: the folder is unused while it saves
    /// elsewhere.
    public var saveTo: Moved? = nil

    public enum Documentation: Sendable, Hashable {
        case apple(URL)
        case undocumented
    }

    /// A key macOS 27 reads in place of another: `screencaptureui` writes `mark` when it moves the screenshot keys,
    /// and until then reads the old key, once, to copy it.
    public struct Moved: Sendable, Hashable {
        public let old: String
        public let new: String
        public let mark: String

        /// The key macOS reads now. macOS 26 knows only the old one, whatever the domain holds.
        func key(onMacOS27: Bool, markIsSet: Bool) -> String {
            onMacOS27 && markIsSet ? new : old
        }
    }
}

/// Where the Screenshot app saves a screenshot instead of a folder (Options > Save to).
public enum ScreenshotDestination: Sendable, Hashable {
    case clipboard
    case preview
    case mail
    case messages
    case unknown

    /// What `value` names, or nil for a folder: macOS writes `file` for one, and a missing value means one too.
    init?(_ value: String?) {
        switch value {
        case nil, "file": return nil
        case "clipboard": self = .clipboard
        case "preview": self = .preview
        case "mail": self = .mail
        case "messages": self = .messages
        default: self = .unknown
        }
    }
}

/// A tweak's current state, as read from the preferences.
public struct TweakState: Sendable, Hashable {
    /// Where a value comes from that Peel can't change from the layer it writes, the person's own for any host:
    /// a layer macOS reads before Peel's, or one it falls back to while Peel's holds nothing.
    public enum Elsewhere: Sendable, Hashable {
        /// Set for this Mac alone, which wins over what Peel writes.
        case thisMac
        /// Set for every account of this Mac, by an administrator, while nothing of the person's own stands over it.
        case everyAccount
        /// Set for every app at once, in the global domain, while the tweak belongs to one app's domain.
        case everyApp
    }

    /// True when the key holds the value this tweak writes. For a folder or a name tweak, true when the key holds
    /// a path or a name.
    public let isOn: Bool
    /// True when the value is managed, for example by a configuration profile, so Peel can't change it.
    public let isManaged: Bool
    /// For a folder tweak, the path it holds; for a name tweak, the name.
    public let text: String?
    /// Where the value in effect comes from when turning the tweak off here would change nothing.
    public let heldElsewhere: Elsewhere?
    /// The key read, when macOS moved the setting to it (`Tweak.moved`).
    public let movedKey: String?
    /// Where screenshots go while the Screenshot app saves them anywhere but a folder (`Tweak.saveTo`).
    public let savedElsewhere: ScreenshotDestination?

    public init(
        isOn: Bool, isManaged: Bool, text: String?, heldElsewhere: Elsewhere? = nil, movedKey: String? = nil,
        savedElsewhere: ScreenshotDestination? = nil
    ) {
        self.isOn = isOn
        self.isManaged = isManaged
        self.text = text
        self.heldElsewhere = heldElsewhere
        self.movedKey = movedKey
        self.savedElsewhere = savedElsewhere
    }

    public static let unset = TweakState(isOn: false, isManaged: false, text: nil)
}
