import Foundation
import Observation
import PeelCore

@Observable
final class GitLibrary {
    struct State: Equatable {
        var isInstalled: Bool
        var settings: [String: String?]?
        var known: Set<String>?
        var signingKey: String?
    }

    private static let ledgerKey = "terminalGit"

    private var ledger = GitLedger(stored: UserDefaults.standard.dictionary(forKey: ledgerKey) ?? [:])
    private var git: GitConfig?
    private(set) var state: State?
    private(set) var isWorking = false
    private(set) var wasRefused = false

    var hasSomethingOn: Bool {
        GitSetting.allCases.contains(where: isOn)
    }

    func refresh() async {
        let git = if let git { git } else { await GitConfig.find() }
        let settings = await git?.settings()
        var known = state?.known
        if known == nil {
            known = await git?.knownKeys()
        }
        self.git = git
        state = State(
            isInstalled: git != nil,
            settings: settings,
            known: known,
            signingKey: GitSetting.signingKey(in: .homeDirectory)
        )
    }

    func isOn(_ setting: GitSetting) -> Bool {
        state?.settings.map(setting.isOn(in:)) ?? false
    }

    func isOffered(_ setting: GitSetting) -> Bool {
        guard let state, state.settings != nil, state.known.map(setting.isKnown(by:)) == true else { return false }
        return setting != .signCommits || state.signingKey != nil || isOn(setting)
    }

    func set(_ setting: GitSetting, to isOn: Bool) async {
        guard let git, !isWorking else { return }
        isWorking = true
        var ledger = ledger
        let outcome = isOn
            ? await ledger.turnOn(setting, signingKey: state?.signingKey, in: git)
            : await ledger.turnOff(setting, in: git)
        finish(ledger, refused: outcome == .refused)
        await refresh()
    }

    func turnAllOff() async {
        guard let git, !isWorking else { return }
        isWorking = true
        var ledger = ledger
        var refused = false
        for setting in GitSetting.allCases where isOn(setting) {
            refused = await ledger.turnOff(setting, in: git) == .refused || refused
        }
        finish(ledger, refused: refused)
        await refresh()
    }

    private func finish(_ ledger: GitLedger, refused: Bool) {
        self.ledger = ledger
        UserDefaults.standard.set(ledger.stored, forKey: Self.ledgerKey)
        wasRefused = refused
        isWorking = false
    }
}
