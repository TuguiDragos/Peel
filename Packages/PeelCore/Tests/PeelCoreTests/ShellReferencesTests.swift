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

    @Test func readsTheStartupFilesOfEachShellOnce() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try directory.directory("home")

        let files = await ShellReferences.startupFiles(home: home).map(\.lastPathComponent)

        #expect(files == [".zshenv", ".zprofile", ".zshrc", ".zlogin", ".bash_profile", ".bashrc", ".profile", "config.fish"])
        #expect(Set(files).count == files.count)
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
