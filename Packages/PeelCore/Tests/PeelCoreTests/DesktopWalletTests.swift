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
        "Library/Application Support/Haveno/xmr_mainnet/wallet/haveno_XMR.keys",
        "Library/Application Support/Haveno/xmr_mainnet/keys/sig.key",
        "Library/Application Support/Haveno-reto/xmr_mainnet/wallet/haveno_XMR.keys",
        "Library/Application Support/Haveno-reto/xmr_mainnet/keys/sig.key",
        "Library/Containers/com.cypherstack.stackwallet/Data/Library/stackwallet/isar/desktopStore.isar",
        "Library/stackwallet/isar/desktopStore.isar",
        "Library/Application Support/umami/Local Storage/leveldb/000003.log",
        "Library/Application Support/umami/Local Storage/backup_leveldb.json",
        "Library/Application Support/MyTonWallet/IndexedDB/file__0.indexeddb.leveldb/000003.log",
        ".eclair/node_seed.dat",
        ".eclair/channel_seed.dat",
        ".eclair/seed.dat",
        ".eclair/mainnet/eclair.sqlite.bak",
        ".lighthouse/mainnet/validators/0x87a5/voting-keystore.json",
        ".lighthouse/mainnet/validators/slashing_protection.sqlite",
        ".lighthouse/mainnet/secrets/0x87a5",
        ".lighthouse/mainnet/wallets/main/wallet.json",
        "Library/Eth2Validators/prysm-wallet-v2/accounts/all-accounts.keystore.json",
        "Library/Application Support/ethereum2/wallets/main/wallet.json",
        "Library/Signer/masterseed.json",
        ".ape/accounts/main.json",
        ".brownie/accounts/main.json",
        ".avalanche-cli/key/main.pk",
        ".avalanchego/staking/staker.key",
        ".avalanchego/staking/staker.crt",
        ".config/stellar/identity/carol.toml",
        ".config/soroban/identity/carol.toml",
        ".tezos-signer/secret_keys",
        ".starknet_accounts/starknet_open_zeppelin_accounts.json",
    ])
    func refusesWhatAWalletKeeps(_ key: String) throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        try directory.file("home/" + key)
        let guardian = RemovalGuard(
            environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url.appending(path: "root"))
        )
        var item = home.appending(path: key)

        while item.path(percentEncoded: false).count > home.path(percentEncoded: false).count {
            #expect(!guardian.allowsRemoval(of: item), "\(item.path(percentEncoded: false)) may be removed")
            item = item.deletingLastPathComponent()
        }
    }

    @Test(arguments: [
        "Library/Caches/hardhat-nodejs/compilers-v2/list.json",
        "Library/Application Support/DashCore/blocks/blk00000.dat",
        "Library/Application Support/PIVX/blocks/blk00000.dat",
        "Library/Application Support/firo/blocks/blk00000.dat",
        ".walletwasabi/client/BitcoinStore/Main/IndexStore/MatureIndex.dat",
        ".gingerwallet/client/BitcoinStore/Main/IndexStore/MatureIndex.dat",
        "Library/Application Support/Haveno-reto/xmr_mainnet/haveno.log",
        "Library/Containers/com.cypherstack.stackwallet/Data/Library/Caches/thumbnail.png",
        ".lighthouse/mainnet/beacon/chain_db/000001.sst",
        ".brownie/packages/OpenZeppelin/openzeppelin-contracts@4.9.0/package.json",
        ".avalanchego/db/mainnet/v1.4.5/000001.log",
        ".avalanche-cli/logs/avalanche.log",
        ".config/stellar/network/testnet.toml",
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
