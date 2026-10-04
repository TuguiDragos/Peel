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
    /// What each key held before Peel changed it, so turning the tweak off can put it back. A key that held
    /// nothing has no entry.
    public private(set) var previousValues: [Tweak.ID: Any]
    /// What Peel wrote to each key it changed. A key that holds anything else was changed outside Peel since, and
    /// that choice is the person's: it is never written over with what was there before Peel.
    public private(set) var writtenValues: [Tweak.ID: Any]

    public init(
        changedByPeel: Set<Tweak.ID> = [], previousValues: [Tweak.ID: Any] = [:], writtenValues: [Tweak.ID: Any] = [:]
    ) {
        self.changedByPeel = changedByPeel
        self.previousValues = previousValues
        self.writtenValues = writtenValues
    }

    /// Whether `tweak`'s key still holds what Peel wrote to it.
    public func holdsPeelsChange(_ tweak: Tweak, stored: Any?) -> Bool {
        changedByPeel.contains(tweak.id) && Self.isSame(stored, writtenValues[tweak.id])
    }

    /// Takes what each key Peel changed holds now as what Peel wrote, for a ledger saved before Peel kept that.
    public mutating func adoptStoredValuesAsWritten(in store: some TweakStoring) {
        for tweak in TweakCatalog.all where changedByPeel.contains(tweak.id) && writtenValues[tweak.id] == nil {
            writtenValues[tweak.id] = store.storedValue(of: tweak)
        }
    }

    public mutating func turnOn(_ tweak: Tweak, path: String? = nil, in store: some TweakStoring) -> Outcome {
        let before = store.storedValue(of: tweak)
        let wasPeels = holdsPeelsChange(tweak, stored: before)
        guard store.turnOn(tweak, path: path) else { return .refused }
        let after = store.storedValue(of: tweak)
        // A key that already held the value was not changed by Peel, so turning it off later removes the key,
        // as for any setting made outside Peel.
        guard !Self.isSame(before, after) else { return .unchanged }
        // What the key held is recorded once the write succeeds, unless it was Peel's own value: after a failed
        // write the person may still change it, and a value they chose since Peel's change is theirs to get back.
        if !wasPeels {
            previousValues[tweak.id] = before
        }
        changedByPeel.insert(tweak.id)
        writtenValues[tweak.id] = after
        return .changed
    }

    /// Turns `tweak` off. A setting Peel changed gets back what its key held before. A setting made outside
    /// Peel has its key removed, so macOS falls back to its default. A key the person changed after Peel did is
    /// left as it is, and Peel forgets its change.
    public mutating func turnOff(_ tweak: Tweak, in store: some TweakStoring) -> Outcome {
        let before = store.storedValue(of: tweak)
        if changedByPeel.contains(tweak.id), !holdsPeelsChange(tweak, stored: before) {
            forget(tweak)
            return .unchanged
        }
        let restored = changedByPeel.contains(tweak.id) ? previousValues[tweak.id] : nil
        guard store.restore(restored, for: tweak) else { return .refused }
        forget(tweak)
        return Self.isSame(before, store.storedValue(of: tweak)) ? .unchanged : .changed
    }

    private mutating func forget(_ tweak: Tweak) {
        changedByPeel.remove(tweak.id)
        previousValues.removeValue(forKey: tweak.id)
        writtenValues.removeValue(forKey: tweak.id)
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
        case .aSwitch, .aSwitchForThisAppAlone: return state.isOn
        case .folder: return holdsPeelsChange(tweak, stored: state.path)
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
