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
        ".fuel/wallets/.wallet",
        ".osmosisd/keyring-file/main.info",
        ".osmosisd/keyring-test/main.info",
        ".osmosisd/config/priv_validator_key.json",
        "Library/Application Support/Namecoin/wallets/wallet.dat",
        "Library/Application Support/Namecoin/wallet.dat",
        "Library/Application Support/Groestlcoin/wallets/wallet.dat",
        "Library/Application Support/Groestlcoin/wallet.dat",
        "Library/Application Support/Liquid/wallets/wallet.dat",
        "Library/Application Support/Liquid/wallet.dat",
        "Library/Application Support/Elements/wallets/wallet.dat",
        "Library/Application Support/Elements/wallet.dat",
        ".electrum-abc/wallets/default_wallet",
        ".electrum-sv/wallets/default_wallet",
        ".electrum-nmc/wallets/default_wallet",
        "Library/Application Support/Dcrwallet/mainnet/wallet.db",
        "Library/Application Support/Dexc/mainnet/dexc.db",
        "Library/Application Support/Dexc/mainnet/assetdb/btc/wallet.db",
        ".ashigaru/config",
        "Library/Application Support/bitcoin_safe/bitcoin/main.wallet",
        "Library/Application Support/joinmarket/wallets/wallet.jmdat",
        ".cashu/wallet/wallet.sqlite3",
        "Library/Application Support/Kaspawallet/kaspa-mainnet/keys.json",
        ".grim/main/wallets/1767225600/wallet_data/wallet.seed",
        "Library/Nano/wallets.ldb",
        "Library/Nano/backup/5F2B1E9C0D4A7B3E6C8D1F0A2B4C6E8D0F1A3B5C7D9E0F2A4B6C8D0E2F4A6B8C.json",
        "Library/Application Support/Bisq2/db/private/key_bundle_store.protobuf",
        "Library/Application Support/Blockstream/Green/wallets/0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0",
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
        ".fuel/toolchains/latest-aarch64-apple-darwin/bin/forc",
        ".osmosisd/data/application.db/000001.log",
        "Library/Application Support/Namecoin/blocks/blk00000.dat",
        "Library/Application Support/Liquid/blocks/blk00000.dat",
        ".electrum-abc/blockchain_headers",
        ".electrum-nmc/blockchain_headers",
        "Library/Application Support/Dexc/mainnet/logs/dexc.log",
        "Library/Application Support/joinmarket/logs/joinmarket.log",
        ".grim/main/chain_data/multi_lmdb/data.mdb",
        "Library/Nano/data.ldb",
        "Library/Application Support/Bisq2/bisq.log",
        "Library/Application Support/Blockstream/Green/cache/data8/a/3f9c2b1e7d4a.d",
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

    @Test func safetyMDCountsEveryPlace() throws {
        let page = try String(contentsOf: StringCatalogTests.repository.appending(path: "SAFETY.md"), encoding: .utf8)
        let counts = page.matches(of: /(\d+) places in (all|the table)/).compactMap { Int($0.output.1) }

        #expect(counts.count == 2)
        #expect(counts.allSatisfy { $0 == ProtectedData.walletKeys.count }, "\(counts) against \(ProtectedData.walletKeys.count)")
    }
}
