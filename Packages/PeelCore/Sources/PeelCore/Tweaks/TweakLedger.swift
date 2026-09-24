import Foundation

/// The reads and writes `TweakLedger` needs. `TweakStore` provides them through CFPreferences.
public protocol TweakStoring {
    func storedValue(of tweak: Tweak) -> Any?
    func turnOn(_ tweak: Tweak, path: String?) -> Bool
    /// Writes `value` back, or removes the key when there is none, which hands the setting back to macOS.
    func restore(_ value: Any?, for tweak: Tweak) -> Bool
}

/// Tracks which tweaks Peel turned on and what their keys held before, and decides what turning a tweak on
/// or off does.
public struct TweakLedger {
    public enum Outcome: Sendable, Equatable {
        /// Nothing was written: the key is managed (for example by a configuration profile), or the write failed.
        case refused
        /// The stored value is the same as before, so nothing needs to restart.
        case unchanged
        case changed
    }

    /// The tweaks Peel turned on and has not turned off since.
    public private(set) var changedByPeel: Set<Tweak.ID>
    /// What each key held before Peel first changed it, so turning the tweak off can put it back. A key that
    /// held nothing has no entry.
    public private(set) var previousValues: [Tweak.ID: Any]

    public init(changedByPeel: Set<Tweak.ID> = [], previousValues: [Tweak.ID: Any] = [:]) {
        self.changedByPeel = changedByPeel
        self.previousValues = previousValues
    }

    public mutating func turnOn(_ tweak: Tweak, path: String? = nil, in store: some TweakStoring) -> Outcome {
        let before = store.storedValue(of: tweak)
        guard store.turnOn(tweak, path: path) else { return .refused }
        // A key that already held the value was not changed by Peel, so turning it off later removes the key,
        // as for any setting made outside Peel.
        guard !Self.isSame(before, store.storedValue(of: tweak)) else { return .unchanged }
        // The previous value is recorded only after the write succeeds, and only the first time. After a
        // failed write, the user may still change the value. After the first write, the key holds Peel's value.
        if !changedByPeel.contains(tweak.id), let before {
            previousValues[tweak.id] = before
        }
        changedByPeel.insert(tweak.id)
        return .changed
    }

    /// Turns `tweak` off. A setting Peel changed gets back what its key held before. A setting made outside
    /// Peel has its key removed, so macOS falls back to its default.
    public mutating func turnOff(_ tweak: Tweak, in store: some TweakStoring) -> Outcome {
        let before = store.storedValue(of: tweak)
        let restored = changedByPeel.contains(tweak.id) ? previousValues[tweak.id] : nil
        guard store.restore(restored, for: tweak) else { return .refused }
        changedByPeel.remove(tweak.id)
        previousValues.removeValue(forKey: tweak.id)
        return Self.isSame(before, store.storedValue(of: tweak)) ? .unchanged : .changed
    }

    /// The result of turning several tweaks off. `restarts` lists each restart once, however many of its
    /// settings changed.
    public struct Batch: Sendable, Equatable {
        public var changed: [Tweak] = []
        public var refused: [Tweak] = []
        public var restarts: [Tweak.Restart] = []
    }

    /// Returns whether Turn All Off should turn `tweak` off. It matches what the tweak's own row offers: a
    /// switch that is on, or a folder that Peel chose, since only then does the row show Put Back. A managed
    /// value is left alone, as the row leaves it.
    public func isOn(_ tweak: Tweak, state: TweakState) -> Bool {
        guard !state.isManaged else { return false }
        switch tweak.kind {
        case .aSwitch: return state.isOn
        case .folder: return changedByPeel.contains(tweak.id)
        }
    }

    /// Turns each of `tweaks` off exactly as its own row would.
    public mutating func turnOff(_ tweaks: [Tweak], in store: some TweakStoring) -> Batch {
        var batch = Batch()
        for tweak in tweaks {
            switch turnOff(tweak, in: store) {
            case .refused:
                batch.refused.append(tweak)
            case .unchanged:
                break
            case .changed:
                batch.changed.append(tweak)
                if !batch.restarts.contains(tweak.restart) {
                    batch.restarts.append(tweak.restart)
                }
            }
        }
        return batch
    }

    private static func isSame(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case (let lhs as NSObject, let rhs as NSObject): lhs.isEqual(rhs)
        default: false
        }
    }
}
