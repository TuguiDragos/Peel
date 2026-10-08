import PeelCore
import SwiftUI

struct SSHTab: View {
    @Environment(SSHLibrary.self) private var ssh
    @State private var isConfirmingTurnAllOff = false

    var body: some View {
        Form {
            if let state = ssh.state {
                Section {
                    SSHLinesRow(isIncluded: state.isIncluded)
                } footer: {
                    if ssh.wasRefused {
                        StatusLabel(title: Text("macOS refused it"), tint: .accentColor)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("What ~/.ssh/config sets earlier for a server stays in force, since ssh uses the first value it finds.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    ForEach(SSHSetting.allCases, id: \.self) { setting in
                        TerminalSwitchRow(
                            title: setting.title,
                            detail: setting.detail,
                            footnote: setting.lines.joined(separator: "\n"),
                            isOn: Binding(
                                get: { ssh.state?.settings?.contains(setting) == true },
                                set: { ssh.set(setting, to: $0) }
                            ),
                            isDisabled: !ssh.isOffered(setting)
                        )
                    }
                } header: {
                    Text("Connections")
                }
            }
        }
        .formStyle(.grouped)
        .edgeBar(.bottom) {
            TurnAllOffBar(
                explanation: "Peel writes these to a file of its own, which ssh reads. Turning one off takes it out of that file, and your ~/.ssh/config stays as it is.",
                isEnabled: ssh.hasSomethingOn
            ) {
                isConfirmingTurnAllOff = true
            }
        }
        .alert("Turn off all SSH settings?", isPresented: $isConfirmingTurnAllOff) {
            Button("Turn All Off") { ssh.turnAllOff() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("New connections use only what ~/.ssh/config sets.")
        }
    }
}

private struct SSHLinesRow: View {
    @Environment(SSHLibrary.self) private var ssh
    let isIncluded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if isIncluded {
                    Label {
                        Text("ssh reads Peel’s settings")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                } else {
                    Label {
                        Text("ssh doesn’t read Peel’s settings yet")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                InfoNote(
                    name: String(localized: "Peel’s settings file"),
                    detail: Text("Peel writes these settings only in a file of its own, which ssh reads through two lines at the end of ~/.ssh/config, so Peel never changes your own file. Turn All Off empties Peel’s file, and the lines then do nothing."),
                    footnote: Text(verbatim: ssh.lines.joined(separator: "\n"))
                )
            }
            .font(.body.weight(.semibold))
            if isIncluded {
                Text("From ~/.ssh/config")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                CopyableLines(
                    caption: Text("Run this once in Terminal to add Peel’s lines at the end of ~/.ssh/config, after what you set for each server."),
                    lines: [SSHFile.command(adding: ssh.lines, to: ssh.config, home: .homeDirectory)]
                )
            }
        }
        .padding(.vertical, 4)
    }
}
