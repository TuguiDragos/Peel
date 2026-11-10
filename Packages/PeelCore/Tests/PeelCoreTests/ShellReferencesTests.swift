import Foundation
@testable import PeelCore
import Testing

struct ShellReferencesTests {
    @Test func namesTheLinesThatStillPointToWhatMoved() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try directory.file("home/.zshrc", contents: Data("""
            # export PATH="/Applications/Note Pad.app/Contents/MacOS:$PATH"
            export PATH="/Applications/Note Pad.app/Contents/MacOS:$PATH"
            alias notes="$HOME/Library/Application Support/Note Pad/notes"
            source ~/Library/Application\\ Support/Note\\ Pad/env.sh
            export EDITOR=vim
            """.utf8))
        try directory.file("home/.config/fish/config.fish", contents: Data("set -gx NOTES ~/Library/Application Support/Note Pad\n".utf8))
        try directory.file("home/.bashrc", contents: Data("export PATH=/opt/other/bin:$PATH\n".utf8))
        let moved = [
            URL(filePath: "/Applications/Note Pad.app", directoryHint: .isDirectory),
            home.appending(path: "Library/Application Support/Note Pad", directoryHint: .isDirectory),
        ]

        let found = await ShellReferences.find(naming: moved, home: home)

        #expect(found.map { ($0.file.lastPathComponent, $0.line) }.map { "\($0.0):\($0.1)" } == [
            ".zshrc:2", ".zshrc:3", ".zshrc:4", "config.fish:1",
        ])
        #expect(await ShellReferences.find(naming: [], home: home).isEmpty)
    }

    @Test func namesALineOnlyWhereThePathStandsWhole() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try directory.file("home/.zshrc", contents: Data("""
            export PATH="$HOME/Library/Application Support/CodeWhisperer/bin:$PATH"
            source ~/Applications/Foo.app/Contents/env.sh
            PATH=/Applications/Foo.appendix/bin:$PATH
            cp -R /Applications/Foo.app.bak /tmp
            alias foo=/applications/FOO.app/Contents/MacOS/foo
            export PATH="$PATH:$HOME/Library/Application Support/Code/bin"
            [ -d "/Applications/Foo.app" ] && echo yes
            fpath=(~/Library/Application\\ Support/Code $fpath)
            """.utf8))
        let moved = [
            URL(filePath: "/Applications/Foo.app", directoryHint: .isDirectory),
            home.appending(path: "Library/Application Support/Code", directoryHint: .isDirectory),
        ]

        let found = await ShellReferences.find(naming: moved, home: home)

        #expect(found.map(\.line) == [5, 6, 7, 8])
    }

    @Test func findsTheFolderZshenvNamesWithoutRunningAnyStartupFile() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        for name in [".zshenv", ".zprofile", ".zlogin"] {
            let ran = home.appending(path: "ran\(name)").path(percentEncoded: false)
            let sets = name == ".zshenv" ? "export ZDOTDIR=\"$HOME/.config/zsh\"\n" : ""
            try directory.file("home/\(name)", contents: Data("\(sets): > '\(ran)'\n".utf8))
        }
        try directory.file("home/.config/zsh/.zshrc", contents: Data("source /Applications/Pad.app/Contents/env.sh\n".utf8))
        let moved = [URL(filePath: "/Applications/Pad.app", directoryHint: .isDirectory)]

        let found = await ShellReferences.find(naming: moved, home: home)

        #expect(found.map { "\($0.file.lastPathComponent):\($0.line)" } == [".zshrc:1"])
        #expect(found.first?.file.deletingLastPathComponent().lastPathComponent == "zsh")
        let left = try FileManager.default.contentsOfDirectory(atPath: home.path(percentEncoded: false))
        #expect(left.filter { $0.hasPrefix("ran") }.isEmpty)
    }

    @Test func readsTheStartupFilesOfEachShellOnce() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try directory.directory("home")

        let files = ShellReferences.startupFiles(home: home).map(\.lastPathComponent)

        #expect(files == [
            ".zshenv", ".zprofile", ".zshrc", ".zlogin", ".bash_profile", ".bash_login", ".bashrc", ".profile",
            ".tcshrc", ".cshrc", ".login", "config.fish",
        ])
        #expect(Set(files).count == files.count)
    }

    @Test func namesTheLinesBashLoginAndTcshReadToo() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try directory.file("home/.bash_login", contents: Data("export PATH=\"$HOME/.notepad/bin:$PATH\"\n".utf8))
        try directory.file("home/.tcshrc", contents: Data("setenv PATH \"$HOME/.notepad/bin\":\"$PATH\"\n".utf8))
        try directory.file("home/.cshrc", contents: Data("setenv PATH \"$HOME/.notepad/bin\":\"$PATH\"\n".utf8))
        try directory.file("home/.login", contents: Data("source ~/.notepad/env.csh\n".utf8))
        let moved = [home.appending(path: ".notepad", directoryHint: .isDirectory)]

        let found = await ShellReferences.find(naming: moved, home: home)

        #expect(found.map(\.file.lastPathComponent) == [".bash_login", ".tcshrc", ".cshrc", ".login"])
    }

    @Test func spellsAPathAsAShellLineWould() {
        let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)
        #expect(ShellReferences.spellings(of: URL(filePath: "/Applications/Pad.app/"), home: home) == ["/Applications/Pad.app"])
        #expect(ShellReferences.spellings(of: URL(filePath: "/Users/me/Library/Pad Data"), home: home) == [
            "/Users/me/Library/Pad Data", "~/Library/Pad Data", "$HOME/Library/Pad Data", "${HOME}/Library/Pad Data",
            "/Users/me/Library/Pad\\ Data", "~/Library/Pad\\ Data", "$HOME/Library/Pad\\ Data", "${HOME}/Library/Pad\\ Data",
        ])
    }
}
