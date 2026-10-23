import Foundation
@testable import PeelCore
import Testing

private struct GitHome: ~Copyable {
    let home: URL
    let config: GitConfig
    private let directory: TemporaryDirectory

    init() async throws {
        let directory = try TemporaryDirectory()
        let config = try #require(await GitConfig.find(home: directory.url))
        home = directory.url
        self.config = config
        self.directory = directory
    }

    var file: String {
        (try? String(contentsOf: home.appending(path: ".gitconfig"), encoding: .utf8)) ?? ""
    }

    func settings() async throws -> [String: String?] {
        try #require(await config.settings())
    }

    func publicKey(_ name: String) throws -> String {
        let key = home.appending(path: ".ssh/\(name)")
        try FileManager.default.createDirectory(at: key.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExample org.example\n".write(to: key, atomically: true, encoding: .utf8)
        return key.path(percentEncoded: false)
    }
}

struct GitSettingsTests {
    @Test func everySettingTurnsOnAndOffThroughGitAndLeavesNothingBehind() async throws {
        let git = try await GitHome()
        let key = try git.publicKey("id_ed25519.pub")
        for setting in GitSetting.allCases {
            var ledger = GitLedger()
            #expect(!setting.isOn(in: try await git.settings()), "\(setting)")
            #expect(await ledger.turnOn(setting, signingKey: key, in: git.config) == .changed, "\(setting)")
            #expect(setting.isOn(in: try await git.settings()), "\(setting)")
            #expect(await ledger.turnOff(setting, in: git.config) == .changed, "\(setting)")
            #expect(!setting.isOn(in: try await git.settings()), "\(setting)")
            #expect(ledger.written.isEmpty && ledger.previous.isEmpty, "\(setting)")
        }
        #expect(git.file.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(git.file)")
    }

    @Test func whatThePersonHadBeforeComesBack() async throws {
        let git = try await GitHome()
        #expect(await git.config.set("pull.rebase", to: "false"))
        #expect(await git.config.set("merge.conflictStyle", to: "diff3"))
        var ledger = GitLedger()
        #expect(await ledger.turnOn(.rebaseOnPull, signingKey: nil, in: git.config) == .changed)
        #expect(await ledger.turnOn(.zdiff3Conflicts, signingKey: nil, in: git.config) == .changed)
        #expect(try await git.settings()["pull.rebase"] == "true")
        #expect(await ledger.turnOff(.rebaseOnPull, in: git.config) == .changed)
        #expect(await ledger.turnOff(.zdiff3Conflicts, in: git.config) == .changed)
        let settings = try await git.settings()
        #expect(settings["pull.rebase"] == "false")
        #expect(settings["merge.conflictstyle"] == "diff3")
    }

    @Test func aKeyAFileTheGlobalSettingsIncludeSetsIsLeftToThatFile() async throws {
        let git = try await GitHome()
        let global = "[user]\n\temail = me@example.org\n[includeIf \"gitdir:~/work/\"]\n\tpath = ~/.gitconfig-work\n"
        try global.write(to: git.home.appending(path: ".gitconfig"), atomically: true, encoding: .utf8)
        try "[pull]\n\trebase = false\n".write(to: git.home.appending(path: ".gitconfig-work"), atomically: true, encoding: .utf8)
        var ledger = GitLedger()

        #expect(await ledger.turnOn(.rebaseOnPull, signingKey: nil, in: git.config) == .unchanged)
        #expect(try await git.settings()["pull.rebase"] == nil)
        #expect(await ledger.turnOn(.pruneOnFetch, signingKey: nil, in: git.config) == .changed)
    }

    @Test func readsEveryFileTheGlobalSettingsIncludeAsGitDoes() async throws {
        let git = try await GitHome()
        let files = [
            ".gitconfig": "[user]\n\temail = me@example.org\n[include]\n\tpath = conf/local.conf\n\tpath = ~/missing.conf\n"
                + "[includeIf \"gitdir:~/work/\"]\n\tpath = ~/.gitconfig-work\n",
            "conf/local.conf": "[diff]\n\talgorithm = patience\n[include]\n\tpath = deeper.conf\n",
            "conf/deeper.conf": "[fetch]\n\tprune = false\n",
            ".gitconfig-work": "[pull]\n\trebase = false\n",
        ]
        for (name, text) in files {
            let url = git.home.appending(path: name)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try text.write(to: url, atomically: true, encoding: .utf8)
        }

        #expect(await git.config.keysSetByIncludedFiles() == ["diff.algorithm", "fetch.prune", "pull.rebase"])
    }

    @Test func aValueThePersonChangedAfterPeelStaysTheirs() async throws {
        let git = try await GitHome()
        var ledger = GitLedger()
        #expect(await ledger.turnOn(.rebaseOnPull, signingKey: nil, in: git.config) == .changed)
        #expect(await git.config.set("pull.rebase", to: "merges"))
        #expect(await ledger.turnOff(.rebaseOnPull, in: git.config) == .unchanged)
        #expect(try await git.settings()["pull.rebase"] == "merges")
        #expect(ledger.written.isEmpty)
    }

    @Test func turningOffSigningThePersonSetUpStopsOnlyTheSigning() async throws {
        let git = try await GitHome()
        let key = try git.publicKey("id_ed25519.pub")
        for value in GitSetting.signCommits.values(signingKey: key) {
            #expect(await git.config.set(value.key, to: value.value))
        }
        #expect(GitSetting.signCommits.isOn(in: try await git.settings()))
        var ledger = GitLedger()
        #expect(await ledger.turnOff(.signCommits, in: git.config) == .changed)
        let settings = try await git.settings()
        #expect(settings["commit.gpgsign"] == nil)
        #expect(settings["gpg.format"] == "ssh")
        #expect(settings["user.signingkey"] == .some(key))
    }

    @Test func signingThePersonHadWithGPGComesBackWhole() async throws {
        let git = try await GitHome()
        let key = try git.publicKey("id_ed25519.pub")
        for (name, value) in [("gpg.format", "openpgp"), ("user.signingKey", "ABCDEF0123"), ("commit.gpgSign", "true")] {
            #expect(await git.config.set(name, to: value))
        }
        var ledger = GitLedger()
        #expect(await ledger.turnOn(.signCommits, signingKey: key, in: git.config) == .changed)
        #expect(GitSetting.signCommits.isOn(in: try await git.settings()))
        #expect(await ledger.turnOff(.signCommits, in: git.config) == .changed)
        let settings = try await git.settings()
        #expect(settings["gpg.format"] == "openpgp")
        #expect(settings["user.signingkey"] == "ABCDEF0123")
        #expect(settings["commit.gpgsign"] == "true")
        #expect(!GitSetting.signCommits.isOn(in: settings))
        #expect(ledger.written.isEmpty && ledger.previous.isEmpty)
    }

    @Test func writesDownWhatAKeyHeldBeforeGitWritesIt() async throws {
        let git = try await GitHome()
        var ledger = GitLedger()
        var files: [String] = []

        let outcome = await ledger.turnOn(.rebaseOnPull, signingKey: nil, in: git.config) { _ in
            files.append(git.file)
        }

        #expect(outcome == .changed)
        #expect(files.count == 1 && !files[0].contains("rebase"), "\(files)")
        #expect(git.file.contains("rebase = true"))
    }

    @Test func takesAKeyGitRefusedBackOutOfTheLedger() async throws {
        let git = try await GitHome()
        let home = git.home.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: home)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: home) }
        var ledger = GitLedger()
        var handed: [[String: String]] = []

        let outcome = await ledger.turnOn(.rebaseOnPull, signingKey: nil, in: git.config) { handed.append($0.written) }

        #expect(outcome == .refused)
        #expect(handed == [["pull.rebase": "true"], [:]])
        #expect(ledger.written.isEmpty && ledger.previous.isEmpty)
    }

    @Test func theLedgerIsHandedOverForEveryKeyItChanges() async throws {
        let git = try await GitHome()
        let key = try git.publicKey("id_ed25519.pub")
        var ledger = GitLedger()
        var handed: [Int] = []
        _ = await ledger.turnOn(.signCommits, signingKey: key, in: git.config) { handed.append($0.written.count) }
        #expect(handed == [1, 2, 3])
        handed = []
        _ = await ledger.turnOff(.signCommits, in: git.config) { handed.append($0.written.count) }
        #expect(handed == [2, 1, 0])
    }

    @Test func everyWayGitWritesTrueCountsAsOn() {
        for written in ["true", "TRUE", "yes", "on", "1"] {
            #expect(GitSetting.pruneOnFetch.isOn(in: ["fetch.prune": written]), "\(written)")
        }
        let valueless: [String: String?] = ["fetch.prune": nil]
        #expect(GitSetting.pruneOnFetch.isOn(in: valueless))
        for written in ["false", "no", "off", "0"] {
            #expect(!GitSetting.pruneOnFetch.isOn(in: ["fetch.prune": written]), "\(written)")
        }
        #expect(GitSetting.histogramDiff.isOn(in: ["diff.algorithm": "Histogram"]))
    }

    @Test func aGlobalFileGitCannotReadIsNotKnownAndNothingIsWritten() async throws {
        let git = try await GitHome()
        try "[pull\n\trebase = false\n".write(to: git.home.appending(path: ".gitconfig"), atomically: true, encoding: .utf8)
        #expect(await git.config.settings() == nil)
        var ledger = GitLedger()
        #expect(await ledger.turnOn(.rebaseOnPull, signingKey: nil, in: git.config) == .refused)
        #expect(git.file == "[pull\n\trebase = false\n")
    }

    @Test func signingUsesTheKeyGitSignsWithOrElseTheFirstDefaultKeyAndNeedsOne() async throws {
        let git = try await GitHome()
        #expect(GitSetting.signingKey(in: [:], home: git.home) == nil)
        var ledger = GitLedger()
        #expect(await ledger.turnOn(.signCommits, signingKey: nil, in: git.config) == .refused)
        let rsa = try git.publicKey("id_rsa.pub")
        #expect(GitSetting.signingKey(in: [:], home: git.home) == rsa)
        let ed25519 = try git.publicKey("id_ed25519.pub")
        #expect(GitSetting.signingKey(in: [:], home: git.home) == ed25519)
        let work = try git.publicKey("work.pub")
        #expect(GitSetting.signingKey(in: ["gpg.format": "ssh", "user.signingkey": work], home: git.home) == work)
        #expect(GitSetting.signingKey(in: ["gpg.format": "openpgp", "user.signingkey": "ABCDEF0123"], home: git.home) == ed25519)
        #expect(GitSetting.signingKey(in: ["user.signingkey": work], home: git.home) == ed25519)
        #expect(GitSetting.signingKey(in: ["gpg.format": "ssh", "user.signingkey": ""], home: git.home) == ed25519)
    }

    @Test func turningOnSigningKeepsTheKeyThePersonSignsWith() async throws {
        let git = try await GitHome()
        _ = try git.publicKey("id_ed25519.pub")
        let work = try git.publicKey("work.pub")
        #expect(await git.config.set("gpg.format", to: "ssh"))
        #expect(await git.config.set("user.signingKey", to: work))
        let settings = try await git.settings()
        let key = try #require(GitSetting.signingKey(in: settings, home: git.home))
        var ledger = GitLedger()
        #expect(await ledger.turnOn(.signCommits, signingKey: key, in: git.config) == .changed)
        #expect(try await git.settings()["user.signingkey"] == .some(work))
        #expect(await ledger.turnOff(.signCommits, in: git.config) == .changed)
        let after = try await git.settings()
        #expect(after["user.signingkey"] == .some(work))
        #expect(after["gpg.format"] == "ssh")
        #expect(after["commit.gpgsign"] == nil)
    }

    @Test func theGitOnThisMacKnowsEverySettingAndASettingItDoesNotKnowIsNotOffered() async throws {
        let git = try await GitHome()
        let known = try #require(await git.config.knownKeys())
        for setting in GitSetting.allCases {
            #expect(setting.isKnown(by: known), "\(setting)")
        }
        #expect(!GitSetting.pushNewBranches.isKnown(by: known.subtracting(["push.autosetupremote"])))
    }

    @Test func gitIsTheOneTheDeveloperToolsOrHomebrewInstalledAndNeverTheShim() throws {
        let directory = try TemporaryDirectory()
        let folder = directory.url
        let developer = folder.appending(path: "Developer", directoryHint: .isDirectory)
        let homebrew = folder.appending(path: "homebrew", directoryHint: .isDirectory)
        for git in [developer.appending(path: "usr/bin/git"), homebrew.appending(path: "bin/git")] {
            try FileManager.default.createDirectory(
                at: git.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            #expect(
                FileManager.default.createFile(
                    atPath: git.path(percentEncoded: false),
                    contents: Data(),
                    attributes: [.posixPermissions: 0o755]
                )
            )
        }
        #expect(
            GitConfig.find(developerFolder: developer, homebrewPrefix: homebrew, home: folder)?.executable
                == developer.appending(path: "usr/bin/git")
        )
        #expect(
            GitConfig.find(developerFolder: nil, homebrewPrefix: homebrew, home: folder)?.executable
                == homebrew.appending(path: "bin/git")
        )
        #expect(GitConfig.find(developerFolder: folder.appending(path: "Missing"), homebrewPrefix: nil, home: folder) == nil)
    }
}
