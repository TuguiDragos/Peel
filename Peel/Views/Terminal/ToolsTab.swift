import PeelCore
import SwiftUI

struct ToolsTab: View {
    @Environment(TerminalToolLibrary.self) private var tools

    var body: some View {
        Form {
            if let state = tools.state {
                if state.prefix == nil {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Text("Install Homebrew first")
                                    .font(.body.weight(.semibold))
                                Link(destination: Homebrew.website) { Text(verbatim: "brew.sh") }
                                    .font(.caption)
                            }
                            CopyableLines(
                                caption: Text("These tools install with Homebrew. Run this in Terminal: its script says what it will do and waits before doing it."),
                                lines: [Homebrew.installCommand]
                            )
                        }
                        .padding(.vertical, 4)
                    }
                }
                ForEach(TerminalTool.Group.allCases, id: \.self) { group in
                    Section {
                        ForEach(TerminalTool.allCases.filter { $0.group == group }, id: \.self) { tool in
                            TerminalToolRow(tool: tool, state: state)
                        }
                    } header: {
                        Text(group.title)
                    } footer: {
                        if group == .shell {
                            Text("Their lines go in ~/.zshrc in the order they are listed here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct TerminalToolRow: View {
    @Environment(TerminalToolLibrary.self) private var tools
    let tool: TerminalTool
    let state: TerminalToolLibrary.State

    var body: some View {
        let isInstalled = state.installed.contains(tool)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(verbatim: tool.name)
                    .font(.body.weight(.semibold))
                InfoNote(
                    name: tool.name,
                    detail: Text(tool.detail),
                    footnote: Text((try? AttributedString(markdown: "[\(tool.project.host() ?? "")\(tool.project.path())](\(tool.project.absoluteString))")) ?? AttributedString(tool.project.absoluteString))
                )
                Spacer(minLength: 8)
                if isInstalled {
                    Label {
                        Text("Installed")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Text(tool.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            switch tools.availability(of: tool) {
            case .unknownToHomebrew:
                StatusLabel(title: Text("Homebrew no longer offers it."), tint: .accentColor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .retired(let retirement):
                StatusLabel(title: retirement.title, tint: .accentColor)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                retirement.explanation(now: .now)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .available:
                let setups = tool.setup(prefix: state.prefix ?? Self.defaultPrefix)
                if !isInstalled || !setups.isEmpty {
                    let title: LocalizedStringKey =
                        if isInstalled { "Set up" } else if setups.isEmpty { "Install" } else { "Install and set up" }
                    DisclosureGroup(title) {
                        VStack(alignment: .leading, spacing: 6) {
                            if !isInstalled {
                                CopyableLines(caption: setups.isEmpty ? nil : Text("Install"), lines: [tool.installCommand])
                            }
                            ForEach(setups, id: \.lines) { setup in
                                CopyableLines(caption: Text(setup.place.caption), lines: setup.lines)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .disclosureGroupStyle(ButtonDisclosureStyle())
                }
            }
        }
        .padding(.vertical, 4)
    }

    #if arch(arm64)
    private static let defaultPrefix = URL(filePath: "/opt/homebrew", directoryHint: .isDirectory)
    #else
    private static let defaultPrefix = URL(filePath: "/usr/local", directoryHint: .isDirectory)
    #endif
}
