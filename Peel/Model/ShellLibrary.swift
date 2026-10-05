import Foundation
import Observation
import PeelCore

@Observable
final class ShellLibrary {
    struct State: Equatable {
        var shell: ShellSessions?
        var choices: ShellFile.Choices?
        var isSourced: Bool
        var known: Set<String>?

        var startupFile: URL? {
            shell?.zshrc
        }
    }

    let file = ShellFile.url(in: PeelFolder.url)
    private(set) var state: State?
    private(set) var wasRefused = false

    var line: String {
        ShellFile.line(sourcing: file, home: .homeDirectory)
    }

    var hasSomethingOn: Bool {
        state?.choices.map { !$0.settings.isEmpty || $0.prompt != .macOS } ?? false
    }

    func refresh() async {
        var known = state?.known
        if known == nil {
            known = await ShellFile.knownToZsh()
        }
        let shell = ShellSessions.inTerminal(TerminalSettings())
        state = State(
            shell: shell,
            choices: ShellFile.read(file),
            isSourced: shell?.zshrc.map { ShellFile.isSourced(file, from: $0, home: .homeDirectory) } ?? false,
            known: known
        )
    }

    func isOffered(_ setting: ShellSetting) -> Bool {
        guard let state, state.startupFile != nil, state.choices != nil else { return false }
        return state.known.map(setting.isKnown(by:)) == true
    }

    func isOffered(_ prompt: PromptStyle) -> Bool {
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

    func choose(_ prompt: PromptStyle) {
        guard var choices = state?.choices else { return }
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
