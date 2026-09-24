import Foundation
@testable import PeelCore
import Testing

/// A `TweakStoring` that keeps its values in a dictionary, so `TweakLedger` is tested without cfprefsd.
private final class FakeStore: TweakStoring {
    var values: [String: Any] = [:]
    var refusesWrites = false

    func storedValue(of tweak: Tweak) -> Any? { values[tweak.id] }

    func turnOn(_ tweak: Tweak, path: String?) -> Bool {
        guard !refusesWrites else { return false }
        values[tweak.id] = path ?? true
        return true
    }

    func restore(_ value: Any?, for tweak: Tweak) -> Bool {
        guard !refusesWrites else { return false }
        values[tweak.id] = value
        return true
    }
}

struct TweakLedgerTests {
    private let tweak = TweakCatalog.all[0]

    /// A setting made by hand has no value from before Peel to go back to, so turning it off removes the key
    /// and macOS falls back to its default. Written back as it stood, the switch would stay on.
    @Test func turningOffASettingMadeByHandTakesItOff() {
        let store = FakeStore()
        store.values[tweak.id] = true
        var ledger = TweakLedger()

        #expect(ledger.turnOff(tweak, in: store) == .changed)
        #expect(store.values[tweak.id] == nil, "the value that was there was written back")
    }

    /// What Peel changed goes back to what was there before Peel, which may be the user's own value.
    @Test func turningOffWhatPeelChangedPutsBackWhatWasThere() {
        let store = FakeStore()
        store.values[tweak.id] = 0.5
        var ledger = TweakLedger()

        #expect(ledger.turnOn(tweak, in: store) == .changed)
        #expect(ledger.changedByPeel == [tweak.id])
        #expect(ledger.turnOff(tweak, in: store) == .changed)
        #expect(store.values[tweak.id] as? Double == 0.5)
        #expect(ledger.changedByPeel.isEmpty)
        #expect(ledger.previousValues.isEmpty)
    }

    /// A switch that is already where it is asked to be reports `.unchanged`, so nothing needs restarting.
    @Test func sayWhenNothingChanged() {
        let store = FakeStore()
        var ledger = TweakLedger()

        #expect(ledger.turnOff(tweak, in: store) == .unchanged)
        store.values[tweak.id] = true
        #expect(ledger.turnOn(tweak, in: store) == .unchanged)
    }

    /// A key that already held the value, set by hand or in System Settings while the switch showed an older
    /// reading, was not changed by Peel. Turning it off later removes the key as for any setting made outside
    /// Peel; recorded as Peel's, the same value was written back and the switch stayed on.
    @Test func aKeyThatAlreadyHeldTheValueIsNotPeelsChange() {
        let store = FakeStore()
        store.values[tweak.id] = true
        var ledger = TweakLedger()

        #expect(ledger.turnOn(tweak, in: store) == .unchanged)
        #expect(ledger.changedByPeel.isEmpty)
        #expect(ledger.previousValues.isEmpty)
        #expect(ledger.turnOff(tweak, in: store) == .changed)
        #expect(store.values[tweak.id] == nil, "the setting stayed on")
    }

    /// When a write fails, the value read before it is not kept as the value from before Peel. Nothing of
    /// Peel's landed, and by the next write the user may have changed the value again.
    @Test func remembersNothingFromAWriteThatFailed() {
        let store = FakeStore()
        store.values[tweak.id] = "first"
        store.refusesWrites = true
        var ledger = TweakLedger()

        #expect(ledger.turnOn(tweak, in: store) == .refused)
        #expect(ledger.previousValues.isEmpty)

        store.refusesWrites = false
        store.values[tweak.id] = "second"
        _ = ledger.turnOn(tweak, in: store)
        _ = ledger.turnOff(tweak, in: store)
        #expect(store.values[tweak.id] as? String == "second")
    }

    /// Turn All Off changes only what is on, each the way its own switch would, and restarts the Dock once for
    /// all the Dock settings that changed.
    @Test func turningAllOffTakesOnlyWhatIsOn() {
        let docks = Array(TweakCatalog.all.filter { $0.restart == .dock }.prefix(3))
        let (byPeel, byHand, off) = (docks[0], docks[1], docks[2])
        let store = FakeStore()
        store.values[byPeel.id] = 0.5
        var ledger = TweakLedger()
        _ = ledger.turnOn(byPeel, in: store)
        store.values[byHand.id] = true
        let on = TweakState(isOn: true, isManaged: false, path: nil)
        let unset = TweakState.unset

        #expect(ledger.isOn(byPeel, state: on))
        #expect(ledger.isOn(byHand, state: on))
        #expect(!ledger.isOn(off, state: unset))
        let batch = ledger.turnOff([byPeel, byHand], in: store)

        #expect(batch.changed == [byPeel, byHand])
        #expect(batch.restarts == [.dock])
        #expect(batch.refused.isEmpty)
        #expect(store.values[byPeel.id] as? Double == 0.5)
        #expect(store.values[byHand.id] == nil)
        #expect(store.values[off.id] == nil)
    }

    /// A folder counts as on only where Peel chose it, since only then does its row offer to put it back. A
    /// value a configuration profile sets never counts as on.
    @Test func turningAllOffLeavesWhatNoRowWouldChange() throws {
        let folder = try #require(TweakCatalog.all.first { $0.kind == .folder })
        let aSwitch = TweakCatalog.all[0]
        let chosenByHand = TweakState(isOn: true, isManaged: false, path: "/Users/me/Shots")
        var ledger = TweakLedger()

        #expect(!ledger.isOn(folder, state: chosenByHand))
        #expect(!ledger.isOn(aSwitch, state: TweakState(isOn: true, isManaged: true, path: nil)))
        let store = FakeStore()
        _ = ledger.turnOn(folder, path: "/Users/me/Peel", in: store)
        #expect(ledger.isOn(folder, state: chosenByHand))
    }

    /// A write macOS refused leaves that switch where it was, says so, and restarts nothing for it.
    @Test func turningAllOffReportsWhatWasRefused() {
        let tweak = TweakCatalog.all[0]
        let store = FakeStore()
        store.values[tweak.id] = true
        store.refusesWrites = true
        var ledger = TweakLedger()

        let batch = ledger.turnOff([tweak], in: store)

        #expect(batch.refused == [tweak])
        #expect(batch.changed.isEmpty)
        #expect(batch.restarts.isEmpty)
        #expect(store.values[tweak.id] as? Bool == true)
    }
}
