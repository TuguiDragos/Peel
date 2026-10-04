import Foundation
@testable import PeelCore
import PeelPrivileged
import Testing

private struct SSHHome {
    let folder: URL
    let peelFile: URL
    let config: URL

    init(before lines: [String] = []) throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "SSHFileTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        peelFile = SSHFile.url(in: folder.appending(path: "Library/Application Support/Peel", directoryHint: .isDirectory))
        config = folder.appending(path: "config")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let including = SSHFile.lines(including: peelFile, home: URL(filePath: "/var/empty", directoryHint: .isDirectory))
        try (lines + including).joined(separator: "\n").appending("\n").write(to: config, atomically: true, encoding: .utf8)
    }

    /// The options ssh would use for `host`, by their names in lowercase, as `ssh -G` prints them.
    func options(for host: String) async throws -> [String: String] {
        let answer = await Subprocess.run("/usr/bin/ssh", ["-G", "-F", config.path(percentEncoded: false), host], environment: [:], timeout: 10)
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
        let folder = FileManager.default.temporaryDirectory.appending(path: "SSHFileTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let file = SSHFile.url(in: folder)
        #expect(SSHFile.read(file) == [])
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        #expect(SSHFile.read(file) == nil)
    }
}
