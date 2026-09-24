import AppKit
import Foundation
import Observation
import PeelCore

@Observable
final class TweakLibrary {
    private static let changedKey = "tweaksChangedByPeel"
    /// What each key held before Peel changed it, so a reset gives the user their own setting back.
    private static let previousKey = "tweaksValuesBeforePeel"
    private static let waitingKey = "tweaksWaitingForLogOut"
    private static let sessionKey = "tweaksWaitingSession"

    /// The audit session ID (`man getaudit_addr`), which is new with each login. It tells whether a change
    /// still waiting for a log out was made in this session.
    private static let loginSession: Int = {
        var info = auditinfo_addr_t()
        return getaudit_addr(&info, Int32(MemoryLayout<auditinfo_addr_t>.size)) == 0 ? Int(info.ai_asid) : 0
    }()

    private let store = TweakStore()
    /// What Peel changed, and the values from before. `TweakLedger` decides what turning a switch on or off
    /// does, and is tested there.
    private var ledger: TweakLedger
    private(set) var states: [Tweak.ID: TweakState] = [:]
    private(set) var isSleepDisabled = false
    /// The settings changed in this login session that take effect only after the user logs out. They are
    /// saved with the session ID, so they survive quitting Peel and are dropped after the next login.
    private(set) var waitingForLogOut: Set<Tweak.ID>

    init() {
        ledger = TweakLedger(
            changedByPeel: Set(UserDefaults.standard.stringArray(forKey: Self.changedKey) ?? []),
            previousValues: UserDefaults.standard.dictionary(forKey: Self.previousKey) ?? [:]
        )
        let isThisSession = UserDefaults.standard.integer(forKey: Self.sessionKey) == Self.loginSession
        waitingForLogOut = isThisSession ? Set(UserDefaults.standard.stringArray(forKey: Self.waitingKey) ?? []) : []
    }

    func isWaitingForLogOut(_ group: Tweak.Group) -> Bool {
        tweaks(in: group).contains { waitingForLogOut.contains($0.id) }
    }

    /// True for a setting Peel itself made, which is what it can put back.
    func isChangedByPeel(_ tweak: Tweak) -> Bool {
        ledger.changedByPeel.contains(tweak.id)
    }

    func tweaks(in group: Tweak.Group) -> [Tweak] {
        TweakCatalog.all.filter { $0.group == group }
    }

    func state(of tweak: Tweak) -> TweakState {
        states[tweak.id] ?? .unset
    }

    /// Reads every tweak's state again. System Settings can change any of them while Peel runs, so the page
    /// calls this each time Peel becomes active rather than trusting what it read before.
    func refresh() {
        store.beginReading()
        states = Dictionary(TweakCatalog.all.map { ($0.id, store.state(of: $0)) }, uniquingKeysWith: { first, _ in first })
        isSleepDisabled = SleepSetting.isSleepDisabled()
    }

    /// The value each switch was just set to, kept until the write and any restart are done. A `Toggle` reads
    /// its binding again in the same update, so without this the switch would spring back until the write lands.
    private(set) var asked: [Tweak.ID: Bool] = [:]

    func isOn(_ tweak: Tweak, state: TweakState) -> Bool {
        asked[tweak.id] ?? state.isOn
    }

    func set(_ tweak: Tweak, on isOn: Bool) {
        asked[tweak.id] = isOn
        Task { isOn ? await turnOn(tweak) : await reset(tweak) }
    }

    func turnOn(_ tweak: Tweak, path: String? = nil) async {
        await finish(tweak, after: ledger.turnOn(tweak, path: path, in: store))
    }

    /// Turns `tweak` off. A setting Peel changed gets back the value it had before. A setting changed by hand
    /// is removed, so macOS falls back to its default.
    func reset(_ tweak: Tweak) async {
        await finish(tweak, after: ledger.turnOff(tweak, in: store))
    }

    private func save() {
        UserDefaults.standard.set(Array(ledger.changedByPeel), forKey: Self.changedKey)
        UserDefaults.standard.set(ledger.previousValues, forKey: Self.previousKey)
        UserDefaults.standard.set(Array(waitingForLogOut), forKey: Self.waitingKey)
        UserDefaults.standard.set(Self.loginSession, forKey: Self.sessionKey)
    }

    func chooseScreenshotFolder(for tweak: Tweak) async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Where should screenshots be saved?")
        guard await panel.begin() == .OK, let url = panel.url else { return }
        // screencapture writes nothing at all if the folder isn't there, so it is checked before it is set.
        var isDirectory: ObjCBool = false
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue,
              FileManager.default.isWritableFile(atPath: path)
        else { return }
        await turnOn(tweak, path: path)
    }

    /// The settings Peel could not write, so each row can say so instead of letting the switch spring back
    /// with no reason. Cleared by the next attempt, and by leaving the page.
    private(set) var refused: Set<Tweak.ID> = []

    func forgetRefusals() {
        refused = []
    }
    private(set) var isTurningAllOff = false

    /// Whether Turn All Off has anything to change.
    var hasSomethingOn: Bool {
        TweakCatalog.all.contains { ledger.isOn($0, state: state(of: $0)) }
    }

    /// Turns off every tweak that is on, as its own switch would, and restarts each affected process once.
    func turnAllOff() async {
        isTurningAllOff = true
        defer { isTurningAllOff = false }
        // Read again: System Settings may have changed any of these after the page was drawn.
        refresh()
        let batch = ledger.turnOff(TweakCatalog.all.filter { ledger.isOn($0, state: state(of: $0)) }, in: store)
        refused = Set(batch.refused.map(\.id))
        for tweak in batch.changed where tweak.restart == .logOut {
            waitingForLogOut.formSymmetricDifference([tweak.id])
        }
        save()
        for restart in batch.restarts {
            await TweakRestart.run(restart)
        }
        refresh()
    }

    /// Saves the result of a change and restarts what the tweak needs. Nothing restarts when the setting was
    /// already as asked.
    private func finish(_ tweak: Tweak, after outcome: TweakLedger.Outcome) async {
        defer { asked[tweak.id] = nil }
        refused = outcome == .refused ? [tweak.id] : []
        guard outcome != .refused else {
            refresh()
            return
        }
        // Each change flips the tweak in or out of the waiting set: changed and then changed back, it is as it
        // was at login, and nothing waits.
        if outcome == .changed, tweak.restart == .logOut {
            waitingForLogOut.formSymmetricDifference([tweak.id])
        }
        save()
        if outcome == .changed {
            await TweakRestart.run(tweak.restart)
        }
        refresh()
    }
}

extension Tweak.Group {
    var title: LocalizedStringResource {
        switch self {
        case .dock: "Dock"
        case .screenshots: "Screenshots"
        case .finder: "Finder"
        case .typing: "Typing"
        case .windows: "Windows"
        case .privacy: "Privacy"
        }
    }

    var systemImage: String {
        switch self {
        case .dock: "dock.rectangle"
        case .screenshots: "camera.viewfinder"
        case .finder: "folder"
        case .typing: "keyboard"
        case .windows: "macwindow"
        case .privacy: "hand.raised"
        }
    }
}

extension Tweak.Restart {
    var note: LocalizedStringResource? {
        switch self {
        case .none: nil
        case .dock: "The Dock restarts"
        case .finder: "Finder restarts"
        case .controlCenter: "The menu bar restarts"
        case .windowManager: "Window tiling restarts"
        case .relaunchApps: "Open apps keep the old setting until you reopen them"
        case .logOut: "Takes effect after you log out"
        }
    }

    /// The same note as a full sentence, for the text behind the circled i. Each language ends it with its own
    /// punctuation.
    var sentence: LocalizedStringResource? {
        switch self {
        case .none: nil
        case .dock: "The Dock restarts."
        case .finder: "Finder restarts."
        case .controlCenter: "The menu bar restarts."
        case .windowManager: "Window tiling restarts."
        case .relaunchApps: "Open apps keep the old setting until you reopen them."
        case .logOut: "Takes effect after you log out."
        }
    }
}
