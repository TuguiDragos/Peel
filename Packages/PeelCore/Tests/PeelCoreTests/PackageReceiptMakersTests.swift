import Foundation
@testable import PeelCore
import Synchronization
import Testing

struct PackageReceiptMakersTests {
    /// The receipt of `package`, which wrote the programs `teams` names, each signed by its team.
    private func receipt(
        _ package: String, in directory: borrowing TemporaryDirectory, signedBy teams: KeyValuePairs<String, String>,
        installed: [InstalledApp] = [], asked: @escaping @Sendable (URL) -> Void = { _ in }
    ) async throws -> PackageReceipt? {
        let volume = PathPattern.canonical(directory.url)
        for (name, _) in teams {
            try directory.setPermissions(0o755, of: directory.file("Library/\(package)/\(name)"))
        }
        let listing = ([package] + teams.map { "\(package)/\($0.key)" }).joined(separator: "\n")
        let signers = Dictionary(uniqueKeysWithValues: teams.map { ($0.key, $0.value) })
        let pkgutil: PackageReceipts.Pkgutil = { arguments in
            switch arguments.first {
            case "--pkgs-plist": PkgutilAnswer.packages(package)
            case "--pkg-info-plist":
                PkgutilAnswer.packageInfo(package, volume: volume.path(percentEncoded: false), location: "Library")
            case "--files": listing
            default: nil
            }
        }
        let scan = await PackageReceipts.list(
            exclusions: .none, pkgutil: pkgutil,
            environment: SearchEnvironment(homeDirectory: volume.appending(path: "home"), rootDirectory: volume),
            teamOf: { url in
                asked(url)
                return signers[url.lastPathComponent]
            },
            installedApps: { installed }
        )
        return scan.receipts.first
    }

    @Test func aPackageOfAProductWhoseAppsLeftNamesItsMakersStep() async throws {
        let directory = try TemporaryDirectory()

        let found = try await receipt(
            "com.box.desktop.installer", in: directory, signedBy: ["helper": "ABCDE12345", "agentd": "M683GB7CPW"]
        )

        #expect(found?.makersUninstaller?.maker == "Box")
        #expect(found?.makersUninstaller?.step == .fromTheMakersPage)
    }

    @Test func bitdefendersAgentPackageIsBitdefenders() async throws {
        let directory = try TemporaryDirectory()

        let found = try await receipt("com.bitdefender.agent", in: directory, signedBy: ["bdagentd": "GUNFMW623Y"])

        #expect(found?.makersUninstaller?.maker == "Bitdefender")
    }

    @Test func anotherAppOfTheMakerStillInstalledMayUseThePackage() async throws {
        let directory = try TemporaryDirectory()
        let app = InstalledApp(
            url: URL(filePath: "/Applications/Box Tools.app"), bundleIdentifier: "com.box.tools", name: "Box Tools",
            teamIdentifier: "M683GB7CPW"
        )

        let found = try await receipt(
            "com.box.desktop.installer", in: directory, signedBy: ["agentd": "M683GB7CPW"], installed: [app]
        )

        #expect(found != nil)
        #expect(found?.makersUninstaller == nil)
    }

    @Test func aPackageNamedLikeAProductIsNotItsWithoutItsMakersSignature() async throws {
        let directory = try TemporaryDirectory()

        let found = try await receipt("com.box.desktop.installer", in: directory, signedBy: ["agentd": "ABCDE12345"])

        #expect(found != nil)
        #expect(found?.makersUninstaller == nil)
    }

    @Test func whatOnlyAnAdministratorMovesIsLeftToTheMakersStep() throws {
        let item = PackageReceipt.Item(
            url: URL(filePath: "/Library/Box/agentd"), size: 16, requiresPrivileges: true, refusal: nil,
            heldBack: .beyondTheHelper, removedElsewhere: nil
        )
        var receipt = PackageReceipt(
            identifier: "com.box.desktop.installer", version: "1", installDate: nil, volume: URL(filePath: "/"),
            items: [item]
        )
        #expect(receipt.itemsLeftForAnAdministrator == [item])

        receipt.makersUninstaller = MakersUninstaller.ofWhatIsLeft(team: "M683GB7CPW", part: receipt.identifier)

        #expect(receipt.makersUninstaller != nil)
        #expect(receipt.itemsLeftForAnAdministrator.isEmpty)
    }

    @Test func aPackageNoMakerNamesHasNoSignatureRead() async throws {
        let directory = try TemporaryDirectory()
        let asked = Mutex(0)

        let found = try await receipt("org.example.agent", in: directory, signedBy: ["agentd": "M683GB7CPW"]) { _ in
            asked.withLock { $0 += 1 }
        }

        #expect(found != nil)
        #expect(found?.makersUninstaller == nil)
        #expect(asked.withLock { $0 } == 0)
    }
}
