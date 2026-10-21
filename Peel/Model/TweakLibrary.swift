import Foundation
import Observation
import PeelCore

@Observable
final class TweakLibrary {
    private static let changedKey = "tweaksChangedByPeel"
    /// What each key held before Peel changed it, so a reset gives the user their own setting back.
    private static let previousKey = "tweaksValuesBeforePeel"
    private static let writtenKey = "tweaksValuesWrittenByPeel"
    private static let waitingKey = "tweaksWaitingForLogOut"
    private static let sessionKey = "tweaksWaitingSession"

    /// The audit session ID (`man getaudit_addr`), which is new with each login. It tells whether a change
    /// still waiting for a log out was made in this session.
    private static let loginSession: Int = {
        var info = auditinfo_addr_t()
        return getaudit_addr(&info, Int32(MemoryLayout<auditinfo_addr_t>.size)) == 0 ? Int(info.ai_asid) : 0
    }()

    private let store: any TweakStoring
    private let defaults: UserDefaults
    private let home: URL
    /// Restarts the process that owns a setting; `TweakRestart.run` unless a test gives its own.
    private let restart: @Sendable (Tweak.Restart) async -> Void
    /// What Peel changed, and the values from before. `TweakLedger` decides what turning a switch on or off
    /// does, and is tested there.
    private var ledger: TweakLedger
    private(set) var states: [Tweak.ID: TweakState] = [:]
    private(set) var isSleepDisabled = false
    /// The settings changed in this login session that take effect only after the user logs out. They are
    /// saved with the session ID, so they survive quitting Peel and are dropped after the next login.
    private(set) var waitingForLogOut: Set<Tweak.ID>

    /// The preferences the tweaks are read from and written to, the store the ledger is kept in, the home whose
    /// Trash a screenshot folder is checked against, and what restarts a process: the person's own unless a test
    /// gives its own.
    init(
        store: any TweakStoring = TweakStore(),
        defaults: UserDefaults = .standard,
        home: URL = .homeDirectory,
        restart: @escaping @Sendable (Tweak.Restart) async -> Void = TweakRestart.run
    ) {
        self.store = store
        self.defaults = defaults
        self.home = home
        self.restart = restart
        ledger = TweakLedger(
            changedByPeel: Set(defaults.stringArray(forKey: Self.changedKey) ?? []),
            previousValues: defaults.dictionary(forKey: Self.previousKey) ?? [:],
            writtenValues: defaults.dictionary(forKey: Self.writtenKey) ?? [:]
        )
        let isThisSession = defaults.integer(forKey: Self.sessionKey) == Self.loginSession
        waitingForLogOut = isThisSession ? Set(defaults.stringArray(forKey: Self.waitingKey) ?? []) : []
        ledger.adoptStoredValuesAsWritten(in: store)
        refresh()
    }

    func isWaitingForLogOut(_ group: Tweak.Group) -> Bool {
        tweaks(in: group).contains { waitingForLogOut.contains($0.id) }
    }

    /// True for a setting Peel itself made and the person has not changed since, which is what it can put back.
    func isChangedByPeel(_ tweak: Tweak) -> Bool {
        ledger.holdsPeelsChange(tweak, stored: store.storedValue(of: tweak))
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
        states = Dictionary(
            TweakCatalog.all.map { ($0.id, store.state(of: $0)) },
            uniquingKeysWith: { first, _ in first }
        )
        isSleepDisabled = SleepSetting.isSleepDisabled()
    }

    /// The value each switch was just set to, kept until the write and any restart are done. A `Toggle` reads
    /// its binding again in the same update, so without this the switch would spring back until the write lands.
    private(set) var asked: [Tweak.ID: Bool] = [:]

    func isOn(_ tweak: Tweak, state: TweakState) -> Bool {
        asked[tweak.id] ?? state.isOn
    }

    /// A switch's changes to one tweak, made one at a time: flipped quickly, only the latest waiting change runs next.
    private var lines: [Tweak.ID: OneAtATime<Bool>] = [:]
    /// The tweaks changed by a switch whose restart was left to a change waiting after it.
    private var restartOwed: Set<Tweak.ID> = []

    /// Returns the task that makes the change, which a test can await; the page lets it run.
    @discardableResult
    func set(_ tweak: Tweak, on isOn: Bool) -> Task<Void, Never> {
        asked[tweak.id] = isOn
        let line = lines[tweak.id] ?? OneAtATime()
        lines[tweak.id] = line
        return Task {
            await line.ask(isOn) { [self] isOn, anotherWaits in
                let outcome = isOn ? ledger.turnOn(tweak, in: store) : ledger.turnOff(tweak, in: store)
                await finish(tweak, after: outcome, isLast: !anotherWaits())
            }
        }
    }

    func turnOn(_ tweak: Tweak, text: String? = nil) async {
        await finish(tweak, after: ledger.turnOn(tweak, text: text, in: store))
    }

    func rename(_ tweak: Tweak, to name: String) async {
        name.isEmpty ? await reset(tweak) : await turnOn(tweak, text: name)
    }

    /// Turns `tweak` off. A setting Peel changed gets back the value it had before. A setting changed by hand
    /// is removed, so macOS falls back to its default.
    func reset(_ tweak: Tweak) async {
        await finish(tweak, after: ledger.turnOff(tweak, in: store))
    }

    private func save() {
        defaults.set(Array(ledger.changedByPeel), forKey: Self.changedKey)
        defaults.set(ledger.previousValues, forKey: Self.previousKey)
        defaults.set(ledger.writtenValues, forKey: Self.writtenKey)
        defaults.set(Array(waitingForLogOut), forKey: Self.waitingKey)
        defaults.set(Self.loginSession, forKey: Self.sessionKey)
    }

    func chooseScreenshotFolder(for tweak: Tweak) async {
        // Asked again once the panel has closed, since the folder can change after the panel's own check.
        guard let url = await ScreenshotFolderPanel.choose(), ScreenshotFolder.problem(with: url, home: home) == nil
        else { return }
        await turnOn(tweak, text: ScreenshotFolder.setting(for: url))
    }

    /// The settings Peel could not write, so each row can say so instead of letting the switch spring back
    /// with no reason. A tweak leaves the set with its next write that lands, and all of them when the page goes.
    private(set) var refused: Set<Tweak.ID> = []

    func forgetRefusals() {
        refused = []
    }
    private(set) var isTurningAllOff = false

    /// Whether Turn All Off has anything to change.
    var hasSomethingOn: Bool {
        Self.onTweaksPage.contains { ledger.isOn($0, state: state(of: $0)) }
    }

    private static let onTweaksPage = TweakCatalog.all.filter { Tweak.Group.onTweaksPage.contains($0.group) }

    /// Turns off every tweak that is on, as its own switch would, and restarts each affected process once.
    func turnAllOff() async {
        isTurningAllOff = true
        defer { isTurningAllOff = false }
        // Read again: System Settings may have changed any of these after the page was drawn.
        refresh()
        let tried = Self.onTweaksPage.filter { ledger.isOn($0, state: state(of: $0)) }
        let batch = ledger.turnOff(tried, in: store)
        refused.subtract(tried.map(\.id))
        refused.formUnion(batch.refused.map(\.id))
        for tweak in batch.changed where tweak.restart == .logOut {
            waitingForLogOut.formSymmetricDifference([tweak.id])
        }
        save()
        for needed in batch.restarts {
            await restart(needed)
        }
        refresh()
    }

    /// Saves the result of a change and restarts what the tweak needs. Nothing restarts when the setting was
    /// already as asked.
    private func finish(_ tweak: Tweak, after outcome: TweakLedger.Outcome, isLast: Bool = true) async {
        defer { if isLast { asked[tweak.id] = nil } }
        if outcome == .refused { refused.insert(tweak.id) } else { refused.remove(tweak.id) }
        guard outcome != .refused else {
            if isLast, restartOwed.remove(tweak.id) != nil { await restart(tweak.restart) }
            refresh()
            return
        }
        // Each change flips the tweak in or out of the waiting set: changed and then changed back, it is as it
        // was at login, and nothing waits.
        if outcome == .changed, tweak.restart == .logOut {
            waitingForLogOut.formSymmetricDifference([tweak.id])
        }
        save()
        if !isLast {
            if outcome == .changed { restartOwed.insert(tweak.id) }
        } else {
            let wasOwed = restartOwed.remove(tweak.id) != nil
            if outcome == .changed || wasOwed { await restart(tweak.restart) }
        }
        refresh()
    }
}

extension Tweak.Group {
    static let onTweaksPage = allCases.filter { $0 != .terminal }

    var title: LocalizedStringResource {
        switch self {
        case .dock: "Dock"
        case .screenshots: "Screenshots"
        case .finder: "Finder"
        case .typing: "Typing"
        case .windows: "Windows"
        case .privacy: "Privacy"
        case .terminal: "Terminal"
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
        case .terminal: "terminal"
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
        case .terminalQuits: "Takes effect the next time Terminal quits"
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
        case .terminalQuits: "Takes effect the next time Terminal quits."
        }
    }
}
