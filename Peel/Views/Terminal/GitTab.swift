import PeelCore
import SwiftUI

struct GitTab: View {
    @Environment(GitLibrary.self) private var git
    @State private var isConfirmingTurnAllOff = false

    static let turningOneOff: LocalizedStringResource = "Peel changes these with `git config --global`. Turning one off puts back what was there before Peel, or removes it when you had set it yourself."

    static let settingsUnreadable: LocalizedStringResource = "Git couldn’t read your settings, so Peel changes nothing here. Run `git config --global --list` in Terminal to see what Git says."

    static let afterTurningAllOff: LocalizedStringResource = "Settings Peel changed go back to what they were. Settings you made yourself that are on here are removed from your Git settings, so Git’s defaults apply."

    var body: some View {
        Form {
            if let state = git.state {
                if !state.isInstalled {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Git isn’t installed")
                                .font(.body.weight(.semibold))
                            CopyableLines(
                                caption: Text("Run this in Terminal to install Apple’s command line developer tools, which include Git."),
                                lines: ["xcode-select --install"]
                            )
                        }
                        .padding(.vertical, 4)
                    }
                } else if state.settings == nil {
                    Section {
                        StatusLabel(title: Text(Self.settingsUnreadable), tint: .accentColor)
                    }
                } else if state.known == nil {
                    Section {
                        StatusLabel(title: Text(TerminalPage.didNotAnswer("Git")), tint: .accentColor)
                    }
                } else if git.wasRefused {
                    Section {
                        StatusLabel(title: Text(verbatim: git.whyRefused.sentence), tint: .accentColor)
                    }
                }
                ForEach(GitSetting.Group.allCases, id: \.self) { group in
                    Section {
                        ForEach(GitSetting.allCases.filter { $0.group == group }, id: \.self) { setting in
                            GitSettingRow(setting: setting)
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
                explanation: Self.turningOneOff,
                isEnabled: git.hasSomethingOn
            ) {
                isConfirmingTurnAllOff = true
            }
        }
        .alert("Turn off all Git settings?", isPresented: $isConfirmingTurnAllOff) {
            Button("Turn All Off") { git.turnAllOff() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.afterTurningAllOff)
        }
    }
}

private struct GitSettingRow: View {
    @Environment(GitLibrary.self) private var git
    let setting: GitSetting

    var body: some View {
        TerminalSwitchRow(
            title: setting.title,
            detail: setting.detail,
            footnote: setting.commands(signingKey: git.state?.signingKey ?? "~/.ssh/id_ed25519.pub")
                .joined(separator: "\n"),
            caption: caption,
            isOn: Binding(
                get: { git.isOn(setting) },
                set: { git.set(setting, to: $0) }
            ),
            isDisabled: !git.isOffered(setting)
        )
    }

    private var caption: LocalizedStringResource? {
        if git.isSetInIncludedFiles(setting) { return "Set in a file your Git settings include" }
        guard setting == .signCommits else { return nil }
        guard let key = git.state?.signingKey else { return "Needs an SSH key in ~/.ssh" }
        return GitSetting.isTheKeyItself(key)
            ? "With the key written in your Git settings"
            : "With \(URL(filePath: key).abbreviatedPath)"
    }
}
