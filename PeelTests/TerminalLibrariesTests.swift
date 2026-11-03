import Foundation
@testable import Peel
@testable import PeelCore
import Testing

private final class FakeTerminalSettings: TerminalSettingsStoring {
    var isTerminalOpen = false
    var isManaged = false
    var storedProfiles: [String: [String: Any]]? = [:]
    var names: [TerminalProfileRole: String] = [:]
    var shellSetting: String?

    func profiles() -> [String: [String: Any]]? { storedProfiles }

    func setProfiles(_ profiles: [String: [String: Any]]) -> Bool {
        storedProfiles = profiles
        return true
    }

    func profileName(for role: TerminalProfileRole) -> String? { names[role] }

    func setProfileName(_ name: String?, for role: TerminalProfileRole) -> Bool {
        names[role] = name
        return true
    }

    func shell() -> String? { shellSetting }
}

struct TerminalLibrariesTests {
    private func madeUpHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(
            path: "TerminalLibrariesTests-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func unreadableFile(at url: URL) throws -> Int {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = Data(repeating: UInt8(ascii: "#"), count: 65 * 1_024)
        try bytes.write(to: url)
        return bytes.count
    }

    private func size(of url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int)
    }

    @Test func turnAllOffOnTheShellTabLeavesAFileItCouldNotRead() async throws {
        let home = try madeUpHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appending(path: "Library/Application Support/Peel", directoryHint: .isDirectory)
        let library = ShellLibrary(folder: folder, home: home)
        let bytes = try unreadableFile(at: library.file)

        await library.refresh()
        #expect(library.state?.choices == nil)
        library.turnAllOff()

        #expect(try size(of: library.file) == bytes)
    }

    @Test func turnAllOffOnTheSSHTabLeavesAFileItCouldNotRead() async throws {
        let home = try madeUpHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appending(path: "Library/Application Support/Peel", directoryHint: .isDirectory)
        let library = SSHLibrary(folder: folder, home: home)
        let bytes = try unreadableFile(at: library.file)

        await library.refresh()
        #expect(library.state?.settings == nil)
        library.turnAllOff()

        #expect(try size(of: library.file) == bytes)
    }

    @Test func theShellTabAsksZshWhichPromptItShowsOnlyWhilePeelsPromptIsOn() async throws {
        let home = try madeUpHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appending(path: "Library/Application Support/Peel", directoryHint: .isDirectory)
        let terminal = FakeTerminalSettings()
        terminal.shellSetting = "/bin/zsh"
        let library = ShellLibrary(folder: folder, home: home, terminal: terminal)
        try ("precmd() { PROMPT='mine> ' }\n" + library.line + "\n")
            .write(to: home.appending(path: ".zshrc"), atomically: true, encoding: .utf8)
        try "export ZDOTDIR=\"$HOME\"\n".write(to: home.appending(path: ".zshenv"), atomically: true, encoding: .utf8)

        await library.refresh()
        #expect(library.state?.isSourced == true)
        #expect(library.state?.shownPrompt == nil)

        library.setPrompt(Prompt())
        await library.refresh()
        #expect(library.state?.shownPrompt?.setBeforeEachCommandBy == ["precmd"])
        #expect(library.state?.shownPrompt?.prompt == "mine> ")
    }

    @Test func aSwitchTurnedOnWhileZshAnswersStaysOn() async throws {
        let home = try madeUpHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appending(path: "Library/Application Support/Peel", directoryHint: .isDirectory)
        let terminal = FakeTerminalSettings()
        terminal.shellSetting = "/bin/zsh"
        let library = ShellLibrary(folder: folder, home: home, terminal: terminal)
        try ("sleep 3\n" + library.line + "\n")
            .write(to: home.appending(path: ".zshrc"), atomically: true, encoding: .utf8)
        try "export ZDOTDIR=\"$HOME\"\n".write(to: home.appending(path: ".zshenv"), atomically: true, encoding: .utf8)
        await library.refresh()
        library.setPrompt(Prompt())

        let reading = Task { await library.refresh() }
        try await Task.sleep(for: .seconds(1))
        library.set(.autoCD, to: true)
        await reading.value

        #expect(library.state?.choices?.settings.contains(.autoCD) == true)
        library.set(.comments, to: true)
        #expect(ShellFile.read(library.file)?.settings == [.autoCD, .comments])
    }

    @Test func aReadingCutShortIsNoAnswerFromZshOrSSH() async throws {
        let home = try madeUpHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appending(path: "Library/Application Support/Peel", directoryHint: .isDirectory)
        let terminal = FakeTerminalSettings()
        terminal.shellSetting = "/bin/zsh"
        let shell = ShellLibrary(folder: folder, home: home, terminal: terminal)
        let ssh = SSHLibrary(folder: folder, home: home)

        let reading = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await shell.refresh()
            await ssh.refresh()
        }
        await reading.value

        #expect(shell.state == nil)
        #expect(ssh.state == nil)
    }

    @Test func theShellTabLooksForNoZshrcWhenTerminalOpensBash() async throws {
        let home = try madeUpHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appending(path: "Library/Application Support/Peel", directoryHint: .isDirectory)
        let terminal = FakeTerminalSettings()
        terminal.shellSetting = "/bin/bash"
        let library = ShellLibrary(folder: folder, home: home, terminal: terminal)
        try (library.line + "\n").write(to: home.appending(path: ".zshrc"), atomically: true, encoding: .utf8)

        await library.refresh()
        #expect(library.state?.shell == .bash)
        #expect(library.state?.startupFile == nil)
        #expect(library.state?.isSourced == false)
    }

    @Test func theTerminalTabKnowsFromTheStartWhenTerminalsProfilesCannotBeRead() throws {
        let home = try madeUpHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let defaults = made.defaults
        let terminal = FakeTerminalSettings()
        let theme = TerminalThemeCatalog.all[0]
        terminal.names = [.newWindows: theme.profileName, .startup: theme.profileName]
        terminal.storedProfiles = nil

        let library = TerminalLibrary(settings: terminal, defaults: defaults, home: home)

        #expect(library.areProfilesUnreadable)
        #expect(library.themeInUse == theme)
        #expect(library.options == nil)
        #expect(!library.wasRefused)

        terminal.storedProfiles = [theme.profileName: ["name": theme.profileName]]
        library.refresh()
        #expect(!library.areProfilesUnreadable)
        #expect(library.options == [])
    }

    @Test func saysWhenTerminalOpensWithAProfileOtherThanNewWindows() throws {
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let theme = try #require(TerminalThemeCatalog.all.first)
        let terminal = FakeTerminalSettings()
        terminal.names = [.newWindows: theme.profileName, .startup: "Basic"]

        let library = TerminalLibrary(settings: terminal, defaults: made.defaults)
        #expect(library.themeInUse == theme)
        #expect(library.opensWith == "Basic")

        terminal.names[.startup] = theme.profileName
        library.refresh()
        #expect(library.opensWith == nil)

        terminal.names[.startup] = nil
        library.refresh()
        #expect(library.opensWith == nil)
    }

    @Test func aRefusalIsForgottenWhenThePageGoes() throws {
        let home = try madeUpHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let defaults = made.defaults
        let terminal = FakeTerminalSettings()
        let library = TerminalLibrary(settings: terminal, defaults: defaults, home: home)
        terminal.storedProfiles = nil

        library.perform(.use(TerminalThemeCatalog.all[0]))
        #expect(library.areProfilesUnreadable)
        library.forgetRefusal()
        #expect(!library.wasRefused)
    }

    @Test func aToolIsInstalledThoughPeelWontRunTheBrewThatInstalledIt() throws {
        let home = try madeUpHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let prefix = home.appending(path: "homebrew", directoryHint: .isDirectory)
        let tool = try #require(TerminalTool.allCases.first)
        let formula = try #require(tool.formulae.first)
        try FileManager.default.createDirectory(
            at: prefix.appending(path: "opt/\(formula)", directoryHint: .isDirectory), withIntermediateDirectories: true
        )
        let refused = HomebrewChoice.Unrunnable(
            brew: prefix.appending(path: "bin/brew"), refusal: .ownedByAnotherAccount(owner: nil)
        )

        #expect(TerminalToolLibrary.installed(prefix: nil, refused: refused, unrunnable: nil).contains(tool))
        #expect(TerminalToolLibrary.installed(prefix: nil, refused: nil, unrunnable: refused).contains(tool))
        #expect(TerminalToolLibrary.installed(prefix: prefix, refused: nil, unrunnable: nil).contains(tool))
        #expect(TerminalToolLibrary.installed(prefix: nil, refused: nil, unrunnable: nil).isEmpty)
    }

    @Test func aToolsLinesNameTheFolderOfTheBrewPeelWontRun() {
        let refused = HomebrewChoice.Unrunnable(
            brew: URL(filePath: "/org.example/brew/bin/brew"), refusal: .ownedByAnotherAccount(owner: nil)
        )
        let running = URL(filePath: "/org.example/other/", directoryHint: .isDirectory)
        typealias Brew = HomebrewChoice.Unrunnable
        func folder(_ prefix: URL?, _ refused: Brew?, _ unrunnable: Brew?) -> String? {
            TerminalToolLibrary.State(prefix: prefix, installed: [], unrunnable: unrunnable, refused: refused)
                .folder?.path(percentEncoded: false)
        }

        #expect(folder(nil, refused, nil) == "/org.example/brew/")
        #expect(folder(nil, nil, refused) == "/org.example/brew/")
        #expect(folder(running, refused, nil) == "/org.example/other/")
        #expect(folder(nil, nil, nil) == nil)
    }

    @Test func aToolsAvailabilityIsNotKnownWhileHomebrewIsAsked() {
        let fzf = HomebrewPackage(name: "fzf", kind: .formula)
        let catalog = TerminalToolLibrary.Catalog(known: ["fzf"], packages: [fzf])
        #expect(TerminalToolLibrary.availability(of: .fzf, in: .asking) == nil)
        #expect(TerminalToolLibrary.availability(of: .fzf, in: .notAsked) == .available)
        #expect(TerminalToolLibrary.availability(of: .fzf, in: .answered(catalog)) == .available)
        #expect(TerminalToolLibrary.availability(of: .fzfTab, in: .answered(catalog)) == .unknownToHomebrew)
        #expect(TerminalToolLibrary.availability(of: .fzfTab, in: .notAsked) == .available)
    }

    @Test func aGitThatWentAwayIsLookedForAgain() async throws {
        let home = try madeUpHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let git = home.appending(path: "git")
        try Data("#!/bin/sh\nexit 1\n".utf8).write(to: git)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: git.path(percentEncoded: false))
        let found = GitConfig(executable: git, home: home)
        let library = GitLibrary(home: home, defaults: made.defaults, finding: {
            FileManager.default.isExecutableFile(atPath: git.path(percentEncoded: false)) ? found : nil
        })
        await library.refresh()
        #expect(library.state?.isInstalled == true)

        try FileManager.default.removeItem(at: git)
        await library.refresh()

        #expect(library.state?.isInstalled == false)
    }

    @Test func aGitRefusalIsForgottenWhenThePageGoes() async throws {
        let home = try madeUpHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let git = home.appending(path: "git")
        try Data("#!/bin/sh\nexit 1\n".utf8).write(to: git)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: git.path(percentEncoded: false))
        let library = GitLibrary(home: home, defaults: made.defaults) { GitConfig(executable: git, home: home) }
        await library.refresh()

        library.set(.rebaseOnPull, to: true)
        await library.refresh()
        #expect(library.wasRefused)

        library.forgetRefusal()
        #expect(!library.wasRefused)
    }

    @Test func aGitChangeSavesTheLedgerInTheStoreItWasGiven() async throws {
        let home = try madeUpHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let defaults = made.defaults
        let library = GitLibrary(home: home, defaults: defaults)
        await library.refresh()
        let state = try #require(library.state)
        #expect(state.isInstalled)
        let standardBefore = UserDefaults.standard.dictionary(forKey: GitLibrary.ledgerKey)

        library.set(.rebaseOnPull, to: true)
        #expect(library.isOn(.rebaseOnPull))
        await library.refresh()

        #expect(library.isOn(.rebaseOnPull))
        let written = try #require(defaults.dictionary(forKey: GitLibrary.ledgerKey)?["written"] as? [String: String])
        #expect(written["pull.rebase"] == "true")
        #expect(UserDefaults.standard.dictionary(forKey: GitLibrary.ledgerKey) == nil || standardBefore != nil)

        library.set(.rebaseOnPull, to: false)
        await library.refresh()
        #expect(!library.isOn(.rebaseOnPull))
        #expect((defaults.dictionary(forKey: GitLibrary.ledgerKey)?["written"] as? [String: String])?.isEmpty == true)
    }
}
