import AppKit
import Foundation
import Observation
import PeelCore

@Observable
final class TerminalLibrary {
    enum Action: Equatable {
        case use(TerminalTheme)
        case putBack
        case set(TerminalOption, Bool)
    }

    private static let ledgerKey = "terminalThemes"
    private static let patience: Duration = .seconds(10)

    private let settings = TerminalSettings()
    private var ledger: TerminalThemeLedger
    private(set) var themeInUse: TerminalTheme?
    private(set) var profileInUse: String?
    private(set) var canPutBack = false
    private(set) var isTerminalOpen = false
    private(set) var isQuittingTerminal = false
    private(set) var quietsLogin = false
    private(set) var isMovingQuietLogin = false
    private(set) var shellSessions: ShellSessions?
    private(set) var options: Set<TerminalOption>?
    private(set) var isManaged = false
    private(set) var wasRefused = false
    var waitingForTerminal: Action?
    var terminalDidNotQuit = false

    init() {
        ledger = TerminalThemeLedger(stored: UserDefaults.standard.dictionary(forKey: Self.ledgerKey) ?? [:])
    }

    func refresh() {
        profileInUse = settings.profileName(for: .newWindows)
        themeInUse = ledger.theme(in: settings)
        canPutBack = ledger.canPutBack
        isTerminalOpen = settings.isTerminalOpen
        quietsLogin = HushLogin.isOn(in: .homeDirectory)
        shellSessions = ShellSessions.inTerminal(settings)
        options = ledger.options(in: settings)
        isManaged = settings.isManaged
    }

    func perform(_ action: Action) {
        guard !settings.isTerminalOpen else {
            waitingForTerminal = action
            return
        }
        let outcome = switch action {
        case .use(let theme): (try? ledger.use(theme, in: settings)) ?? .refused
        case .putBack: ledger.putBack(in: settings)
        case .set(let option, let isOn): ledger.set(option, to: isOn, in: settings)
        }
        UserDefaults.standard.set(ledger.stored, forKey: Self.ledgerKey)
        wasRefused = outcome == .refused
        refresh()
    }

    func quitTerminal(andThen action: Action) async {
        waitingForTerminal = nil
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: TerminalSettings.identifier)
        isQuittingTerminal = true
        defer { isQuittingTerminal = false }
        running.forEach { $0.terminate() }
        let didQuit = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await QuitBeforeRemoving.untilGone(running); return true }
            group.addTask { try? await Task.sleep(for: Self.patience); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        guard didQuit else {
            terminalDidNotQuit = true
            return
        }
        perform(action)
    }

    func turnOnQuietLogin() {
        quietsLogin = HushLogin.turnOn(in: .homeDirectory)
    }

    func moveQuietLoginToTrash(recording record: (TrashResult, [URL: Int64]) async -> Void) async -> TrashResult {
        isMovingQuietLogin = true
        defer { isMovingQuietLogin = false }
        let file = HushLogin.url(in: .homeDirectory)
        let sizes = [URL: Int64](measured: [(file, await FileSize.reclaimableSize(of: file))])
        let result = await QuitGuard.shared.run {
            let result = await TrashService(exclusions: ExclusionsStore.shared.exclusions).trash([file])
            await record(result, sizes)
            return result
        }
        quietsLogin = HushLogin.isOn(in: .homeDirectory)
        return result
    }

    func openTerminal() {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: TerminalSettings.identifier) else { return }
        if settings.isTerminalOpen {
            NSWorkspace.shared.open([URL.homeDirectory], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.openApplication(at: terminal, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
