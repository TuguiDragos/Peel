import Darwin
import Foundation
@testable import PeelCore
import Testing

/// A made-up home whose `.zshrc` sources Peel's file, the way a person's does once they add Peel's line.
private struct ZshHome {
    let home: URL
    let peelFile: URL

    init() throws {
        home = FileManager.default.temporaryDirectory.appending(path: "ShellFileTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        peelFile = ShellFile.url(in: home.appending(path: "Library/Application Support/Peel", directoryHint: .isDirectory))
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try (ShellFile.line(sourcing: peelFile, home: home) + "\nPS1='ready> '\n")
            .write(to: home.appending(path: ".zshrc"), atomically: true, encoding: .utf8)
    }

    var environment: [String: String] {
        ["HOME": home.path, "ZDOTDIR": home.path, "TERM": "xterm-256color", "PATH": "/usr/bin:/bin"]
    }

    /// Whether `check` holds in a new interactive zsh, which also has to start without a single error.
    func answers(_ check: String) throws -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = ["-i", "-c", "if \(check); then print yes; else print no; fi"]
        process.environment = environment
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let said = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let complained = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(complained.isEmpty, "\(complained)")
        return said == "yes\n"
    }
}

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
            #expect(ShellFile.write([], to: shell.peelFile))
            #expect(try shell.answers(check) == false, "\(setting)")
            #expect(ShellFile.write([setting], to: shell.peelFile))
            #expect(try shell.answers(check) == true, "\(setting)")
        }
    }

    @Test func everySettingAtOnceIsInEffectWithoutAnError() throws {
        let shell = try ZshHome()
        #expect(ShellFile.write(Set(ShellSetting.allCases), to: shell.peelFile))
        let all = ShellSetting.allCases.compactMap { Self.inEffect[$0] }.map { "{ \($0) }" }.joined(separator: " && ")
        #expect(try shell.answers(all))
    }

    @Test func upAndDownFindTheCommandsThatStartWithWhatWasTyped() throws {
        let shell = try ZshHome()
        #expect(ShellFile.write([.prefixSearch], to: shell.peelFile))
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

    @Test func theFileReadsBackAsTheSettingsWrittenInIt() {
        for setting in ShellSetting.allCases {
            #expect(ShellFile.settings(in: ShellFile.contents(of: [setting])) == [setting])
        }
        #expect(ShellFile.settings(in: ShellFile.contents(of: Set(ShellSetting.allCases))) == Set(ShellSetting.allCases))
        #expect(ShellFile.settings(in: ShellFile.contents(of: [])).isEmpty)
    }

    @Test func aMissingFileHasNothingOnAndOneThatCannotBeReadIsNotKnown() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ShellFileTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let file = ShellFile.url(in: folder)
        #expect(ShellFile.read(file) == [])
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
        #expect(ShellFile.write([.comments], to: file))
        #expect(try String(contentsOf: theirs, encoding: .utf8) == "theirs\n")
        #expect(try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false)
        #expect(ShellFile.read(file) == [.comments])
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
