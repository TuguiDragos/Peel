public enum SSHSetting: CaseIterable, Sendable {
    case keychain
    case keepAlive
    case reuseConnections

    public var lines: [String] {
        switch self {
        case .keychain: ["UseKeychain yes", "AddKeysToAgent yes"]
        case .keepAlive: ["ServerAliveInterval 60"]
        case .reuseConnections: ["ControlMaster auto", "ControlPath ~/.ssh/cm-%C", "ControlPersist 10m"]
        }
    }

    /// The options only Apple's ssh knows. Another ssh, such as Homebrew's, stops at an option it doesn't know
    /// unless an `IgnoreUnknown` before it names the option (`man ssh_config`).
    var onlyApplesSSHKnows: [String] {
        switch self {
        case .keychain: ["UseKeychain"]
        case .keepAlive, .reuseConnections: []
        }
    }
}
