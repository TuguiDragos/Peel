import PeelCore
import SwiftUI

struct ShellTab: View {
    @Environment(ShellLibrary.self) private var shell
    @State private var isConfirmingTurnAllOff = false

    var body: some View {
        Form {
            if let state = shell.state {
                Section {
                    ShellLineRow(state: state)
                } footer: {
                    if shell.wasRefused {
                        StatusLabel(title: Text("macOS refused it"), tint: .accentColor)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if state.startupFile != nil {
                        Text("Takes effect in new windows")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                PromptSection(state: state)
                ForEach(ShellSetting.Group.allCases, id: \.self) { group in
                    Section {
                        ForEach(ShellSetting.allCases.filter { $0.group == group }, id: \.self) { setting in
                            TerminalSwitchRow(
                                title: setting.title,
                                detail: setting.detail,
                                footnote: setting.lines.joined(separator: "\n"),
                                isOn: Binding(
                                    get: { shell.state?.choices?.settings.contains(setting) == true },
                                    set: { shell.set(setting, to: $0) }
                                ),
                                isDisabled: !shell.isOffered(setting)
                            )
                        }
                    } header: {
                        Text(group.title)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .edgeBar(.bottom) {
            TurnAllOffBar(
                explanation: "Peel writes these to a file of its own, which zsh reads. Turning one off takes it out of that file, and your ~/.zshrc stays as it is.",
                isEnabled: shell.hasSomethingOn
            ) {
                isConfirmingTurnAllOff = true
            }
        }
        .alert("Turn off all shell settings?", isPresented: $isConfirmingTurnAllOff) {
            Button("Turn All Off") { shell.turnAllOff() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("New windows start with the prompt and settings macOS sets.")
        }
    }
}

private struct ShellLineRow: View {
    @Environment(ShellLibrary.self) private var shell
    let state: ShellLibrary.State

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let startupFile = state.startupFile {
                HStack(spacing: 5) {
                    if state.isSourced {
                        Label {
                            Text("zsh reads Peel’s settings")
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    } else {
                        Label {
                            Text("zsh doesn’t read Peel’s settings yet")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    InfoNote(
                        name: String(localized: "Peel’s settings file"),
                        detail: Text("Peel writes these settings only in a file of its own, which zsh reads through one line in \(startupFile.abbreviatedPath), so Peel never changes your own file. The command adds the line at the end. If you load tools such as fzf-tab there, move the line above them, since their settings have to come after Peel’s. Turn All Off empties Peel’s file, and the line then does nothing."),
                        footnote: Text(verbatim: shell.file.abbreviatedPath)
                    )
                }
                .font(.body.weight(.semibold))
                if state.isSourced {
                    Text("From \(startupFile.abbreviatedPath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    CopyableLines(
                        caption: Text("Run this once in Terminal to add Peel’s line to \(startupFile.abbreviatedPath). New windows then read the settings below."),
                        lines: [ShellFile.command(adding: shell.line, to: startupFile, home: .homeDirectory)]
                    )
                }
            } else if state.shell == .bash {
                Text("Terminal opens bash, so these zsh settings don’t apply.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Terminal opens a shell other than zsh, so these settings don’t apply.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PromptSection: View {
    @Environment(ShellLibrary.self) private var shell
    @Environment(TerminalLibrary.self) private var terminal
    let state: ShellLibrary.State

    var body: some View {
        let prompt = state.choices?.prompt
        let shown = prompt ?? shell.draft
        Section {
            PromptPreview(prompt: shown, theme: terminal.themeInUse)
                .opacity(prompt == nil ? 0.5 : 1)
                .padding(.vertical, 4)
            TerminalSwitchRow(
                title: "Use Peel’s prompt",
                detail: "The prompt is what zsh shows before each command you type. Peel writes the one you build here in its own file, in place of the one zsh shows now.",
                footnote: shown.lines.joined(separator: "\n"),
                isOn: Binding(
                    get: { shell.state?.choices?.prompt != nil },
                    set: { shell.setPrompt($0 ? shell.draft : nil) }
                ),
                isDisabled: !shell.isOffered(Prompt(showsBranch: false))
            )
            Picker(selection: part(\.start)) {
                ForEach(Prompt.Start.allCases, id: \.self) { start in
                    Text(start.title).tag(start)
                }
            } label: {
                partTitle("Before the symbol", isOn: prompt != nil)
            }
            .disabled(prompt == nil)
            TerminalSwitchRow(
                title: "Git branch",
                detail: "In a Git repository, the prompt shows the branch you’re on, as zsh’s own vcs_info reads it.",
                footnote: Prompt.branchLines.joined(separator: "\n"),
                isOn: part(\.showsBranch),
                isDisabled: prompt == nil || !shell.isOffered(Prompt(showsBranch: true))
            )
            Picker(selection: part(\.symbol)) {
                ForEach(Prompt.Symbol.allCases, id: \.self) { symbol in
                    Text(verbatim: symbol.rawValue).tag(symbol)
                }
            } label: {
                partTitle("Symbol", isOn: prompt != nil)
            }
            .pickerStyle(.segmented)
            .disabled(prompt == nil)
            TerminalSwitchRow(
                title: "Red after a failed command",
                detail: "The symbol turns red when the command before it failed, so a failure stands out.",
                footnote: nil,
                isOn: part(\.turnsRedAfterAFailure),
                isDisabled: prompt == nil
            )
            TerminalSwitchRow(
                title: "Command on its own line",
                detail: "The symbol starts a line of its own, so the command always has the whole width of the window.",
                footnote: nil,
                isOn: part(\.isOnItsOwnLine),
                isDisabled: prompt == nil
            )
        } header: {
            Text("Prompt")
        } footer: {
            if prompt != nil, !state.isSourced, let startupFile = state.startupFile {
                StatusLabel(
                    title: Text("zsh shows this prompt once Peel’s line is in \(startupFile.abbreviatedPath)."),
                    tint: .accentColor
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if prompt != nil, state.setsItsOwnPrompt, let startupFile = state.startupFile {
                StatusLabel(
                    title: Text("Your \(startupFile.abbreviatedPath) sets its own prompt after Peel’s line, so zsh shows that one."),
                    tint: .accentColor
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("The colors are the Terminal theme’s.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func partTitle(_ title: LocalizedStringResource, isOn: Bool) -> some View {
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(isOn ? .primary : .tertiary)
    }

    private func part<Value>(_ keyPath: WritableKeyPath<Prompt, Value>) -> Binding<Value> {
        Binding(
            get: { (shell.state?.choices?.prompt ?? shell.draft)[keyPath: keyPath] },
            set: { value in
                var prompt = shell.state?.choices?.prompt ?? shell.draft
                prompt[keyPath: keyPath] = value
                shell.setPrompt(prompt)
            }
        )
    }
}
