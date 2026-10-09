/// What Peel wrote to Git's settings and what each key held before, so turning a setting off puts back what the
/// person had. A key the person changed after Peel did is theirs, and is left as it is.
public struct GitLedger {
    public enum Outcome: Sendable, Equatable {
        case changed
        case unchanged
        case refused
    }

    public private(set) var previous: [String: String]
    public private(set) var written: [String: String]

    public init(stored: [String: Any] = [:]) {
        previous = stored["previous"] as? [String: String] ?? [:]
        written = stored["written"] as? [String: String] ?? [:]
    }

    public var stored: [String: Any] {
        ["previous": previous, "written": written]
    }

    public mutating func turnOn(_ setting: GitSetting, signingKey: String?, in config: GitConfig) async -> Outcome {
        let values = setting.values(signingKey: signingKey)
        guard !values.isEmpty, let settings = await config.settings() else { return .refused }
        guard !setting.isSetInIncludedFiles(await config.keysSetByIncludedFiles()) else { return .unchanged }
        var outcome = Outcome.unchanged
        for wanted in values {
            let name = wanted.key.lowercased()
            let before = settings[name]
            guard before != .some(.some(wanted.value)) else { continue }
            let isPeels = written[name].map { before == .some(.some($0)) } ?? false
            guard await config.set(wanted.key, to: wanted.value) else { return .refused }
            if !isPeels {
                switch before {
                case .none: previous.removeValue(forKey: name)
                case .some(.none): previous[name] = "true"
                case .some(.some(let value)): previous[name] = value
                }
            }
            written[name] = wanted.value
            outcome = .changed
        }
        return outcome
    }

    public mutating func turnOff(_ setting: GitSetting, in config: GitConfig) async -> Outcome {
        guard let settings = await config.settings() else { return .refused }
        var outcome = Outcome.unchanged
        for key in setting.keys {
            let name = key.lowercased()
            let now = settings[name]
            if let mine = written[name] {
                if now == .some(.some(mine)) {
                    let restored = if let before = previous[name] {
                        await config.set(key, to: before)
                    } else {
                        await config.remove(key)
                    }
                    guard restored else { return .refused }
                    outcome = .changed
                }
                written.removeValue(forKey: name)
                previous.removeValue(forKey: name)
            } else if setting.switchKeys.contains(key), now != nil {
                guard await config.remove(key) else { return .refused }
                outcome = .changed
            }
        }
        return outcome
    }
}
