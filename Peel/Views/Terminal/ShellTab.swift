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
                        Label("macOS refused it", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    } else if state.startupFile != nil {
                        Text("Takes effect in new windows")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    let width = PromptSample.width(of: PromptStyle.allCases)
                    ForEach(PromptStyle.allCases, id: \.self) { style in
                        PromptRow(style: style, sampleWidth: width)
                    }
                } header: {
                    Text("Prompt")
                } footer: {
                    Text("The colors are the Terminal theme’s, and the arrow turns red after a command fails.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        .safeAreaBar(edge: .bottom) {
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
                        Text("Add Peel’s line to \(startupFile.abbreviatedPath)")
                    }
                    InfoNote(
                        name: String(localized: "Peel’s settings file"),
                        detail: Text("Peel writes these settings only in a file of its own, which zsh reads through one line in \(startupFile.abbreviatedPath), so Peel never changes your own file. Put the line above the lines that load other tools. Turn All Off empties Peel’s file, and the line then does nothing."),
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
                        caption: Text("Run this once in Terminal, and new windows read the settings below."),
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

private struct PromptRow: View {
    @Environment(ShellLibrary.self) private var shell
    @Environment(TerminalLibrary.self) private var terminal
    let style: PromptStyle
    let sampleWidth: CGFloat

    var body: some View {
        let isChosen = shell.state?.choices?.prompt == style
        Button {
            shell.choose(style)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(isChosen ? 1 : 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.title)
                        .font(.body.weight(.semibold))
                    Text(style.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                PromptSample(style: style, theme: terminal.themeInUse, width: sampleWidth)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!shell.isOffered(style))
        .accessibilityLabel(Text(style.title))
        .accessibilityHint(Text(style.detail))
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .padding(.vertical, 2)
    }
}
