import Foundation
@testable import PeelCore
import PeelPrivileged
import Testing

struct ShellSessionsTests {
    @Test func aZDOTDIRSetWhereALoginShellReadsItMovesTheZshrc() async throws {
        let directory = try TemporaryDirectory()
        let home = try directory.directory("home")
        try directory.file(
            "home/.zprofile", contents: Data("export ZDOTDIR=\"$HOME/.config/zsh\"\nprint \"said at login\"\n".utf8)
        )
        let zsh = ShellSessions.zsh(startupFile: home.appending(path: ".zshenv"))

        let zshrc = await zsh.zshrc(home: home, zdotdir: nil)

        #expect(zshrc?.path(percentEncoded: false).hasSuffix("home/.config/zsh/.zshrc") == true)
    }

    /// The startup files are the account's own, so the shell that runs them must not reach what was given to Peel.
    @Test(arguments: [false, true])
    func theShellThatRunsTheStartupFilesAnswersForItself(isInteractive: Bool) async throws {
        let system = try #require(Subprocess.Responsibility.system)
        let directory = try TemporaryDirectory()
        let home = try directory.directory("home")
        let started = directory.url.appending(path: "started")
        let goOn = directory.url.appending(path: "go-on")
        try directory.file("home/.zshenv", contents: Data("""
            print -r -- $$ > \(started.path(percentEncoded: false).quotedForTheShell).new
            /bin/mv \(started.path(percentEncoded: false).quotedForTheShell).new \(started.path(percentEncoded: false).quotedForTheShell)
            while [[ ! -e \(goOn.path(percentEncoded: false).quotedForTheShell) ]]; do /bin/sleep 0.05; done

            """.utf8))
        let zsh = ShellSessions.zsh(startupFile: home.appending(path: ".zshenv"))
        let start = try ProgramStart(in: directory.url, started: started, goOn: goOn, system: system)
        async let answered: Void = {
            if isInteractive {
                _ = await zsh.promptShown(home: home, zdotdir: nil)
            } else {
                _ = await zsh.zshrc(home: home, zdotdir: nil)
            }
            start.runEnded()
        }()

        let answer = await start.answer
        await answered

        #expect(answer != nil, "zsh ended before it named itself")
        #expect(answer.map { $0.responsible == $0.pid } == true)
    }

    @Test func whenZshCannotBeStartedOnItsOwnTheStartupFilesTextNamesTheFolderAndNothingRuns() async throws {
        let directory = try TemporaryDirectory()
        let home = try directory.directory("home")
        let ran = directory.url.appending(path: "ran")
        try directory.file("home/.zshenv", contents: Data("""
            export ZDOTDIR="$HOME/.config/zsh"
            /usr/bin/touch \(ran.path(percentEncoded: false).quotedForTheShell)

            """.utf8))
        let zsh = ShellSessions.zsh(startupFile: home.appending(path: ".zshenv"))

        let zshrc = await zsh.zshrc(home: home, zdotdir: nil, asking: nil)
        let shown = await zsh.promptShown(home: home, zdotdir: nil, asking: nil)

        #expect(zshrc == nil)
        #expect(shown == nil)
        #expect(zsh.zshrcByTheText(home: home, zdotdir: nil)?.path(percentEncoded: false)
            .hasSuffix("home/.config/zsh/.zshrc") == true)
        #expect(ran.isMissing)
    }

    @Test func theStartupFilesTextNamesTheZshrcAndRunsNothing() throws {
        let directory = try TemporaryDirectory()
        let home = try directory.directory("home")
        let ran = directory.url.appending(path: "ran")
        try directory.file("home/.zshenv", contents: Data("""
            /usr/bin/touch \(ran.path(percentEncoded: false).quotedForTheShell)
            export ZDOTDIR="$HOME/.config/zsh"

            """.utf8))
        let zsh = ShellSessions.zsh(startupFile: home.appending(path: ".zshenv"))

        #expect(zsh.zshrcByTheText(home: home, zdotdir: nil)?.path(percentEncoded: false)
            .hasSuffix("home/.config/zsh/.zshrc") == true)
        #expect(ShellSessions.bash.zshrcByTheText(home: home, zdotdir: nil) == nil)
        #expect(ran.isMissing)
    }

    @Test func askingZshAQuestionRunsNoLogoutFile() async throws {
        let directory = try TemporaryDirectory()
        let home = try directory.directory("home")
        let loggedOut = directory.url.appending(path: "logged-out")
        let line = "print >> \(loggedOut.path(percentEncoded: false).quotedForTheShell)\n"
        try directory.file("home/.zlogout", contents: Data(line.utf8))
        let zsh = ShellSessions.zsh(startupFile: home.appending(path: ".zshenv"))

        let shown = await zsh.promptShown(home: home, zdotdir: nil)
        let zshrc = await zsh.zshrc(home: home, zdotdir: nil)

        #expect(shown != nil)
        #expect(zshrc != nil)
        #expect(!FileManager.default.fileExists(atPath: loggedOut.path(percentEncoded: false)))
    }

    @Test func onlyAPeelLaunchdStartedSharesTheSessionsZDOTDIR() {
        let environment = ["ZDOTDIR": "/org.example/zsh"]

        #expect(ShellSessions.sessionZDOTDIR(parent: 1, environment: environment) == "/org.example/zsh")
        #expect(ShellSessions.sessionZDOTDIR(parent: 4_242, environment: environment) == nil)
        #expect(ShellSessions.sessionZDOTDIR(parent: 1, environment: [:]) == nil)
    }

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

    @Test func zshReadsItsZshrcFromTheFolderItsZshenvNames() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url
        let zsh = ShellSessions.zsh(startupFile: home.appending(path: ".zshenv", directoryHint: .notDirectory))
        #expect(await zsh.zshrc(home: home, zdotdir: nil)?.path(percentEncoded: false)
            == home.appending(path: ".zshrc").path(percentEncoded: false))

        try directory.file(".zshenv", contents: Data("export ZDOTDIR=\"$HOME/.config/zsh\"\n".utf8))
        #expect(await zsh.zshrc(home: home, zdotdir: nil)?.path(percentEncoded: false)
            == home.appending(path: ".config/zsh/.zshrc").path(percentEncoded: false))
        #expect(await ShellSessions.bash.zshrc(home: home, zdotdir: nil) == nil)
    }

    @Test func readsTheFolderAStartupFileGivesZdotdirOnlyWhenItIsWrittenPlainly() {
        let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)
        let folders = { (text: String, environment: [String: String]) in
            ShellSessions.foldersGivenToZDOTDIR(in: text, home: home, environment: environment)
                .map { $0.path(percentEncoded: false) }
        }
        #expect(folders("ZDOTDIR=~/.zsh\n", [:]) == ["/Users/someone/.zsh/"])
        #expect(folders("export ZDOTDIR=\"$HOME/.config/zsh\"  # where zsh looks\n", [:]) == ["/Users/someone/.config/zsh/"])
        #expect(folders("  typeset -x ZDOTDIR='/Users/Shared/z sh'\n", [:]) == ["/Users/Shared/z sh/"])
        #expect(folders("export ZDOTDIR=${XDG_CONFIG_HOME:-${HOME}/.config}/zsh\n", [:]) == ["/Users/someone/.config/zsh/"])
        #expect(folders("export ZDOTDIR=${XDG_CONFIG_HOME:-$HOME/.config}/zsh\n", ["XDG_CONFIG_HOME": "/Users/someone/xdg"])
            == ["/Users/someone/xdg/zsh/"])
        #expect(folders("ZDOTDIR=/a\nZDOTDIR=/b;\n", [:]) == ["/a/", "/b/"])
        let unreadable = [
            "# ZDOTDIR=/commented", "ZDOTDIR=$(cat ~/.zdotdir)", "ZDOTDIR=`pwd`", "ZDOTDIR=$OTHER/zsh", "ZDOTDIR=relative/zsh",
            "ZDOTDIR='$HOME/literal'", "ZDOTDIR=\"/unclosed", "MY_ZDOTDIR=/x", "ZDOTDIR=",
        ]
        for line in unreadable {
            #expect(folders(line, [:]).isEmpty, "\(line)")
        }
    }

    @Test func aValueTheSessionGivesZdotdirIsNotExpandedAgain() {
        let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)
        let folders = { (environment: [String: String]) in
            ShellSessions.foldersGivenToZDOTDIR(
                in: "export ZDOTDIR=${ZDOTDIR:-$HOME/.config/zsh}\n", home: home, environment: environment
            ).map { $0.path(percentEncoded: false) }
        }
        #expect(folders(["ZDOTDIR": "${ZDOTDIR:-/tmp}"]).isEmpty)
        #expect(folders(["ZDOTDIR": "/Users/someone/zsh"]) == ["/Users/someone/zsh/"])
    }

    @Test func zshStartsWithZdotdirOnlyWhenTheSessionSetsIt() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url
        let zsh = ShellSessions.zsh(startupFile: home.appending(path: ".zshenv", directoryHint: .notDirectory))
        try directory.file(".zshenv", contents: Data("export ZDOTDIR=${ZDOTDIR:-$HOME/.config/zsh}\n".utf8))

        #expect(await zsh.zshrc(home: home, zdotdir: nil)?.path(percentEncoded: false)
            == home.appending(path: ".config/zsh/.zshrc").path(percentEncoded: false))
        #expect(await zsh.zshrc(home: home, zdotdir: home.path(percentEncoded: false))?.path(percentEncoded: false)
            == home.appending(path: ".zshrc").path(percentEncoded: false))
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
