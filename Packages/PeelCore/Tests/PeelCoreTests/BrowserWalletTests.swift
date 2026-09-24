import Foundation
@testable import PeelCore
@testable import PeelPrivileged
import Testing

/// A wallet extension keeps its vault inside a browser profile. The vault, the profile, and every folder around it
/// are refused, while the rest of what a browser keeps can still go.
struct BrowserWalletTests {
    private let metaMask = WalletIDs.metaMask
    /// An ad blocker, which holds no wallet.
    private let adBlocker = "cjpalhdlnbpafiamejdnhcphjbkeiagm"

    private func guardian(in directory: borrowing TemporaryDirectory) -> RemovalGuard {
        RemovalGuard(environment: SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        ))
    }

    private func refused(_ paths: [String], allowed: [String], in directory: borrowing TemporaryDirectory) {
        let guardian = guardian(in: directory)
        for path in paths {
            #expect(!guardian.allowsRemoval(of: directory.url.appending(path: path)), "\(path) may be removed")
        }
        for path in allowed {
            #expect(guardian.allowsRemoval(of: directory.url.appending(path: path)), "\(path) is refused")
        }
    }

    /// Chrome keeps a profile two levels inside its maker's folder, and an extension's `storage.local` in the
    /// profile's `Local Extension Settings`. `Local Storage` is shared by every extension, so it stays too.
    @Test func aChromiumProfileWithAWalletStaysWithEveryFolderAroundIt() throws {
        let directory = try TemporaryDirectory()
        let chrome = "home/Library/Application Support/Google/Chrome"
        try directory.file("\(chrome)/Local State")
        try directory.file("\(chrome)/Default/Local Extension Settings/\(metaMask)/000003.log")
        try directory.file("\(chrome)/Default/Local Storage/leveldb/000005.ldb")
        try directory.file("\(chrome)/Default/Cache/Cache_Data/data_0", bytes: 4_096)
        try directory.file("\(chrome)/Profile 1/Local Extension Settings/\(adBlocker)/000003.log")
        try directory.file("\(chrome)/Profile 1/Local Storage/leveldb/000005.ldb")

        refused([
            "home/Library/Application Support/Google",
            chrome,
            "\(chrome)/Default",
            "\(chrome)/Default/Local Extension Settings",
            "\(chrome)/Default/Local Extension Settings/\(metaMask)",
            "\(chrome)/Default/Local Extension Settings/\(metaMask)/000003.log",
            "\(chrome)/Default/Local Storage",
            "\(chrome)/Default/Local Storage/leveldb/000005.ldb",
        ], allowed: [
            "\(chrome)/Default/Cache",
            "\(chrome)/Profile 1",
            "\(chrome)/Profile 1/Local Storage",
        ], in: directory)
    }

    /// A wallet can keep its vault in IndexedDB instead, under any of the names Chromium gives an origin's store.
    @Test func everyIndexedDBStoreOfAWalletCounts() throws {
        let profile = "home/Library/Application Support/BraveSoftware/Brave-Browser/Default"
        for store in ["\(metaMask)_0.indexeddb.leveldb", "\(metaMask)_0.indexeddb.blob", "\(metaMask)_0"] {
            let directory = try TemporaryDirectory()
            try directory.file("\(profile)/IndexedDB/chrome-extension_\(store)/000003.log")
            refused([
                "home/Library/Application Support/BraveSoftware",
                "\(profile)/IndexedDB/chrome-extension_\(store)",
            ], allowed: [], in: directory)
        }

        // Another extension's store, or a name that only begins like a wallet's, holds no wallet.
        let directory = try TemporaryDirectory()
        try directory.file("\(profile)/IndexedDB/chrome-extension_\(adBlocker)_0.indexeddb.leveldb/000003.log")
        try directory.file("\(profile)/IndexedDB/chrome-extension_\(metaMask)_1.indexeddb.leveldb/000003.log")
        refused([], allowed: ["home/Library/Application Support/BraveSoftware"], in: directory)
    }

    /// Firefox installs an add-on as `extensions/<ID>.xpi`, and keeps its data in the profile's `storage` under
    /// a name only the profile's settings connect to the add-on.
    @Test func aFirefoxProfileWithAWalletAddOnStays() throws {
        let directory = try TemporaryDirectory()
        let profiles = "home/Library/Application Support/Firefox/Profiles"
        try directory.file("\(profiles)/a1b2.default-release/extensions/\(WalletIDs.metaMaskForFirefox).xpi")
        try directory.file("\(profiles)/a1b2.default-release/storage/default/moz-extension+++5f1c^userContextId=4294967295/idb/1.sqlite")
        try directory.file("\(profiles)/c3d4.work/extensions/uBlock0@raymondhill.net.xpi")
        try directory.file("\(profiles)/c3d4.work/storage/default/moz-extension+++9e2a/idb/1.sqlite")

        refused([
            "home/Library/Application Support/Firefox",
            profiles,
            "\(profiles)/a1b2.default-release",
            "\(profiles)/a1b2.default-release/extensions",
            "\(profiles)/a1b2.default-release/extensions/\(WalletIDs.metaMaskForFirefox).xpi",
            "\(profiles)/a1b2.default-release/storage",
            "\(profiles)/a1b2.default-release/storage/default",
        ], allowed: [
            "\(profiles)/c3d4.work",
            "\(profiles)/c3d4.work/storage",
        ], in: directory)
    }

    /// Brave keeps its own wallet's encrypted recovery phrase in the profile's `Preferences`.
    @Test func bravesOwnWalletKeepsItsProfile() throws {
        let directory = try TemporaryDirectory()
        let brave = "home/Library/Application Support/BraveSoftware/Brave-Browser"
        try directory.file("\(brave)/Default/Preferences", contents: Data(#"{"brave":{"wallet":{"encrypted_mnemonic":"c2VjcmV0"}}}"#.utf8))
        try directory.file("\(brave)/Profile 1/Preferences", contents: Data(#"{"brave":{"new_tab_page":{}}}"#.utf8))

        refused([brave, "\(brave)/Default", "\(brave)/Default/Preferences"], allowed: ["\(brave)/Profile 1"], in: directory)
    }

    /// Opera keeps its first profile in its folder itself, and Arc its profiles in `User Data`.
    @Test func findsAProfileWhereverABrowserKeepsIt() throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Application Support/com.operasoftware.Opera/Local Extension Settings/\(metaMask)/000003.log")
        try directory.file("home/Library/Application Support/Arc/User Data/Default/Local Extension Settings/\(metaMask)/000003.log")

        refused([
            "home/Library/Application Support/com.operasoftware.Opera",
            "home/Library/Application Support/Arc",
        ], allowed: [], in: directory)
    }

    /// Every fingerprint is the SHA-256 of the ID in the comment above it, and no entry is missing one. A Chromium
    /// ID is 32 letters from a to p, which reading an IndexedDB store's name relies on, and an add-on's ID is kept in
    /// lowercase, as the lookup compares it.
    @Test func everyFingerprintIsTheIDAboveIt() throws {
        let extensions = try WalletIDs.entries(of: "walletExtensions")
        let addOns = try WalletIDs.entries(of: "walletAddOns")

        #expect(extensions.count == ProtectedData.walletExtensions.count)
        #expect(Set(extensions.map(\.fingerprint)) == ProtectedData.walletExtensions)
        #expect(addOns.count == ProtectedData.walletAddOns.count)
        #expect(Set(addOns.map(\.fingerprint)) == ProtectedData.walletAddOns)
        for entry in extensions + addOns {
            #expect(ProtectedData.fingerprint(entry.id) == entry.fingerprint, "\(entry.name)")
        }
        #expect(extensions.allSatisfy { $0.id.count == 32 && $0.id.allSatisfy { ("a"..."p").contains($0) } })
        #expect(addOns.allSatisfy { $0.id == $0.id.lowercased() && !$0.id.hasSuffix(".xpi") })
    }
}
