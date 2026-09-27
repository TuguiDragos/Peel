import Foundation
import Synchronization

/// The places nothing may be removed from, wherever the request comes from. This lives beside the helper on
/// purpose: a program running as root must not depend on its caller to tell it what is irreplaceable.
public enum ProtectedData: Sendable {
    /// The folders every account starts with. Each folder itself is never removed, whatever it holds, and an
    /// app whose name matches one never claims it.
    public static let accountFolders = [
        "Applications", "Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures", "Public",
    ]

    /// Folders in a user's home, most of them in Library, that hold work nothing can bring back. iCloud Drive
    /// is the worst of them: a file removed there is removed from the user's other devices too.
    public static let homeFolders = [
        "Library/Mobile Documents",
        "Library/CloudStorage",
        "Library/Keychains",
        "Library/Passes",
        "Library/Spelling",
        "Library/KeyboardServices",
        "Library/Autosave Information",
        "Library/Application Support/MobileSync",
        "Library/Application Support/AddressBook",
        "Library/Application Support/CallHistoryDB",
        "Library/Mail",
        "Library/Messages",
        "Library/Safari",
        "Library/Containers/com.apple.Safari/Data/Library/Safari",
        "Library/Calendars",
        "Library/Reminders",
        "Library/Contacts",
        "Library/Shortcuts",
        "Library/Group Containers/group.is.workflow.shortcuts",
        "Library/Group Containers/group.is.workflow.my.app",
        "Library/HomeKit",
        "Library/Accounts",
        "Library/Finance",
        "Library/IdentityServices",
        "Library/Application Support/CallHistoryTransactions",
        "Library/Application Support/FaceTime",
        "Library/Containers/com.apple.freeform",
        "Library/Containers/com.apple.journal",
        "Library/Containers/com.apple.Stickies/Data/Library/Stickies",
        ".Trash",
        ".ssh",
        ".gnupg",
        ".aws",
        ".password-store",
    ]

    /// Single keys and secrets, named one at a time rather than protecting the folder around each, since some
    /// of those folders are caches worth cleaning: `~/.m2/repository` and `~/.android/avd` are large and come
    /// back on their own. `holds(_:home:)` is what stops a folder from going and taking the key with it.
    ///
    /// - `debug.keystore` signs every Android debug build. Android Studio replaces a missing one with a new
    ///   key, whose SHA-1 differs from the fingerprint Firebase and the Google Maps API have on file, and
    ///   debug builds already installed refuse to update to a build signed with it.
    /// - `settings-security.xml` holds Maven's master password, the only key to the encrypted passwords in
    ///   `settings.xml`.
    /// - `gradle.properties` is where Gradle's signing documentation says to keep `signing.keyId`,
    ///   `signing.password`, and `signing.secretKeyRingFile`, rather than in a project.
    /// - `.git-credentials` is git's credential store, which keeps passwords in plain text
    ///   (`man git-credential-store`).
    public static let homeKeys = [
        ".android/debug.keystore",
        ".m2/settings-security.xml",
        ".gradle/gradle.properties",
        ".git-credentials",
    ]

    /// Where desktop wallets and key tools keep their keys, as each project's own documentation or source says.
    /// Losing one loses what it holds unless its seed phrase was kept somewhere else, so each is refused, and so
    /// is every folder holding one, while what sits beside it and comes back on its own, such as a downloaded
    /// blockchain, can still go. A whole folder is named where the keys lie at its top among everything else.
    public static let walletKeys = [
        "Library/Application Support/Bitcoin/wallets",
        "Library/Application Support/Bitcoin/wallet.dat",
        "Library/Application Support/Litecoin/wallets",
        "Library/Application Support/Litecoin/wallet.dat",
        "Library/Application Support/Dogecoin/wallet.dat",
        "Library/Application Support/DashCore/wallets",
        "Library/Application Support/DashCore/wallet.dat",
        "Library/Application Support/Zcash/wallet.dat",
        "Library/Application Support/Zcash/zingo-wallet.dat",
        ".zallet/wallet.db",
        ".zallet/encryption-identity.txt",
        "Library/Containers/me.hanh.ywallet.ywallet/Data/Library/Application Support/me.hanh.ywallet.ywallet/databases",
        "Monero/wallets",
        "Library/Application Support/MyMonero",
        ".electrum/wallets",
        ".electrum-ltc/wallets",
        ".electrum-grs/wallets",
        ".electron-cash/wallets",
        ".electrum-dash/wallets",
        ".sparrow/wallets",
        ".local/share/sparrow/wallets",
        ".walletwasabi/client/Wallets",
        ".specter/wallets",
        ".specter/devices",
        "Library/Application Support/Bisq/btc_mainnet/wallet",
        "Library/Application Support/Bisq/btc_mainnet/keys",
        "Library/Application Support/Liana/bitcoin",
        "Library/Application Support/Nunchuk",
        "Library/Application Support/Blockstream/Green/wallets2",
        "Library/Containers/io.bluewallet.bluewallet/Data/Library/Caches/keyvalue.realm",
        "Library/Application Support/Exodus/exodus.wallet",
        "Library/Application Support/Exodus/Backups",
        "Library/Application Support/atomic",
        "Library/Application Support/@onekeyhq/desktop",
        "Library/Application Support/Frame/signers",
        "Library/Application Support/rabby-desktop",
        "Library/Ethereum/keystore",
        ".foundry/keystores",
        "Library/Preferences/hardhat-nodejs/keystore.json",
        ".phoenix/seed.dat",
        "Library/Application Support/Lnd/data",
        ".lightning/bitcoin/hsm_secret",
        ".lightning/bitcoin/lightningd.sqlite3",
        ".lightning/bitcoin/emergency.recover",
        "Library/Application Support/albyhub",
        ".config/solana/id.json",
        ".sui/sui_config/sui.keystore",
        ".aptos/config.yaml",
        ".near-credentials",
        ".tezos-client/secret_keys",
        ".gaia/keyring-file",
        ".gaia/keyring-test",
        ".gaia/config/priv_validator_key.json",
        "Library/Application Support/Daedalus Mainnet/wallets",
        "Library/Application Support/decrediton/wallets",
        ".chia_keys",
        ".grin/main/wallet_data",
        ".kaspa",
    ]

    /// Every protected place named from a home folder: `homeFolders`, `homeKeys` and `walletKeys`. `refuses`,
    /// `holds` and `RemovalGuard` all read it, so a place added to one of those lists is protected by all three.
    public static let homeTrees = homeFolders + homeKeys + walletKeys

    /// Hidden items in the home folder that belong to no single app: shells, git, and the folders many tools
    /// share. Never removed on any app's behalf, but what sits inside `.config`, `.cache`, and `.local` still
    /// can be, so this is an exact match and not a tree.
    public static let sharedHomeItems = [
        ".config", ".cache", ".local", ".CFUserTextEncoding",
        ".kube", ".kube/config",
        ".zshrc", ".zprofile", ".zshenv", ".zsh_history", ".zsh_sessions",
        ".bashrc", ".bash_profile", ".bash_history", ".profile",
        ".gitconfig", ".gitignore_global", ".netrc", ".npmrc",
    ]

    /// Folders outside any home that hold work nothing can bring back, for every account on the Mac.
    public static let systemFolders = ["/Library/Keychains"]

    /// True for a name Apple writes for its own things: `com.apple.` after an optional team and an optional
    /// `group.`, `groups.`, or `systemgroup.`.
    public static func isApplesName(_ name: String) -> Bool {
        var name = Substring(name.lowercased())
        if let dot = name.firstIndex(of: "."), name[..<dot].count == 10, name[..<dot].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
            name = name[name.index(after: dot)...]
        }
        if let prefix = ["group.", "groups.", "systemgroup."].first(where: name.hasPrefix) {
            name = name.dropFirst(prefix.count)
        }
        return name.hasPrefix("com.apple.")
    }

    /// True at or inside one of Apple's own group containers, where the system's apps keep the user's data,
    /// such as notes, reminders, recordings, and calendars. Apple moves them between releases, so they are
    /// recognized by the shape of their name, not by a list. Expects the path in lowercase.
    public static func isInAnApplesGroupContainer(_ spelling: String) -> Bool {
        let names = PathComponents.of(spelling)
        return names.indices.contains { index in
            index + 2 < names.endIndex && names[index] == "library" && names[index + 1] == "group containers"
                && isApplesName(names[index + 2])
        }
    }

    /// True at or inside the `Data/Documents` folder of a sandboxed app's container, where the app keeps what
    /// the user made. The path is compared folder by folder, split on the slash byte, because Swift reads a
    /// slash and a combining mark after it as one `Character`. Expects the path in lowercase.
    public static func isInAContainersDocuments(_ spelling: String) -> Bool {
        let folders = PathComponents.of(spelling)
        return folders.indices.contains { index in
            index + 4 < folders.endIndex && folders[index] == "library" && folders[index + 1] == "containers"
                && folders[index + 3] == "data" && folders[index + 4] == "documents"
        }
    }

    /// True for a sandboxed app's container, or the `Data` folder inside it, while `Data/Documents` holds
    /// anything or cannot be read. Moving either would take the user's documents along. It reads the disk, so
    /// it needs the path as spelled on disk, not lowercased.
    public static func holdsAContainersDocuments(_ path: String) -> Bool {
        let components = PathComponents.of(path)
        guard
            let containers = components.lastIndex(where: { $0.lowercased() == "containers" }),
            containers >= 1, components[containers - 1].lowercased() == "library",
            components.count > containers + 1
        else { return false }
        let inside = components[(containers + 2)...]
        guard inside.isEmpty || (inside.count == 1 && inside[inside.startIndex].lowercased() == "data") else { return false }

        let documents = "/" + components[...(containers + 1)].joined(separator: "/") + "/Data/Documents"
        var info = stat()
        guard lstat(documents, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return false }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: documents) else { return true }
        return names.contains { $0 != ".DS_Store" && $0 != ".localized" }
    }

    /// Work that lives in a cache folder and nowhere else. A JetBrains IDE and Android Studio keep
    /// `LocalHistory` beside their caches: the edits they recorded, which are in no repository. Deno keeps
    /// `location_data` in its cache folder: `localStorage`, and the database behind `Deno.openKv()`.
    static let workKeptInCaches: Set<String> = ["localhistory", "location_data"]

    /// True for a path under a `Caches` folder that is at or inside one of those folders, or holds one a level
    /// or two down, which is how deep they sit (`Caches/JetBrains/<product>/LocalHistory`). It reads the disk,
    /// so it needs the path as spelled on disk.
    public static func holdsWorkKeptInACache(_ path: String) -> Bool {
        let components = PathComponents.of(path).map { $0.lowercased() }
        guard let caches = components.lastIndex(of: "caches"), caches + 1 < components.count else { return false }
        if components[(caches + 1)...].contains(where: workKeptInCaches.contains) { return true }

        let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        return names.contains { name in
            if workKeptInCaches.contains(name.lowercased()) { return true }
            let deeper = (try? FileManager.default.contentsOfDirectory(atPath: path + "/" + name)) ?? []
            return deeper.contains { workKeptInCaches.contains($0.lowercased()) }
        }
    }

    /// True for a file of the global preferences domain: `.GlobalPreferences.plist`, its `_m` twin, and the
    /// ByHost one, which carries the Mac's host UUID in its name. They belong to no app. Expects the path in
    /// lowercase.
    public static func isGlobalPreferences(_ spelling: String) -> Bool {
        let name = (spelling as NSString).lastPathComponent
        guard name.hasPrefix(".globalpreferences"), name.hasSuffix(".plist") else { return false }
        let folder = (spelling as NSString).deletingLastPathComponent
        return folder.hasSuffix("/library/preferences") || folder.hasSuffix("/library/preferences/byhost")
    }

    private static let sharedHomeItemNames = Set(sharedHomeItems.map { $0.lowercased() })

    /// True for one of `sharedHomeItems` exactly, never for anything inside one.
    public static func isSharedHomeItem(_ path: String, home: String) -> Bool {
        let home = ((home as NSString).standardizingPath).lowercased()
        let homeNames = PathComponents.of(home)
        return spellings(of: path).contains { spelling in
            let names = PathComponents.of(spelling)
            guard names.count == homeNames.count + 1, names.starts(with: homeNames), let name = names.last else { return false }
            return sharedHomeItemNames.contains(name)
        }
    }

    /// True when removing `path` would take something protected with it, as removing `~/.m2` would take
    /// `~/.m2/settings-security.xml`. `refuses(_:home:)` asks the other question: whether the path is, or sits
    /// inside, something protected. The two stay apart because scanners also use `refuses` to decide whether
    /// to look inside a folder, and every folder from `/` down to the home folder holds something protected.
    public static func holds(_ path: String, home: String) -> Bool {
        spellings(of: path).contains { spelling in
            let names = PathComponents.of(spelling)
            let holdsIt = { (tree: [String]) in tree.count > names.count && tree.starts(with: names) }
            for home in homes(of: spelling, given: home) where trees(under: home).sitInside(names) {
                return true
            }
            return systemFolders.contains { holdsIt(PathComponents.of($0.lowercased())) }
        }
    }

    /// The protected trees under one home, looked up by a path's own names rather than compared with each tree.
    /// Names compare as strings, so a composed letter still matches its decomposed spelling.
    private struct Trees {
        let trees: Set<[String]>
        /// Every folder a tree sits in, from the root down.
        let ancestors: Set<[String]>

        init(_ trees: [[String]]) {
            self.trees = Set(trees)
            ancestors = Set(trees.flatMap { tree in (0..<tree.count).map { Array(tree[..<$0]) } })
        }

        /// True when `names` is a tree or sits inside one.
        func contain(_ names: [String]) -> Bool {
            names.indices.contains { trees.contains(Array(names[...$0])) }
        }

        /// True when a tree sits inside `names`.
        func sitInside(_ names: [String]) -> Bool {
            ancestors.contains(names)
        }
    }

    /// The protected trees for each home, built once, since `refuses` is asked of every entry a scan looks at.
    /// A path can name any home under `/Users`, so the cache is capped rather than left to grow.
    private static let treesByHome = Mutex<[String: Trees]>([:])

    private static func trees(under home: String) -> Trees {
        treesByHome.withLock { cache in
            if let trees = cache[home] { return trees }
            let trees = Trees(homeTrees.map { PathComponents.of((home as NSString).appendingPathComponent($0).lowercased()) })
            if cache.count >= 32 { cache.removeAll() }
            cache[home] = trees
            return trees
        }
    }

    /// Extensions of the libraries and packages that hold someone's whole photo, music, or video collection.
    /// `photolibrary` and `aplibrary` are iPhoto's and Aperture's, which Photos still opens.
    public static let extensions = [
        "photoslibrary", "photolibrary", "migratedphotolibrary", "musiclibrary", "tvlibrary", "imovielibrary",
        "fcpbundle", "aplibrary",
    ]

    /// True for a folder that holds one of those libraries a level or two down, as in
    /// `<year>/<name>.photoslibrary`. A library can sit anywhere, so no list of places can protect the folder
    /// around one, and this looks inside the folder instead. It reads the disk.
    public static func holdsALibrary(_ path: String) -> Bool {
        let isALibrary = { (name: String) in extensions.contains { name.lowercased().hasSuffix("." + $0) } }
        let folder = URL(filePath: path, directoryHint: .isDirectory)
        let children = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return children.contains { child in
            if isALibrary(child.lastPathComponent) { return true }
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return false }
            let deeper = (try? FileManager.default.contentsOfDirectory(atPath: child.path(percentEncoded: false))) ?? []
            return deeper.contains(where: isALibrary)
        }
    }

    /// The lowercase names a check should compare for `path`. macOS keeps `/var`, `/tmp`, and `/etc` as
    /// symbolic links into `/private`, and disks are case-insensitive by default, so one file has several
    /// names. A check that knew only one of them could be bypassed by writing another.
    public static func spellings(of path: String) -> Set<String> {
        var names = privateNames(of: (path as NSString).standardizingPath)
        let resolved = (path as NSString).resolvingSymlinksInPath
        if resolved != path {
            names.formUnion(privateNames(of: resolved))
        }
        return Set(names.map { name in
            let trimmed = name.count > 1 && name.hasSuffix("/") ? String(name.dropLast()) : name
            return trimmed.lowercased()
        })
    }

    private static func privateNames(of path: String) -> Set<String> {
        for link in ["/var", "/tmp", "/etc"] {
            if PathComponents.isPath(path, atOrInside: link) {
                return [path, "/private" + path]
            }
            let inPrivate = "/private" + link
            if PathComponents.isPath(path, atOrInside: inPrivate) {
                return [path, String(path.dropFirst("/private".count))]
            }
        }
        return [path]
    }

    /// True for a path at or inside anything protected here: the home and system folders, the keys, a wallet
    /// extension's storage, a media library, a global preferences file, or one of Apple's group containers.
    /// Running as root, the helper can see every account on the Mac, so a home folder is any folder directly
    /// inside `/Users`, as well as the one given.
    public static func refuses(_ path: String, home: String) -> Bool {
        spellings(of: path).contains { spelling in
            let names = PathComponents.of(spelling)
            if names.contains(where: { name in extensions.contains { name.hasSuffix("." + $0) } }) { return true }
            if isGlobalPreferences(spelling) || isInAnApplesGroupContainer(spelling) { return true }
            if isInsideAWalletExtension(names) { return true }

            for home in homes(of: spelling, given: home) where trees(under: home).contain(names) {
                return true
            }
            return systemFolders.contains { names.starts(with: PathComponents.of($0.lowercased())) }
        }
    }

    /// The home the caller named, plus whichever account the path itself sits in.
    private static func homes(of path: String, given home: String) -> [String] {
        var homes = [((home as NSString).standardizingPath).lowercased()]
        let components = PathComponents.of(path)
        if components.count >= 2, components[0] == "users" {
            homes.append("/users/" + components[1])
        }
        return homes
    }
}
