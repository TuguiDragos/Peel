/// What each key of a setting held before Peel turned the setting on, and what Peel wrote or found there, so
/// turning the setting off puts back exactly what the person had: a key found already at its value stays. A key
/// the person changed after Peel did is theirs, and is left as it is.
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

    /// Turns `setting` on through Git, and hands the ledger to `saving` with each key before Git writes it, so what a
    /// key held is kept even if Peel ends right after; a key Git refuses is taken out again and handed over once more.
    public mutating func turnOn(
        _ setting: GitSetting, signingKey: String?, in config: GitConfig, saving: (GitLedger) -> Void = { _ in }
    ) async -> Outcome {
        let values = setting.values(signingKey: signingKey)
        guard !values.isEmpty, let settings = await config.settings() else { return .refused }
        guard !setting.isSetInIncludedFiles(await config.keysSetByIncludedFiles()) else { return .unchanged }
        var outcome = Outcome.unchanged
        for wanted in values {
            let name = wanted.key.lowercased()
            let before = settings[name]
            let isPeels = written[name].map { before == .some(.some($0)) } ?? false
            let kept = (previous: previous[name], written: written[name])
            if !isPeels {
                switch before {
                case .none: previous.removeValue(forKey: name)
                case .some(.none): previous[name] = "true"
                case .some(.some(let value)): previous[name] = value
                }
            }
            written[name] = wanted.value
            saving(self)
            if before != .some(.some(wanted.value)) {
                guard await config.set(wanted.key, to: wanted.value) else {
                    previous[name] = kept.previous
                    written[name] = kept.written
                    saving(self)
                    return .refused
                }
                outcome = .changed
            }
        }
        return outcome
    }

    /// Turns `setting` off, putting back what the ledger holds, and hands the ledger to `saving` after each key it
    /// lets go of.
    public mutating func turnOff(
        _ setting: GitSetting, in config: GitConfig, saving: (GitLedger) -> Void = { _ in }
    ) async -> Outcome {
        guard let settings = await config.settings() else { return .refused }
        var outcome = Outcome.unchanged
        for key in setting.keys {
            let name = key.lowercased()
            let now = settings[name]
            if let mine = written[name] {
                if now == .some(.some(mine)), previous[name] != mine {
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
                saving(self)
            } else if setting.switchKeys.contains(key), now != nil {
                guard await config.remove(key) else { return .refused }
                outcome = .changed
            }
        }
        return outcome
    }
}
