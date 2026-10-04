import AppKit
import PeelCore
import SwiftUI

struct SSHTab: View {
    @Environment(SSHLibrary.self) private var ssh
    @State private var isConfirmingTurnAllOff = false

    var body: some View {
        Form {
            Section {
                SSHLinesRow()
            } footer: {
                if ssh.wasRefused {
                    Label("macOS refused it", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
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
                            get: { ssh.settings?.contains(setting) == true },
                            set: { ssh.set(setting, to: $0) }
                        ),
                        isDisabled: !ssh.isOffered(setting)
                    )
                }
            } header: {
                Text("Connections")
            }
        }
        .formStyle(.grouped)
        .safeAreaBar(edge: .bottom) {
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
        .task {
            await ssh.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await ssh.refresh() }
        }
    }
}

private struct SSHLinesRow: View {
    @Environment(SSHLibrary.self) private var ssh

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if ssh.isIncluded {
                    Label {
                        Text("ssh reads Peel’s settings")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                } else {
                    Text("Add Peel’s lines to ~/.ssh/config")
                }
                InfoNote(
                    name: String(localized: "Peel’s settings file"),
                    detail: Text("Peel writes these settings only in a file of its own, which ssh reads through two lines at the end of ~/.ssh/config, so Peel never changes your own file. Turn All Off empties Peel’s file, and the lines then do nothing."),
                    footnote: Text(verbatim: ssh.lines.joined(separator: "\n"))
                )
            }
            .font(.body.weight(.semibold))
            if ssh.isIncluded {
                Text("From ~/.ssh/config")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                CopyableLines(
                    caption: Text("Run this once in Terminal. It adds them at the end, after what you set for each server."),
                    lines: [SSHFile.command(adding: ssh.lines, to: ssh.config, home: .homeDirectory)]
                )
            }
        }
        .padding(.vertical, 4)
    }
}
