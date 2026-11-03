public enum TerminalProfileRole: String, CaseIterable, Sendable {
    case newWindows = "Default Window Settings"
    case startup = "Startup Window Settings"
}

public protocol TerminalSettingsStoring {
    var isTerminalOpen: Bool { get }
    var isManaged: Bool { get }
    /// Every profile by name, empty when none is kept, and nil when what is kept cannot be read as profiles.
    func profiles() -> [String: [String: Any]]?
    func setProfiles(_ profiles: [String: [String: Any]]) -> Bool
    func profileName(for role: TerminalProfileRole) -> String?
    func setProfileName(_ name: String?, for role: TerminalProfileRole) -> Bool
    /// The command Terminal opens new windows with, when Shells open with names one.
    func shell() -> String?
    /// Whether Terminal has set itself up, which it does once, the first time it opens: it then names its initial
    /// profile for new windows and at startup itself.
    var hasSetItselfUp: Bool { get }
    /// The profile Terminal's own initial settings name, which it gives new windows and startup as it sets itself up.
    var initialProfileName: String? { get }
}
