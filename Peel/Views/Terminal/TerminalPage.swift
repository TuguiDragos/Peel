import AppKit
import PeelCore
import SwiftUI

struct TerminalPage: View {
    @Environment(TerminalLibrary.self) private var terminal
    @Environment(TweakLibrary.self) private var tweaks
    @Environment(RemovalHistoryStore.self) private var history
    @State private var showsWindowSwitch = false

    var body: some View {
        TabView {
            Tab("Themes", systemImage: "paintpalette") {
                Form {
                    Section("In Use") {
                        TerminalThemeInUse()
                    }
                    Section {
                        TerminalThemeGrid()
                    }
                }
                .formStyle(.grouped)
            }
            Tab("Settings", systemImage: "gearshape") {
                TerminalSettingsForm(showsWindowSwitch: showsWindowSwitch)
            }
        }
        .navigationTitle(Text(Tool.terminal.title))
        .task {
            terminal.refresh()
            tweaks.refresh()
            showsWindowSwitch = TerminalWindows.switchMatters()
        }
        .onDisappear {
            tweaks.forgetRefusals()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            terminal.refresh()
            tweaks.refresh()
            showsWindowSwitch = TerminalWindows.switchMatters()
        }
        .onChange(of: history.revision) {
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

private struct TerminalSettingsForm: View {
    @Environment(TerminalLibrary.self) private var terminal
    let showsWindowSwitch: Bool

    var body: some View {
        Form {
            Section("When Terminal Opens") {
                if terminal.quietsLogin {
                    RemovalsHeldBanner()
                }
                QuietLoginRow()
                if let sessions = terminal.shellSessions {
                    ShellSessionsRow(sessions: sessions)
                }
                if showsWindowSwitch {
                    TweakRow(tweak: TweakCatalog.terminalWindows)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct QuietLoginRow: View {
    @Environment(TerminalLibrary.self) private var terminal
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(RemovalOutcome.self) private var outcome
    @Environment(ExclusionsStore.self) private var exclusions
    @State private var asked: Bool?

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text("No “Last login” line")
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    InfoNote(
                        name: String(localized: "No “Last login” line"),
                        detail: Text("New Terminal windows start at the prompt, without the line that says when you last logged in. Logins to this Mac over SSH leave it out too."),
                        footnote: Text(verbatim: HushLogin.url(in: .homeDirectory).abbreviatedPath)
                    )
                }
                Text("Takes effect in new windows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Toggle(isOn: isOn) { EmptyView() }
                .labelsHidden()
                .accessibilityRepresentation {
                    Toggle(isOn: isOn) { Text("No “Last login” line") }
                }
                .disabled(terminal.isMovingQuietLogin || terminal.quietsLogin && !canMoveToTrash)
        }
        .padding(.vertical, 4)
    }

    private var canMoveToTrash: Bool {
        exclusions.exclusions.isKnown && !history.isUnreadable
    }

    private var isOn: Binding<Bool> {
        Binding(
            get: { asked ?? terminal.quietsLogin },
            set: { on in
                guard !on else {
                    terminal.turnOnQuietLogin()
                    return
                }
                asked = false
                Task {
                    let result = await terminal.moveQuietLoginToTrash { result, sizes in
                        await history.record(result, tool: .terminal, source: "Terminal", sourceKey: "tool", sizes: sizes)
                    }
                    asked = nil
                    outcome.report(result)
                }
            }
        )
    }
}

private struct ShellSessionsRow: View {
    let sessions: ShellSessions

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text("No “Restored session” line")
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    InfoNote(
                        name: String(localized: "No “Restored session” line"),
                        detail: Text("When Terminal reopens a window, \(sessions.name) starts it with a “Restored session” line and gives it back its own command history. For that, every shell saves its session as it ends, with a “Saving session” line, and keeps it for two weeks. Peel doesn’t change your shell’s files."),
                        footnote: Text(verbatim: sessions.script)
                    )
                }
                Group {
                    switch sessions {
                    case .zsh(let startupFile): Text("Add this line to \(startupFile.abbreviatedPath)")
                    case .bash: Text("Run this command in Terminal")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(verbatim: sessions.turnOff)
                    .font(.subheadline.monospaced())
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            CopyButton(text: sessions.turnOff)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}
