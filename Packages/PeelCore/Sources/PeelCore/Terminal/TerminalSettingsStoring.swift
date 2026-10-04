public enum TerminalProfileRole: String, CaseIterable, Sendable {
    case newWindows = "Default Window Settings"
    case startup = "Startup Window Settings"
}

public protocol TerminalSettingsStoring {
    var isTerminalOpen: Bool { get }
    var isManaged: Bool { get }
    func profiles() -> [String: [String: Any]]
    func setProfiles(_ profiles: [String: [String: Any]]) -> Bool
    func profileName(for role: TerminalProfileRole) -> String?
    func setProfileName(_ name: String?, for role: TerminalProfileRole) -> Bool
}
