import Darwin
import Foundation
@testable import PeelCore
import PeelPrivileged
import Testing

struct ShellFileTests {
    static let inEffect: [ShellSetting: String] = [
        .longHistory: "(( HISTSIZE == 50000 && SAVEHIST == 50000 ))",
        .sharedHistory: "[[ -o sharehistory ]]",
        .timedHistory: "[[ -o extendedhistory ]]",
        .noRepeats: "[[ -o histignorealldups ]]",
        .spaceHides: "[[ -o histignorespace ]]",
        .tidyHistory: "[[ -o histreduceblanks ]]",
        .verifyRecall: "[[ -o histverify ]]",
        .lockedHistory: "[[ -o histfcntllock ]]",
        .comments: "[[ -o interactivecomments ]]",
        .prefixSearch: """
            [[ $(bindkey '^[[A') == *' up-line-or-beginning-search' && $(bindkey '^[OA') == *' up-line-or-beginning-search' \
            && $(bindkey '^[[B') == *' down-line-or-beginning-search' && $(bindkey '^[OB') == *' down-line-or-beginning-search' ]]
            """,
        .pathWords: "[[ $WORDCHARS != */* ]]",
        .autoCD: "[[ -o autocd ]]",
        .folderStack: "[[ -o autopushd && -o pushdignoredups ]]",
        .completionMenu: "(( $+functions[compdef] )) && [[ $(zstyle -L ':completion:*' menu) == *' menu select' ]]",
        .anyCase: "(( $+functions[compdef] )) && [[ $(zstyle -L ':completion:*' matcher-list) == *\"'m:{a-zA-Z}={A-Za-z}'\" ]]",
        .colorfulLs: "[[ ${(t)CLICOLOR} == *export* && $CLICOLOR == 1 ]]",
    ]

    @Test func everySettingIsInEffectInANewShellOnceItIsOnAndNotBefore() throws {
        let shell = try ZshHome()
        #expect(Set(Self.inEffect.keys) == Set(ShellSetting.allCases))
        for setting in ShellSetting.allCases {
            let check = try #require(Self.inEffect[setting])
            #expect(ShellFile.write(.init(), to: shell.peelFile))
            #expect(try shell.answers(check) == false, "\(setting)")
            #expect(ShellFile.write(.init(settings: [setting]), to: shell.peelFile))
            #expect(try shell.answers(check) == true, "\(setting)")
        }
    }

    @Test func everySettingAtOnceIsInEffectWithoutAnError() throws {
        let shell = try ZshHome()
        #expect(ShellFile.write(.init(settings: Set(ShellSetting.allCases)), to: shell.peelFile))
        let all = ShellSetting.allCases.compactMap { Self.inEffect[$0] }.map { "{ \($0) }" }.joined(separator: " && ")
        #expect(try shell.answers(all))
    }

    @Test func upAndDownFindTheCommandsThatStartWithWhatWasTyped() throws {
        let shell = try ZshHome(thenRun: ["PS1='ready> '"])
        #expect(ShellFile.write(.init(settings: [.prefixSearch]), to: shell.peelFile))
        for up in ["\u{1B}[A", "\u{1B}OA"] {
            try "echo alpha\necho beta\n".write(to: shell.home.appending(path: ".zsh_history"), atomically: true, encoding: .utf8)
            let terminal = try PseudoTerminal()
            let process = Process()
            process.executableURL = URL(filePath: "/bin/zsh")
            process.arguments = ["-i"]
            process.environment = shell.environment
            let replica = FileHandle(fileDescriptor: terminal.replica, closeOnDealloc: false)
            process.standardInput = replica
            process.standardOutput = replica
            process.standardError = replica
            try process.run()
            terminal.read(until: "ready> ")
            terminal.type("echo al" + up + "\r")
            terminal.read(until: "\r\nalpha")
            terminal.type("exit\r")
            _ = terminal.everything()
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
            #expect(terminal.drawn.contains("\r\nalpha\r\n"), "\(up.debugDescription): \(terminal.drawn.debugDescription)")
            #expect(!terminal.drawn.contains("\r\nbeta\r\n"), "\(up.debugDescription)")
        }
    }

    @Test func theFileReadsBackAsTheChoicesWrittenInIt() {
        for setting in ShellSetting.allCases {
            let choices = ShellFile.Choices(settings: [setting])
            #expect(ShellFile.choices(in: ShellFile.contents(of: choices)) == choices)
        }
        for prompt in PromptStyle.allCases {
            let choices = ShellFile.Choices(settings: Set(ShellSetting.allCases), prompt: prompt)
            #expect(ShellFile.choices(in: ShellFile.contents(of: choices)) == choices)
        }
        #expect(ShellFile.choices(in: ShellFile.contents(of: .init())) == .init())
    }

    @Test func aMissingFileHasNothingOnAndOneThatCannotBeReadIsNotKnown() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ShellFileTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let file = ShellFile.url(in: folder)
        #expect(ShellFile.read(file) == .init())
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        #expect(ShellFile.read(file) == nil)
    }

    @Test func writingReplacesALinkInsteadOfWritingWhereItLeads() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ShellFileTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let file = ShellFile.url(in: folder)
        let theirs = folder.appending(path: "theirs")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "theirs\n".write(to: theirs, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: theirs)
        #expect(ShellFile.write(.init(settings: [.comments]), to: file))
        #expect(try String(contentsOf: theirs, encoding: .utf8) == "theirs\n")
        #expect(try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false)
        #expect(ShellFile.read(file) == .init(settings: [.comments]))
    }

    @Test func theLineIsFoundInTheStartupFileUnlessItIsACommentOrSpelledAnotherWay() throws {
        let shell = try ZshHome()
        let startup = shell.home.appending(path: ".zshrc")
        #expect(ShellFile.line(sourcing: shell.peelFile, home: shell.home)
            == "[[ -r \"$HOME/Library/Application Support/Peel/Terminal/zshrc\" ]] && source \"$HOME/Library/Application Support/Peel/Terminal/zshrc\"")
        #expect(ShellFile.isSourced(shell.peelFile, from: startup, home: shell.home))
        for (text, found) in [
            ("source ~/Library/Application\\ Support/Peel/Terminal/zshrc\n", true),
            ("export PATH=/opt/homebrew/bin:$PATH\n  . \"$HOME/Library/Application Support/Peel/Terminal/zshrc\"\n", true),
            ("# " + ShellFile.line(sourcing: shell.peelFile, home: shell.home) + "\n", false),
            ("setopt AUTO_CD\n", false),
        ] {
            try text.write(to: startup, atomically: true, encoding: .utf8)
            #expect(ShellFile.isSourced(shell.peelFile, from: startup, home: shell.home) == found, "\(text)")
        }
        try FileManager.default.removeItem(at: startup)
        #expect(!ShellFile.isSourced(shell.peelFile, from: startup, home: shell.home))
    }
}

struct ZshRequirementsTests {
    @Test func theZshOnThisMacKnowsEverySettingAndEveryPrompt() async throws {
        let known = try #require(await ShellFile.knownToZsh())
        for setting in ShellSetting.allCases {
            #expect(setting.isKnown(by: known), "\(setting)")
        }
        for prompt in PromptStyle.allCases {
            #expect(prompt.isKnown(by: known), "\(prompt)")
        }
    }

    @Test func whatALineNeedsIsReadFromIt() {
        #expect(ZshRequirements.of(["setopt AUTO_PUSHD PUSHD_IGNORE_DUPS"]) == ["option:autopushd", "option:pushdignoredups"])
        #expect(ZshRequirements.of(["autoload -Uz vcs_info add-zsh-hook"]) == ["function:vcs_info", "function:add-zsh-hook"])
        #expect(ZshRequirements.of([ShellFile.completionSystem]) == ["function:compinit"])
        #expect(ZshRequirements.of(["HISTSIZE=50000", "zstyle ':completion:*' menu select"]).isEmpty)
        #expect(ShellSetting.completionMenu.requirements == ["function:compinit"])
    }

    @Test func aSettingOrPromptNeedingWhatZshDoesNotKnowIsNotOffered() async throws {
        let known = try #require(await ShellFile.knownToZsh())
        #expect(!ShellSetting.sharedHistory.isKnown(by: known.subtracting(["option:sharehistory"])))
        #expect(!ShellSetting.prefixSearch.isKnown(by: known.subtracting(["function:up-line-or-beginning-search"])))
        #expect(!PromptStyle.arrowAndBranch.isKnown(by: known.subtracting(["function:vcs_info"])))
        #expect(PromptStyle.macOS.isKnown(by: []))
    }
}

struct PeelLinesCommandTests {
    private func run(_ command: String, home: URL) async throws -> Int32 {
        let answer = await Subprocess.run("/bin/zsh", ["-f", "-c", command], environment: ["HOME": home.path(percentEncoded: false), "PATH": "/usr/bin:/bin"], timeout: 10)
        guard case .success(let output) = answer else { throw POSIXError(.EIO) }
        #expect(output.errorText.isEmpty, "\(output.errorText)")
        return output.status
    }

    private func madeUpHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "PeelLines-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    @Test func theShellsCommandAddsTheLineAtTheEndOfZshrcAndPeelFindsIt() async throws {
        let home = try madeUpHome()
        let file = ShellFile.url(in: home.appending(path: "Library/Application Support/Peel", directoryHint: .isDirectory))
        let zshrc = home.appending(path: ".zshrc")
        let line = ShellFile.line(sourcing: file, home: home)
        let command = ShellFile.command(adding: line, to: zshrc, home: home)
        #expect(command.hasSuffix(" >> ~/.zshrc"))
        #expect(try await run(command, home: home) == 0)
        #expect(try String(contentsOf: zshrc, encoding: .utf8) == line + "\n")
        #expect(ShellFile.isSourced(file, from: zshrc, home: home))
        try "setopt AUTO_CD\n".write(to: zshrc, atomically: true, encoding: .utf8)
        #expect(try await run(command, home: home) == 0)
        #expect(try String(contentsOf: zshrc, encoding: .utf8) == "setopt AUTO_CD\n" + line + "\n")
    }

    @Test func theSSHCommandMakesAClosedFolderAndAddsTheLinesPeelFinds() async throws {
        let home = try madeUpHome()
        let file = SSHFile.url(in: home.appending(path: "Library/Application Support/Peel", directoryHint: .isDirectory))
        let config = home.appending(path: ".ssh/config")
        let lines = SSHFile.lines(including: file, home: home)
        #expect(try await run(SSHFile.command(adding: lines, to: config, home: home), home: home) == 0)
        let folder = try FileManager.default.attributesOfItem(atPath: config.deletingLastPathComponent().path(percentEncoded: false))
        #expect((folder[.posixPermissions] as? Int) == 0o700)
        #expect(try String(contentsOf: config, encoding: .utf8) == "\n" + lines.joined(separator: "\n") + "\n")
        #expect(SSHFile.isIncluded(file, from: config, home: home))
    }

    @Test func aPathOutsideTheHomeOrWithASpaceIsQuotedForTheShell() {
        let home = URL(filePath: "/Users/example", directoryHint: .isDirectory)
        #expect(home.appending(path: ".zshrc").pathForTheShell(home: home) == "~/.zshrc")
        #expect(home.appending(path: "My Files/.zshrc").pathForTheShell(home: home) == "'/Users/example/My Files/.zshrc'")
        #expect(URL(filePath: "/etc/it's").pathForTheShell(home: home) == "'/etc/it'\\''s'")
        #expect(ShellSessions.zsh(startupFile: home.appending(path: ".zshenv")).zshrc == home.appending(path: ".zshrc"))
        #expect(ShellSessions.bash.zshrc == nil)
    }
}
