import AppKit
import PeelCore
import SwiftUI

struct ToolsTab: View {
    @Environment(TerminalToolLibrary.self) private var tools

    var body: some View {
        Form {
            if tools.hasLooked, tools.prefix == nil {
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
                        TerminalToolRow(tool: tool)
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
        .formStyle(.grouped)
        .task {
            await tools.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await tools.refresh() }
        }
    }
}

private struct TerminalToolRow: View {
    @Environment(TerminalToolLibrary.self) private var tools
    let tool: TerminalTool

    var body: some View {
        let isInstalled = tools.installed.contains(tool)
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
                Text("Homebrew no longer offers it.")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            case .retired(let retirement):
                retirement.title
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                retirement.explanation(now: .now)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .available:
                if !isInstalled {
                    CopyableLines(caption: Text("Install"), lines: [tool.installCommand])
                }
                ForEach(tool.setup(prefix: tools.prefix ?? Self.defaultPrefix), id: \.lines) { setup in
                    CopyableLines(caption: Text(setup.place.caption), lines: setup.lines)
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
