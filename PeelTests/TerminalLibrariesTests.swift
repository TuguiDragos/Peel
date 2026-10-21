import Foundation
@testable import Peel
import PeelCore
import Testing

/// Terminal's settings as a test keeps them in memory, never Terminal's own.
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

    /// A file Peel refuses to read, larger than it ever writes.
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
        let library = ShellLibrary(folder: folder, home: home)
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

    @Test func theTerminalTabKnowsFromTheStartWhenTerminalsProfilesCannotBeRead() throws {
        let home = try madeUpHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let suite = "org.example.peel-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
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

    @Test func aRefusalIsForgottenWhenThePageGoes() throws {
        let home = try madeUpHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let suite = "org.example.peel-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let terminal = FakeTerminalSettings()
        let library = TerminalLibrary(settings: terminal, defaults: defaults, home: home)
        terminal.storedProfiles = nil

        library.perform(.use(TerminalThemeCatalog.all[0]))
        #expect(library.areProfilesUnreadable)
        library.forgetRefusal()
        #expect(!library.wasRefused)
    }

    @Test func aGitChangeSavesTheLedgerInTheStoreItWasGiven() async throws {
        let home = try madeUpHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let suite = "org.example.peel-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
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
