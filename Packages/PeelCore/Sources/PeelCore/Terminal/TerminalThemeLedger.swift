public struct TerminalThemeLedger {
    public enum Outcome: Sendable, Equatable {
        case changed
        case unchanged
        case terminalIsOpen
        case managed
        case refused
    }

    public private(set) var before: [TerminalProfileRole: String]?
    public private(set) var chosen: String?
    public private(set) var written: [String: String]

    public init(stored: [String: Any] = [:]) {
        before = (stored["before"] as? [String: String]).map { names in
            Dictionary(
                uniqueKeysWithValues: names.compactMap { role, name in
                    TerminalProfileRole(rawValue: role).map { ($0, name) }
                }
            )
        }
        chosen = stored["chosen"] as? String
        written = stored["written"] as? [String: String] ?? [:]
    }

    public var stored: [String: Any] {
        var stored: [String: Any] = ["written": written]
        if let before {
            stored["before"] = Dictionary(uniqueKeysWithValues: before.map { ($0.key.rawValue, $0.value) })
        }
        if let chosen {
            stored["chosen"] = chosen
        }
        return stored
    }

    public var canPutBack: Bool {
        before != nil
    }

    public func theme(in terminal: some TerminalSettingsStoring) -> TerminalTheme? {
        let name = terminal.profileName(for: .newWindows)
        return TerminalThemeCatalog.all.first { $0.profileName == name }
    }

    public func options(in terminal: some TerminalSettingsStoring) -> Set<TerminalOption>? {
        guard let theme = theme(in: terminal), let profile = terminal.profiles()[theme.profileName] else { return nil }
        return Set(TerminalOption.allCases.filter { $0.isOn(in: profile) })
    }

    public mutating func set(
        _ option: TerminalOption,
        to isOn: Bool,
        in terminal: some TerminalSettingsStoring
    ) -> Outcome {
        guard !terminal.isTerminalOpen else { return .terminalIsOpen }
        guard !terminal.isManaged else { return .managed }
        guard let name = theme(in: terminal)?.profileName else { return .unchanged }
        var profiles = terminal.profiles()
        guard var profile = profiles[name], option.isOn(in: profile) != isOn else { return .unchanged }
        let isStillPeels = written[name] != nil && TerminalProfile.fingerprint(of: profile) == written[name]
        option.set(isOn, in: &profile)
        profiles[name] = profile
        guard terminal.setProfiles(profiles) else { return .refused }
        if isStillPeels {
            written[name] = TerminalProfile.fingerprint(of: profile)
        }
        return .changed
    }

    public mutating func use(_ theme: TerminalTheme, in terminal: some TerminalSettingsStoring) throws -> Outcome {
        guard !terminal.isTerminalOpen else { return .terminalIsOpen }
        guard !terminal.isManaged else { return .managed }
        let name = theme.profileName
        let settings = try TerminalProfile.settings(for: theme, options: options(in: terminal) ?? [])
        guard let fingerprint = TerminalProfile.fingerprint(of: settings) else { return .refused }
        var profiles = terminal.profiles()
        let isStillPeels =
            written[name] != nil && profiles[name].flatMap(TerminalProfile.fingerprint(of:)) == written[name]
        let rewritesProfile = profiles[name] == nil || (isStillPeels && written[name] != fingerprint)
        let isInUse = TerminalProfileRole.allCases.allSatisfy { terminal.profileName(for: $0) == name }
        guard rewritesProfile || !isInUse else { return .unchanged }
        if rewritesProfile {
            profiles[name] = settings
            guard terminal.setProfiles(profiles) else { return .refused }
            written[name] = fingerprint
        }
        if before == nil {
            before = Dictionary(uniqueKeysWithValues: TerminalProfileRole.allCases.compactMap { role in
                terminal.profileName(for: role).map { (role, $0) }
            })
        }
        chosen = name
        for role in TerminalProfileRole.allCases {
            guard terminal.setProfileName(name, for: role) else { return .refused }
        }
        return .changed
    }

    public mutating func putBack(in terminal: some TerminalSettingsStoring) -> Outcome {
        guard let before else { return .unchanged }
        guard !terminal.isTerminalOpen else { return .terminalIsOpen }
        guard !terminal.isManaged else { return .managed }
        for role in TerminalProfileRole.allCases where terminal.profileName(for: role) == chosen {
            guard terminal.setProfileName(before[role], for: role) else { return .refused }
        }
        let inUse = Set(TerminalProfileRole.allCases.compactMap { terminal.profileName(for: $0) })
        var profiles = terminal.profiles()
        let untouched = written.filter { name, fingerprint in
            !inUse.contains(name) && profiles[name].flatMap(TerminalProfile.fingerprint(of:)) == fingerprint
        }
        if !untouched.isEmpty {
            untouched.keys.forEach { profiles[$0] = nil }
            guard terminal.setProfiles(profiles) else { return .refused }
        }
        self.before = nil
        chosen = nil
        written = [:]
        return .changed
    }
}
