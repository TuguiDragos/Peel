import Foundation
import Observation
import PeelCore

@Observable
final class ShellLibrary {
    struct State: Equatable {
        var shell: ShellSessions?
        var choices: ShellFile.Choices?
        var isSourced: Bool
        var setsItsOwnPrompt: Bool
        var known: Set<String>?

        var startupFile: URL? {
            shell?.zshrc
        }
    }

    let file = ShellFile.url(in: PeelFolder.url)
    private(set) var state: State?
    private(set) var wasRefused = false
    private(set) var draft = Prompt()

    var line: String {
        ShellFile.line(sourcing: file, home: .homeDirectory)
    }

    var hasSomethingOn: Bool {
        state?.choices.map { !$0.settings.isEmpty || $0.prompt != nil } ?? false
    }

    func refresh() async {
        var known = state?.known
        if known == nil {
            known = await ShellFile.knownToZsh()
        }
        let shell = ShellSessions.inTerminal(TerminalSettings())
        let choices = ShellFile.read(file)
        state = State(
            shell: shell,
            choices: choices,
            isSourced: shell?.zshrc.map { ShellFile.isSourced(file, from: $0, home: .homeDirectory) } ?? false,
            setsItsOwnPrompt: shell?.zshrc.map {
                ShellFile.setsItsOwnPrompt(after: file, in: $0, home: .homeDirectory)
            } ?? false,
            known: known
        )
        if let prompt = choices?.prompt {
            draft = prompt
        }
    }

    func isOffered(_ setting: ShellSetting) -> Bool {
        guard let state, state.startupFile != nil, state.choices != nil else { return false }
        return state.known.map(setting.isKnown(by:)) == true
    }

    func isOffered(_ prompt: Prompt) -> Bool {
        guard let state, state.startupFile != nil, state.choices != nil else { return false }
        return state.known.map(prompt.isKnown(by:)) == true
    }

    func set(_ setting: ShellSetting, to isOn: Bool) {
        guard var choices = state?.choices else { return }
        if isOn {
            choices.settings.insert(setting)
        } else {
            choices.settings.remove(setting)
        }
        write(choices)
    }

    func setPrompt(_ prompt: Prompt?) {
        guard var choices = state?.choices else { return }
        if let prompt {
            draft = prompt
        }
        choices.prompt = prompt
        write(choices)
    }

    func turnAllOff() {
        write(ShellFile.Choices())
    }

    private func write(_ choices: ShellFile.Choices) {
        wasRefused = !ShellFile.write(choices, to: file)
        state?.choices = ShellFile.read(file)
    }
}
