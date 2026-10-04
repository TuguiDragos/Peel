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

    public enum Documentation: Sendable, Hashable {
        case apple(URL)
        case undocumented
    }
}

/// A tweak's current state, as read from the preferences.
public struct TweakState: Sendable, Hashable {
    /// True when the key holds the value this tweak writes. For a folder tweak, true when the key holds a path.
    public let isOn: Bool
    /// True when the value is managed, for example by a configuration profile, so Peel can't change it.
    public let isManaged: Bool
    /// For a folder tweak, the path it holds.
    public let path: String?

    public static let unset = TweakState(isOn: false, isManaged: false, path: nil)
}
