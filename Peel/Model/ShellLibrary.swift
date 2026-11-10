import Foundation
import Observation
import PeelCore

@Observable
final class ShellLibrary {
    struct State: Equatable {
        var shell: ShellSessions?
        var startupFile: URL?
        var choices: ShellFile.Choices?
        /// Why Peel's file can't be read, while `choices` is nil, when Peel knows.
        var whyUnreadable: FileProblem?
        var isSourced: Bool
        var setsItsOwnPrompt: Bool
        /// What zsh answered when asked which prompt it shows, asked only while Peel's prompt is on and its line read.
        var shownPrompt: ShellSessions.ShownPrompt?
        /// Peel's prompt when zsh was asked, which its answer is about.
        var promptAskedAbout: String?
        var known: Set<String>?
    }

    private struct ZshAnswer {
        let shell: ShellSessions
        let startupFile: URL
        let shownPrompt: ShellSessions.ShownPrompt?
        let promptAskedAbout: String?
    }

    let file: URL
    private let home: URL
    private let terminal: any TerminalSettingsStoring
    private(set) var state: State?
    /// Why Peel's file couldn't be saved, until the page forgets it.
    private(set) var whyRefused: FileProblem?
    private(set) var draft = Prompt()
    private(set) var isAskingZsh = false
    private(set) var zshDidNotAnswer = false
    private var zshAnswer: ZshAnswer?
    private var answersForgotten = 0

    init(
        folder: URL = PeelFolder.url,
        home: URL = .homeDirectory,
        terminal: any TerminalSettingsStoring = TerminalSettings()
    ) {
        file = ShellFile.url(in: folder)
        self.home = home
        self.terminal = terminal
    }

    var line: String {
        ShellFile.line(sourcing: file, home: home)
    }

    var hasSomethingOn: Bool {
        state?.choices.map { !$0.settings.isEmpty || $0.prompt != nil } ?? false
    }

    /// Runs none of the startup files: only `askZsh()` starts zsh with them.
    func refresh() async {
        var known = state?.known
        if known == nil {
            known = await ShellFile.knownToZsh()
        }
        // A reading stopped because the page went away got no answer from zsh, which isn't zsh not answering.
        guard !Task.isCancelled else { return }
        let shell = ShellSessions.inTerminal(terminal, home: home)
        let answer = zshAnswer.flatMap { $0.shell == shell ? $0 : nil }
        show(shell, startupFile: answer?.startupFile ?? shell?.zshrcByTheText(home: home), answer: answer, known: known)
    }

    func askZsh() async {
        guard !isAskingZsh, let shell = ShellSessions.inTerminal(terminal, home: home) else { return }
        isAskingZsh = true
        defer { isAskingZsh = false }
        let forgotten = answersForgotten
        let known = if let known = state?.known { known } else { await ShellFile.knownToZsh() }
        let startupFile = await shell.zshrc(home: home)
        let isSourced = startupFile.map { ShellFile.isSourced(file, from: $0, home: home) } ?? false
        let peels = isSourced ? ShellFile.read(file)?.prompt?.value : nil
        let shownPrompt: ShellSessions.ShownPrompt? = if peels != nil {
            await shell.promptShown(home: home)
        } else {
            nil
        }
        guard !Task.isCancelled, forgotten == answersForgotten else { return }
        let promptAskedAbout = shownPrompt == nil ? nil : peels
        zshAnswer = startupFile.map {
            ZshAnswer(shell: shell, startupFile: $0, shownPrompt: shownPrompt, promptAskedAbout: promptAskedAbout)
        }
        zshDidNotAnswer = startupFile == nil
        show(shell, startupFile: startupFile ?? shell.zshrcByTheText(home: home), answer: zshAnswer, known: known)
    }

    func forgetZshAnswer() {
        zshAnswer = nil
        zshDidNotAnswer = false
        answersForgotten += 1
    }

    private func show(_ shell: ShellSessions?, startupFile: URL?, answer: ZshAnswer?, known: Set<String>?) {
        let isSourced = startupFile.map { ShellFile.isSourced(file, from: $0, home: home) } ?? false
        // Read after zsh answered, which takes as long as the person's startup files: a switch can change it meanwhile.
        let choices = ShellFile.read(file)
        state = State(
            shell: shell,
            startupFile: startupFile,
            choices: choices,
            whyUnreadable: choices == nil ? ShellFile.whyUnreadable(file) : nil,
            isSourced: isSourced,
            setsItsOwnPrompt: startupFile.map { ShellFile.setsItsOwnPrompt(after: file, in: $0, home: home) } ?? false,
            shownPrompt: answer?.shownPrompt,
            promptAskedAbout: answer?.promptAskedAbout,
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

    func forgetRefusal() {
        whyRefused = nil
    }

    private func write(_ choices: ShellFile.Choices) {
        whyRefused = ShellFile.write(choices, to: file)
        let written = ShellFile.read(file)
        state?.choices = written
        state?.whyUnreadable = written == nil ? ShellFile.whyUnreadable(file) : nil
    }
}
