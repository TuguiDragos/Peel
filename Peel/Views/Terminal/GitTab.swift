import AppKit
import PeelCore
import SwiftUI

struct GitTab: View {
    @Environment(GitLibrary.self) private var git
    @State private var isConfirmingTurnAllOff = false

    var body: some View {
        Form {
            if git.hasLooked, git.git == nil {
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
            } else if git.hasLooked, git.settings == nil {
                Section {
                    Label("Git couldn’t read its settings", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.accentColor)
                }
            } else if git.wasRefused {
                Section {
                    Label("Git refused it", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.accentColor)
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
        .formStyle(.grouped)
        .safeAreaBar(edge: .bottom) {
            TurnAllOffBar(
                explanation: "Peel changes these with `git config --global`. Turning one off puts back what was there before Peel, or leaves it to Git.",
                isEnabled: git.hasSomethingOn && !git.isWorking
            ) {
                isConfirmingTurnAllOff = true
            }
        }
        .alert("Turn off all Git settings?", isPresented: $isConfirmingTurnAllOff) {
            Button("Turn All Off") { Task { await git.turnAllOff() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Settings Peel changed go back to what they were, and the rest go back to Git’s defaults.")
        }
        .task {
            await git.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await git.refresh() }
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
            footnote: setting.values(signingKey: git.signingKey ?? "~/.ssh/id_ed25519.pub")
                .map { "git config --global \($0.key) \($0.value)" }
                .joined(separator: "\n"),
            caption: caption,
            isOn: Binding(
                get: { git.isOn(setting) },
                set: { isOn in Task { await git.set(setting, to: isOn) } }
            ),
            isDisabled: !git.isOffered(setting) || git.isWorking
        )
    }

    private var caption: LocalizedStringResource? {
        guard setting == .signCommits else { return nil }
        guard let key = git.signingKey else { return "Needs an SSH key in ~/.ssh" }
        return "With \(URL(filePath: key).abbreviatedPath)"
    }
}
