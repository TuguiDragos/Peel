import Foundation
import Observation
import PeelCore

@Observable
final class ShellLibrary {
    let file = ShellFile.url(in: PeelFolder.url)
    private(set) var shell: ShellSessions?
    private(set) var choices: ShellFile.Choices?
    private(set) var isSourced = false
    private(set) var known: Set<String>?
    private(set) var wasRefused = false

    var startupFile: URL? {
        shell?.zshrc
    }

    var line: String {
        ShellFile.line(sourcing: file, home: .homeDirectory)
    }

    var hasSomethingOn: Bool {
        choices.map { !$0.settings.isEmpty || $0.prompt != .macOS } ?? false
    }

    func refresh() async {
        shell = ShellSessions.inTerminal(TerminalSettings())
        choices = ShellFile.read(file)
        isSourced = startupFile.map { ShellFile.isSourced(file, from: $0, home: .homeDirectory) } ?? false
        if known == nil {
            known = await ShellFile.knownToZsh()
        }
    }

    func isOffered(_ setting: ShellSetting) -> Bool {
        startupFile != nil && choices != nil && known.map(setting.isKnown(by:)) == true
    }

    func isOffered(_ prompt: PromptStyle) -> Bool {
        startupFile != nil && choices != nil && known.map(prompt.isKnown(by:)) == true
    }

    func set(_ setting: ShellSetting, to isOn: Bool) {
        guard var choices else { return }
        if isOn {
            choices.settings.insert(setting)
        } else {
            choices.settings.remove(setting)
        }
        write(choices)
    }

    func choose(_ prompt: PromptStyle) {
        guard var choices else { return }
        choices.prompt = prompt
        write(choices)
    }

    func turnAllOff() {
        write(ShellFile.Choices())
    }

    private func write(_ choices: ShellFile.Choices) {
        wasRefused = !ShellFile.write(choices, to: file)
        self.choices = ShellFile.read(file)
    }
}
