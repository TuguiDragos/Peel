import Foundation
@testable import PeelCore
import PeelPrivileged
import Testing

struct ShellSessionsTests {
    private let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)

    private func sessions(setting: String?, login: String?, zdotdir: String? = nil) -> ShellSessions? {
        ShellSessions.of(terminalSetting: setting, loginShell: login, zdotdir: zdotdir, home: home)
    }

    @Test func terminalOpensTheShellItsSettingNamesOrElseTheAccountsLoginShell() {
        let zsh = ShellSessions.zsh(startupFile: home.appending(path: ".zshenv", directoryHint: .notDirectory))
        #expect(sessions(setting: nil, login: "/bin/zsh") == zsh)
        #expect(sessions(setting: "", login: "/bin/zsh") == zsh)
        #expect(sessions(setting: "/bin/bash", login: "/bin/zsh") == .bash)
        #expect(sessions(setting: "", login: "/bin/bash") == .bash)
        #expect(sessions(setting: "/opt/homebrew/bin/zsh -l", login: "/bin/bash") == zsh)
        #expect(sessions(setting: "/opt/homebrew/bin/fish", login: "/bin/zsh") == nil)
        #expect(sessions(setting: nil, login: "/bin/tcsh") == nil)
        #expect(sessions(setting: nil, login: nil) == nil)
    }

    @Test func zshReadsItsStartupFileFromZdotdirWhenThatIsSet() {
        #expect(sessions(setting: nil, login: "/bin/zsh", zdotdir: "/Users/someone/.config/zsh")
            == .zsh(startupFile: URL(filePath: "/Users/someone/.config/zsh/.zshenv", directoryHint: .notDirectory)))
        #expect(sessions(setting: nil, login: "/bin/zsh", zdotdir: "")
            == .zsh(startupFile: home.appending(path: ".zshenv", directoryHint: .notDirectory)))
    }

    @Test func turnsSessionsOffTheWayTheScriptsOfThisMacRead() throws {
        let zshrc = try String(contentsOfFile: "/etc/zshrc", encoding: .utf8)
        #expect(zshrc.contains(#". "/etc/zshrc_$TERM_PROGRAM""#))
        let zsh = ShellSessions.zsh(startupFile: home)
        let zshScript = try String(contentsOfFile: zsh.script, encoding: .utf8)
        #expect(zshScript.contains("[ ${SHELL_SESSIONS_DISABLE:-0} -eq 0 ]"))
        #expect(zsh.turnOff == "SHELL_SESSIONS_DISABLE=1")

        let bashrc = try String(contentsOfFile: "/etc/bashrc", encoding: .utf8)
        #expect(bashrc.contains(#". "/etc/bashrc_$TERM_PROGRAM""#))
        let bashScript = try String(contentsOfFile: ShellSessions.bash.script, encoding: .utf8)
        #expect(bashScript.contains(#"[ ! -e "$HOME/.bash_sessions_disable" ]"#))
        #expect(ShellSessions.bash.turnOff == "touch ~/.bash_sessions_disable")
    }

    @Test func readsTheLoginShellTheAccountRecordHolds() async throws {
        guard case .success(let output) = await Subprocess.run("/usr/bin/dscl", [".", "-read", "/Users/\(NSUserName())", "UserShell"], timeout: 10) else {
            Issue.record("dscl did not answer")
            return
        }
        let recorded = output.text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "UserShell: ", with: "")
        #expect(ShellSessions.loginShell() == recorded)
    }

    @Test func readsTerminalsShellSettingAsDefaultsDoes() async {
        let setting = TerminalSettings().shell()
        guard
            case .success(let output) = await Subprocess.run(
                "/usr/bin/defaults",
                ["read", TerminalSettings.identifier, "Shell"],
                timeout: 10
            ), output.status == 0
        else {
            #expect(setting == nil)
            return
        }
        #expect(setting == String(output.text.dropLast()))
    }
}
