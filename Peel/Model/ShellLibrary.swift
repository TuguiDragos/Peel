import Foundation
import Observation
import PeelCore

@Observable
final class ShellLibrary {
    struct State: Equatable {
        var shell: ShellSessions?
        var startupFile: URL?
        var choices: ShellFile.Choices?
        var isSourced: Bool
        var setsItsOwnPrompt: Bool
        /// What zsh answered when asked which prompt it shows, asked only while Peel's prompt is on and its line read.
        var shownPrompt: ShellSessions.ShownPrompt?
        var known: Set<String>?
    }

    let file: URL
    private let home: URL
    private(set) var state: State?
    private(set) var wasRefused = false
    private(set) var draft = Prompt()

    init(folder: URL = PeelFolder.url, home: URL = .homeDirectory) {
        file = ShellFile.url(in: folder)
        self.home = home
    }

    var line: String {
        ShellFile.line(sourcing: file, home: home)
    }

    var hasSomethingOn: Bool {
        state?.choices.map { !$0.settings.isEmpty || $0.prompt != nil } ?? false
    }

    func refresh() async {
        var known = state?.known
        if known == nil {
            known = await ShellFile.knownToZsh()
        }
        let shell = ShellSessions.inTerminal(TerminalSettings(), home: home)
        let startupFile = await shell?.zshrc(home: home)
        let choices = ShellFile.read(file)
        let isSourced = startupFile.map { ShellFile.isSourced(file, from: $0, home: home) } ?? false
        let shownPrompt: ShellSessions.ShownPrompt? = if choices?.prompt != nil, isSourced {
            await shell?.promptShown(home: home)
        } else {
            nil
        }
        state = State(
            shell: shell,
            startupFile: startupFile,
            choices: choices,
            isSourced: isSourced,
            setsItsOwnPrompt: startupFile.map { ShellFile.setsItsOwnPrompt(after: file, in: $0, home: home) } ?? false,
            shownPrompt: shownPrompt,
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

    /// Empties Peel's file, never one it could not read: what is in that one is not known.
    func turnAllOff() {
        guard state?.choices != nil else { return }
        write(ShellFile.Choices())
    }

    private func write(_ choices: ShellFile.Choices) {
        wasRefused = !ShellFile.write(choices, to: file)
        state?.choices = ShellFile.read(file)
    }
}
