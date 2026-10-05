import Foundation
@testable import PeelCore
@testable import PeelPrivileged
import Testing

struct DesktopWalletTests {
    @Test(arguments: [
        "Library/Preferences/hardhat-nodejs/vars.json",
        "Library/Preferences/hardhat-nodejs/keystore.json",
        "Library/Preferences/hardhat-nodejs/dev.keystore.json",
        "Library/Preferences/hardhat-nodejs/hardhat.checksum",
    ])
    func refusesWhatAWalletKeeps(_ key: String) throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try directory.file("home/" + key)
        let guardian = RemovalGuard(
            environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root"))
        )
        let file = home.appending(path: key)
        let folder = file.deletingLastPathComponent()
        let around = folder.deletingLastPathComponent().path(percentEncoded: false)

        #expect(!guardian.allowsRemoval(of: file))
        #expect(!guardian.allowsRemoval(of: folder))
        #expect(ProtectedData.holds(around, home: home.path(percentEncoded: false)))
    }

    @Test(arguments: [
        "Library/Caches/hardhat-nodejs/compilers-v2/list.json",
    ])
    func leavesWhatComesBackOnItsOwn(_ cache: String) throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try directory.file("home/" + cache)
        let guardian = RemovalGuard(
            environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root"))
        )

        #expect(guardian.allowsRemoval(of: home.appending(path: cache)))
    }
}
