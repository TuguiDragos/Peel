import Foundation
import Observation
import PeelCore

@Observable
final class GitLibrary {
    private static let ledgerKey = "terminalGit"

    private var ledger = GitLedger(stored: UserDefaults.standard.dictionary(forKey: ledgerKey) ?? [:])
    private(set) var git: GitConfig?
    private(set) var hasLooked = false
    private(set) var settings: [String: String?]?
    private(set) var known: Set<String>?
    private(set) var signingKey: String?
    private(set) var isWorking = false
    private(set) var wasRefused = false

    var hasSomethingOn: Bool {
        GitSetting.allCases.contains(where: isOn)
    }

    func refresh() async {
        if git == nil {
            git = await GitConfig.find()
        }
        hasLooked = true
        settings = await git?.settings()
        if known == nil {
            known = await git?.knownKeys()
        }
        signingKey = GitSetting.signingKey(in: .homeDirectory)
    }

    func isOn(_ setting: GitSetting) -> Bool {
        settings.map(setting.isOn(in:)) ?? false
    }

    func isOffered(_ setting: GitSetting) -> Bool {
        guard settings != nil, known.map(setting.isKnown(by:)) == true else { return false }
        return setting != .signCommits || signingKey != nil || isOn(setting)
    }

    func set(_ setting: GitSetting, to isOn: Bool) async {
        guard let git, !isWorking else { return }
        isWorking = true
        var ledger = ledger
        let outcome = isOn
            ? await ledger.turnOn(setting, signingKey: signingKey, in: git)
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
