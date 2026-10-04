import AppKit
import PeelCore
import SwiftUI

struct TerminalPage: View {
    @Environment(TerminalLibrary.self) private var terminal

    var body: some View {
        Form {
            Section("In Use") {
                TerminalThemeInUse()
            }
            Section("Themes") {
                TerminalThemeGrid()
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text(Tool.terminal.title))
        .task {
            terminal.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            terminal.refresh()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            terminal.refresh()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            terminal.refresh()
        }
        .alert("Quit Terminal first?", isPresented: isWaitingForTerminal, presenting: terminal.waitingForTerminal) { action in
            Button("Quit Terminal") {
                Task { await terminal.quitTerminal(andThen: action) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("While Terminal is open, it doesn’t see a new theme, and can undo it the next time it saves its settings.")
        }
        .alert("Terminal didn’t quit.", isPresented: Bindable(terminal).terminalDidNotQuit) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("It may be asking whether to stop a command that is still running.")
        }
    }

    private var isWaitingForTerminal: Binding<Bool> {
        Binding(
            get: { terminal.waitingForTerminal != nil },
            set: { if !$0 { terminal.waitingForTerminal = nil } }
        )
    }
}

private struct TerminalThemeInUse: View {
    @Environment(TerminalLibrary.self) private var terminal

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 18) {
                preview
                    .frame(width: 300)
                words
            }
            VStack(alignment: .leading, spacing: 14) {
                preview
                words
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var preview: some View {
        if let theme = terminal.themeInUse {
            TerminalSession(theme: theme)
        } else {
            Image(systemName: "terminal")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(.quaternary, in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: terminal.themeInUse?.name ?? terminal.profileInUse ?? String(localized: Tool.terminal.title))
                .font(.title3.weight(.semibold))
            Text(terminal.themeInUse == nil
                 ? "Choose a theme below, and Terminal opens with it."
                 : "Terminal opens with this theme, and every new window uses it.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 8) {
                Button(terminal.isTerminalOpen ? "Open a New Window" : "Open Terminal") {
                    terminal.openTerminal()
                }
                if terminal.canPutBack {
                    Button("Put Back") {
                        terminal.perform(.putBack)
                    }
                    .transition(.opacity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(terminal.isQuittingTerminal)
            .padding(.top, 4)
            if terminal.problem == .managed {
                Label("Locked by a profile", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            } else if terminal.problem == .refused {
                Label("macOS refused it", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .motion(value: terminal.canPutBack)
    }
}

private struct TerminalThemeGrid: View {
    @Environment(TerminalLibrary.self) private var terminal

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 14)], spacing: 16) {
            ForEach(TerminalThemeCatalog.all) { theme in
                let isInUse = terminal.themeInUse == theme
                Button {
                    terminal.perform(.use(theme))
                } label: {
                    TerminalThemeCard(theme: theme, isInUse: isInUse)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: theme.name))
                .accessibilityAddTraits(isInUse ? .isSelected : [])
            }
        }
        .disabled(terminal.isQuittingTerminal)
        .padding(.vertical, 8)
    }
}
