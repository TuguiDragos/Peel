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
}
