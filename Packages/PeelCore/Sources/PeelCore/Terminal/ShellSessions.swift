public import Foundation

public enum ShellSessions: Sendable, Equatable {
    case zsh(startupFile: URL)
    case bash

    public static func inTerminal(_ terminal: TerminalSettings, home: URL = .homeDirectory) -> ShellSessions? {
        of(terminalSetting: terminal.shell(), loginShell: loginShell(), zdotdir: ProcessInfo.processInfo.environment["ZDOTDIR"], home: home)
    }

    static func of(terminalSetting: String?, loginShell: String?, zdotdir: String?, home: URL) -> ShellSessions? {
        let shell = terminalSetting.flatMap { $0.isEmpty ? nil : $0 } ?? loginShell
        switch shell.map({ String(URL(filePath: $0).lastPathComponent.prefix { $0 != " " }) }) {
        case "zsh"?:
            let folder = zdotdir.flatMap { $0.isEmpty ? nil : URL(filePath: $0, directoryHint: .isDirectory) } ?? home
            return .zsh(startupFile: folder.appending(path: ".zshenv", directoryHint: .notDirectory))
        case "bash"?:
            return .bash
        default:
            return nil
        }
    }

    /// The `.zshrc` beside the `.zshenv` zsh reads, where the line that sources Peel's file goes.
    public var zshrc: URL? {
        guard case .zsh(let zshenv) = self else { return nil }
        return zshenv.deletingLastPathComponent().appending(path: ".zshrc", directoryHint: .notDirectory)
    }

    public var name: String {
        switch self {
        case .zsh: "zsh"
        case .bash: "bash"
        }
    }

    public var turnOff: String {
        switch self {
        case .zsh: "SHELL_SESSIONS_DISABLE=1"
        case .bash: "touch ~/.bash_sessions_disable"
        }
    }

    public var script: String {
        "/etc/\(name)rc_Apple_Terminal"
    }

    static func loginShell(of user: uid_t = getuid()) -> String? {
        var capacity = 1_024
        while capacity <= 65_536 {
            var entry = passwd()
            var found: UnsafeMutablePointer<passwd>?
            var buffer = [CChar](repeating: 0, count: capacity)
            let (result, shell) = buffer.withUnsafeMutableBufferPointer { bytes -> (Int32, String?) in
                let result = getpwuid_r(user, &entry, bytes.baseAddress, bytes.count, &found)
                guard result == 0, found != nil, let shell = entry.pw_shell else { return (result, nil) }
                return (result, String(cString: shell))
            }
            if result == 0 { return shell }
            guard result == ERANGE else { return nil }
            capacity *= 4
        }
        return nil
    }
}
