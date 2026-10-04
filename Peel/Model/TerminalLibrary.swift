import AppKit
import Foundation
import Observation
import PeelCore

@Observable
final class TerminalLibrary {
    enum Action: Equatable {
        case use(TerminalTheme)
        case putBack
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
    private(set) var problem: TerminalThemeLedger.Outcome?
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
    }

    func perform(_ action: Action) {
        guard !settings.isTerminalOpen else {
            waitingForTerminal = action
            return
        }
        let outcome = switch action {
        case .use(let theme): (try? ledger.use(theme, in: settings)) ?? .refused
        case .putBack: ledger.putBack(in: settings)
        }
        UserDefaults.standard.set(ledger.stored, forKey: Self.ledgerKey)
        problem = outcome == .managed || outcome == .refused ? outcome : nil
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

    func openTerminal() {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: TerminalSettings.identifier) else { return }
        if settings.isTerminalOpen {
            NSWorkspace.shared.open([URL.homeDirectory], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.openApplication(at: terminal, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
