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
        var setInIncludedFiles: Set<String> = []
    }

    private static let ledgerKey = "terminalGit"

    private var ledger = GitLedger(stored: UserDefaults.standard.dictionary(forKey: ledgerKey) ?? [:])
    private var git: GitConfig?
    private(set) var state: State?
    private var asked: [GitSetting: Bool] = [:]
    private(set) var wasRefused = false
    private var waiting: [GitSetting: Int] = [:]
    private var changes: Task<Void, Never>?

    var hasSomethingOn: Bool {
        GitSetting.allCases.contains(where: isOn)
    }

    func refresh() async {
        await afterTheOthers {
            await self.read()
        }.value
    }

    private func read() async {
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
            signingKey: GitSetting.signingKey(in: .homeDirectory),
            setInIncludedFiles: await git?.keysSetByIncludedFiles() ?? []
        )
    }

    func isOn(_ setting: GitSetting) -> Bool {
        asked[setting] ?? state?.settings.map(setting.isOn(in:)) ?? false
    }

    func isOffered(_ setting: GitSetting) -> Bool {
        guard let state, state.settings != nil, state.known.map(setting.isKnown(by:)) == true else { return false }
        guard !isSetInIncludedFiles(setting) else { return false }
        return setting != .signCommits || state.signingKey != nil || isOn(setting)
    }

    /// Whether a file the person's global settings include sets the setting, so Peel leaves it to them. One already on
    /// can still be turned off.
    func isSetInIncludedFiles(_ setting: GitSetting) -> Bool {
        guard let state, !isOn(setting) else { return false }
        return setting.isSetInIncludedFiles(state.setInIncludedFiles)
    }

    func set(_ setting: GitSetting, to isOn: Bool) {
        ask([setting], isOn: isOn)
        afterTheOthers {
            await self.change([setting], to: isOn)
        }
    }

    func turnAllOff() {
        let settings = GitSetting.allCases.filter(isOn)
        ask(settings, isOn: false)
        afterTheOthers {
            await self.change(settings, to: false)
        }
    }

    private func ask(_ settings: [GitSetting], isOn: Bool) {
        for setting in settings {
            asked[setting] = isOn
            waiting[setting, default: 0] += 1
        }
    }

    @discardableResult
    private func afterTheOthers(_ work: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let others = changes
        let task = Task {
            await others?.value
            await work()
        }
        changes = task
        return task
    }

    private func change(_ settings: [GitSetting], to isOn: Bool) async {
        if let git {
            var ledger = ledger
            var refused = false
            for setting in settings {
                let outcome = isOn
                    ? await ledger.turnOn(setting, signingKey: state?.signingKey, in: git)
                    : await ledger.turnOff(setting, in: git)
                refused = outcome == .refused || refused
            }
            self.ledger = ledger
            UserDefaults.standard.set(ledger.stored, forKey: Self.ledgerKey)
            wasRefused = refused
            await read()
        }
        for setting in settings {
            waiting[setting, default: 1] -= 1
            if waiting[setting] == 0 {
                waiting[setting] = nil
                asked[setting] = nil
            }
        }
    }
}
