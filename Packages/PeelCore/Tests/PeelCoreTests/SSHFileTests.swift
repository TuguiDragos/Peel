import Foundation
@testable import PeelCore
import PeelPrivileged
import Testing

private struct SSHHome: ~Copyable {
    let folder: URL
    let peelFile: URL
    let config: URL
    private let directory: TemporaryDirectory

    init(before lines: [String] = []) throws {
        let directory = try TemporaryDirectory()
        let peelFile = SSHFile.url(in: directory.url.appending(path: "Library/Application Support/Peel", directoryHint: .isDirectory))
        let config = directory.url.appending(path: "config")
        let including = SSHFile.lines(including: peelFile, home: URL(filePath: "/var/empty", directoryHint: .isDirectory))
        try (lines + including).joined(separator: "\n").appending("\n").write(to: config, atomically: true, encoding: .utf8)
        folder = directory.url
        self.peelFile = peelFile
        self.config = config
        self.directory = directory
    }

    /// The options ssh would use for `host`, by their names in lowercase, as `ssh -G` prints them.
    func options(for host: String) async throws -> [String: String] {
        let answer = await Subprocess.run(
            "/usr/bin/ssh",
            ["-G", "-F", config.path(percentEncoded: false), host],
            environment: [:],
            timeout: 10
        )
        guard case .success(let output) = answer else { throw POSIXError(.EIO) }
        #expect(output.status == 0, "\(output.errorText)")
        return Dictionary(output.text.split(separator: "\n").compactMap { line in
            line.firstIndex(of: " ").map { (String(line[..<$0]), String(line[line.index(after: $0)...])) }
        }, uniquingKeysWith: { first, _ in first })
    }
}

struct SSHFileTests {
    static let inEffect: [SSHSetting: [String: String]] = [
        .keychain: ["addkeystoagent": "true"],
        .keepAlive: ["serveraliveinterval": "60"],
        .reuseConnections: ["controlmaster": "auto", "controlpersist": "600"],
    ]

    @Test func everySettingIsInEffectForEveryServerOnceItIsOnAndNotBefore() async throws {
        let ssh = try SSHHome()
        #expect(Set(Self.inEffect.keys) == Set(SSHSetting.allCases))
        for setting in SSHSetting.allCases {
            let wanted = try #require(Self.inEffect[setting])
            #expect(SSHFile.write([], to: ssh.peelFile))
            let before = try await ssh.options(for: "example.org")
            #expect(wanted.allSatisfy { before[$0.key] != $0.value }, "\(setting)")
            #expect(SSHFile.write([setting], to: ssh.peelFile))
            let after = try await ssh.options(for: "example.org")
            #expect(wanted.allSatisfy { after[$0.key] == $0.value }, "\(setting)")
        }
        #expect(try await ssh.options(for: "example.org")["controlpath"]?.contains("/.ssh/cm-") == true)
    }

    @Test func whatTheConfigSetsForAServerEarlierStaysFirst() async throws {
        let ssh = try SSHHome(before: ["Host server", "  ServerAliveInterval 10"])
        #expect(SSHFile.write([.keepAlive], to: ssh.peelFile))
        #expect(try await ssh.options(for: "server")["serveraliveinterval"] == "10")
        #expect(try await ssh.options(for: "example.org")["serveraliveinterval"] == "60")
    }

    @Test func theSSHOnThisMacAcceptsEverySetting() async {
        #expect(await SSHFile.accepted() == Set(SSHSetting.allCases))
    }

    @Test func anSSHThatDoesNotAnswerLeavesWhatItAcceptsUnknown() async {
        #expect(await SSHFile.accepted(ssh: "/usr/bin/true") == Set(SSHSetting.allCases))
        #expect(await SSHFile.accepted(ssh: "/usr/bin/false") == [])
        #expect(await SSHFile.accepted(ssh: "/usr/bin/peel-no-such-ssh") == nil)
    }

    /// Another ssh, such as Homebrew's, doesn't know `UseKeychain`: renamed to an option the ssh on this Mac doesn't
    /// know either, Peel's file has to be read all the same.
    @Test func anSSHThatDoesNotKnowAnOptionStillReadsTheFile() async throws {
        let ssh = try SSHHome()
        let unknown = SSHFile.contents(of: Set(SSHSetting.allCases)).replacing("UseKeychain", with: "PeelUnknownOption")
        try FileManager.default.createDirectory(
            at: ssh.peelFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try unknown.write(to: ssh.peelFile, atomically: true, encoding: .utf8)
        #expect(try await ssh.options(for: "example.org")["serveraliveinterval"] == "60")
    }

    @Test func aFileWrittenBeforeTheIgnoreUnknownLineReadsAsBefore() {
        let written = [SSHFile.header, "UseKeychain yes", "AddKeysToAgent yes", "ServerAliveInterval 60"]
        #expect(SSHFile.settings(in: written.joined(separator: "\n") + "\n") == [.keychain, .keepAlive])
    }

    @Test func aFileAnEarlierVersionWroteIsBroughtUpToDateAndOneChangedByHandIsNot() throws {
        let earlier = [SSHFile.header, "UseKeychain yes", "AddKeysToAgent yes"].joined(separator: "\n") + "\n"
        #expect(SSHFile.update(of: earlier) == SSHFile.contents(of: [.keychain]))
        #expect(SSHFile.update(of: SSHFile.contents(of: [.keychain])) == nil)
        #expect(SSHFile.update(of: earlier + "Compression yes\n") == nil)
        #expect(SSHFile.update(of: SSHFile.contents(of: [.keepAlive])) == nil)

        let ssh = try SSHHome()
        try FileManager.default.createDirectory(
            at: ssh.peelFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try earlier.write(to: ssh.peelFile, atomically: true, encoding: .utf8)
        SSHFile.bringUpToDate(ssh.peelFile)
        #expect(try String(contentsOf: ssh.peelFile, encoding: .utf8) == SSHFile.contents(of: [.keychain]))
    }

    @Test func theLinesNameTheFileFromTheHomeOrByItsWholePath() {
        let home = URL(filePath: "/Users/example", directoryHint: .isDirectory)
        let file = SSHFile.url(in: home.appending(path: "Library/Application Support/Peel", directoryHint: .isDirectory))
        #expect(SSHFile.lines(including: file, home: home) == ["Match all", "  Include \"~/Library/Application Support/Peel/Terminal/ssh_config\""])
        #expect(SSHFile.lines(including: URL(filePath: "/Volumes/Other/Peel/Terminal/ssh_config"), home: home)
            == ["Match all", "  Include \"/Volumes/Other/Peel/Terminal/ssh_config\""])
    }

    @Test func theIncludeIsFoundUnlessItIsACommentOrOnlyMentionsTheFile() throws {
        let ssh = try SSHHome()
        let home = URL(filePath: "/var/empty", directoryHint: .isDirectory)
        #expect(SSHFile.isIncluded(ssh.peelFile, from: ssh.config, home: home))
        let user = ssh.folder.appending(path: "user")
        for (text, found) in [
            ("Match all\n  Include ~/Library/Application\\ Support/Peel/Terminal/ssh_config\n", true),
            ("Include=\"~/Library/Application Support/Peel/Terminal/ssh_config\"\n", true),
            ("# Include \"~/Library/Application Support/Peel/Terminal/ssh_config\"\n", false),
            ("Host server\n  IdentityFile ~/Library/Application Support/Peel/Terminal/ssh_config\n", false),
        ] {
            try text.write(to: user, atomically: true, encoding: .utf8)
            let home = URL(filePath: "/Users/example", directoryHint: .isDirectory)
            let file = SSHFile.url(in: home.appending(path: "Library/Application Support/Peel", directoryHint: .isDirectory))
            #expect(SSHFile.isIncluded(file, from: user, home: home) == found, "\(text)")
        }
    }

    @Test func theFileReadsBackAsTheSettingsWrittenInIt() {
        for setting in SSHSetting.allCases {
            #expect(SSHFile.settings(in: SSHFile.contents(of: [setting])) == [setting])
        }
        #expect(SSHFile.settings(in: SSHFile.contents(of: Set(SSHSetting.allCases))) == Set(SSHSetting.allCases))
        #expect(SSHFile.settings(in: SSHFile.contents(of: [])).isEmpty)
    }

    @Test func aMissingFileHasNothingOnAndOneThatCannotBeReadIsNotKnown() throws {
        let directory = try TemporaryDirectory()
        let file = SSHFile.url(in: directory.url)
        #expect(SSHFile.read(file) == [])
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        #expect(SSHFile.read(file) == nil)
    }
}
