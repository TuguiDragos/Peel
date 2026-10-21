import Foundation
@testable import PeelCore
import Testing

/// A `TweakStoring` that keeps its values in a dictionary, so `TweakLedger` is tested without cfprefsd.
private final class FakeStore: TweakStoring {
    var values: [String: Any] = [:]
    var refusesWrites = false

    func beginReading() {}

    func state(of tweak: Tweak) -> TweakState {
        let text = values[tweak.id] as? String
        return TweakState(isOn: values[tweak.id] != nil, isManaged: false, text: text)
    }

    func storedValue(of tweak: Tweak) -> Any? { values[tweak.id] }

    func turnOn(_ tweak: Tweak, text: String?) -> Bool {
        guard !refusesWrites else { return false }
        values[tweak.id] = text ?? true
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

    /// Turn All Off puts back only what Peel changed, each the way its own switch would, and restarts the Dock
    /// once for all the Dock settings that changed; a setting the person made stays theirs.
    @Test func turningAllOffTakesOnlyWhatPeelChanged() {
        let docks = Array(TweakCatalog.all.filter { $0.restart == .dock }.prefix(3))
        let (byPeel, byHand, off) = (docks[0], docks[1], docks[2])
        let store = FakeStore()
        store.values[byPeel.id] = 0.5
        var ledger = TweakLedger()
        _ = ledger.turnOn(byPeel, in: store)
        store.values[byHand.id] = true
        let on = TweakState(isOn: true, isManaged: false, text: nil)

        #expect(ledger.isPeels(byPeel, state: on, stored: store.values[byPeel.id]))
        #expect(!ledger.isPeels(byHand, state: on, stored: store.values[byHand.id]))
        #expect(!ledger.isPeels(off, state: .unset, stored: nil))
        let batch = ledger.turnOff([byPeel], in: store)

        #expect(batch.changed == [byPeel])
        #expect(batch.restarts == [.dock])
        #expect(batch.refused.isEmpty)
        #expect(store.values[byPeel.id] as? Double == 0.5)
        #expect(store.values[byHand.id] as? Bool == true)
        #expect(store.values[off.id] == nil)
    }

    /// Nothing Peel changed is put back by Turn All Off while a configuration profile sets it or another layer of
    /// the preferences holds it, nor once its key holds something else than Peel wrote.
    @Test func turningAllOffLeavesWhatNoRowWouldChange() throws {
        let folder = try #require(TweakCatalog.all.first { $0.kind == .folder })
        let aSwitch = TweakCatalog.all[0]
        let store = FakeStore()
        var ledger = TweakLedger()
        _ = ledger.turnOn(aSwitch, in: store)
        _ = ledger.turnOn(folder, text: "/Users/me/Peel", in: store)
        let on = TweakState(isOn: true, isManaged: false, text: nil)

        #expect(ledger.isPeels(aSwitch, state: on, stored: store.values[aSwitch.id]))
        let managed = TweakState(isOn: true, isManaged: true, text: nil)
        #expect(!ledger.isPeels(aSwitch, state: managed, stored: store.values[aSwitch.id]))
        let heldForThisMac = TweakState(isOn: true, isManaged: false, text: nil, heldElsewhere: .thisMac)
        #expect(!ledger.isPeels(aSwitch, state: heldForThisMac, stored: store.values[aSwitch.id]))
        let chosen = TweakState(isOn: true, isManaged: false, text: "/Users/me/Peel")
        #expect(ledger.isPeels(folder, state: chosen, stored: "/Users/me/Peel"))
        #expect(!ledger.isPeels(folder, state: chosen, stored: "/Users/me/Shots"), "a folder chosen since is the person's")
    }

    @Test func aNamePutBackIsTheNameFromBefore() throws {
        let name = try #require(TweakCatalog.all.first { $0.kind == .name })
        let store = FakeStore()
        store.values[name.id] = "ss"
        var ledger = TweakLedger()

        let named = TweakState(isOn: true, isManaged: false, text: "ss")
        #expect(!ledger.isPeels(name, state: named, stored: "ss"))
        #expect(ledger.turnOn(name, text: "shot", in: store) == .changed)
        #expect(ledger.isPeels(name, state: TweakState(isOn: true, isManaged: false, text: "shot"), stored: "shot"))
        #expect(ledger.turnOff(name, in: store) == .changed)
        #expect(store.values[name.id] as? String == "ss")
    }

    /// Once what the key held before is forgotten, turning the tweak off hands the setting to macOS, as for a
    /// setting made outside Peel: for a folder that can no longer take screenshots.
    @Test func aForgottenPreviousValueHandsTheSettingToMacOS() throws {
        let folder = try #require(TweakCatalog.all.first { $0.kind == .folder })
        let store = FakeStore()
        store.values[folder.id] = "/Users/me/Gone"
        var ledger = TweakLedger()
        _ = ledger.turnOn(folder, text: "/Users/me/Peel", in: store)

        ledger.forgetPreviousValue(of: folder)

        #expect(ledger.changedByPeel == [folder.id])
        #expect(ledger.turnOff(folder, in: store) == .changed)
        #expect(store.values[folder.id] == nil)
        #expect(ledger.changedByPeel.isEmpty)
    }

    /// A key the person changed in macOS after Peel did holds their choice now, never written over with what was
    /// there before Peel: the folder chosen later stays, and Peel forgets its change.
    @Test func aChoiceMadeOutsidePeelSinceIsNeverWrittenOver() throws {
        let folder = try #require(TweakCatalog.all.first { $0.kind == .folder })
        let store = FakeStore()
        store.values[folder.id] = "/Users/me/Old"
        var ledger = TweakLedger()
        _ = ledger.turnOn(folder, text: "/Users/me/Peel", in: store)
        store.values[folder.id] = "/Users/me/New"

        #expect(!ledger.holdsPeelsChange(folder, stored: store.values[folder.id]))
        #expect(ledger.turnOff(folder, in: store) == .unchanged)
        #expect(store.values[folder.id] as? String == "/Users/me/New")
        #expect(ledger.changedByPeel.isEmpty)
        #expect(ledger.previousValues.isEmpty)
    }

    /// Turned on again after the person changed the key in macOS, the tweak later puts back their newer value.
    @Test func turningOnAgainRemembersTheValueChosenSince() {
        let store = FakeStore()
        store.values[tweak.id] = 0.5
        var ledger = TweakLedger()
        _ = ledger.turnOn(tweak, in: store)
        store.values[tweak.id] = 0.7

        #expect(ledger.turnOn(tweak, in: store) == .changed)
        #expect(ledger.turnOff(tweak, in: store) == .changed)
        #expect(store.values[tweak.id] as? Double == 0.7)
    }

    /// A ledger saved before Peel kept what it wrote takes what each key holds as Peel's, which is how it read them.
    @Test func aLedgerFromBeforeTakesWhatIsStoredAsPeels() {
        let store = FakeStore()
        store.values[tweak.id] = true
        var ledger = TweakLedger(changedByPeel: [tweak.id], previousValues: [tweak.id: 0.5])

        ledger.adoptStoredValuesAsWritten(in: store)

        #expect(ledger.turnOff(tweak, in: store) == .changed)
        #expect(store.values[tweak.id] as? Double == 0.5)
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
