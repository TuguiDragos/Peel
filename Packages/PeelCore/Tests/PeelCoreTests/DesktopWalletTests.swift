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
        "Library/Application Support/DashCore/backups/wallet.dat.2026-10-05-12-30",
        "Library/Application Support/PIVX/wallet.dat",
        "Library/Application Support/PIVX/wallets/wallet.dat",
        "Library/Application Support/PIVX/backups/wallet.dat.2026-10-05-12-30",
        "Library/Application Support/firo/wallet.dat",
        "Library/Application Support/firo/backups/wallet.dat.2026-10-05-12-30",
        "Library/Application Support/zcoin/wallet.dat",
        "Library/Application Support/zcoin/backups/wallet.dat.2026-10-05-12-30",
        ".walletwasabi/client/WalletBackups/Wallet.json",
        ".gingerwallet/client/Wallets/Wallet.json",
        ".gingerwallet/client/WalletBackups/Wallet.json",
        "Library/Application Support/Zcash/zecwallet-light-wallet.dat",
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
        "Library/Application Support/DashCore/blocks/blk00000.dat",
        "Library/Application Support/PIVX/blocks/blk00000.dat",
        "Library/Application Support/firo/blocks/blk00000.dat",
        ".walletwasabi/client/BitcoinStore/Main/IndexStore/MatureIndex.dat",
        ".gingerwallet/client/BitcoinStore/Main/IndexStore/MatureIndex.dat",
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
