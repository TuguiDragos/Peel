import Foundation
internal import PeelPrivileged

/// Where apps keep what may exist only on this Mac: local mail, message history, password vaults and sign-in codes,
/// VPN connections, what the person made with an app, such as saved games, databases, and the app's own backups, and
/// the sign-ins to services that tools save when the person logs in. A folder at or inside one, or the app's folder
/// that holds one, is shown and never selected for the person, who can still select it.
enum KeptOnlyHere {
    static let places: [(folder: String, inside: String?, reason: HoldBack)] = [
        // Airmail's help, "Backup and restore Airmail for macOS".
        ("Library/Group Containers/2E337YPCZY.airmail", nil, .holdsLocalMail),
        // Microsoft's "Uninstall Office for Mac": Outlook's data goes with these three folders.
        ("Library/Group Containers/UBF8T346G9.Office", nil, .holdsLocalMail),
        ("Library/Group Containers/UBF8T346G9.ms", nil, .holdsLocalMail),
        ("Library/Group Containers/UBF8T346G9.OfficeOsfWebHost", nil, .holdsLocalMail),
        // Canary's "How and where does Canary store encryption keys": Manual mode keys stay on the device.
        ("Library/Containers/io.canarymail.mac", nil, .holdsLocalMail),
        // Mozilla's "Profiles: where Thunderbird stores user data".
        ("Library/Thunderbird", "Profiles", .holdsLocalMail),
        // Signal Desktop's `user_config.main.ts` and `Server.node.ts`.
        ("Library/Application Support/Signal", nil, .holdsMessageHistory),
        // Element Desktop's `electron-main.ts`, which keeps using `Riot` where it is the only one.
        ("Library/Application Support/Element", nil, .holdsMessageHistory),
        ("Library/Application Support/Riot", nil, .holdsMessageHistory),
        // Threema 2.0's folder, from its cask; Threema's "Data security of Threema for desktop".
        ("Library/Application Support/ThreemaDesktop", nil, .holdsMessageHistory),
        // TelegramSwift's `ApiEnvironment.group`; Telegram's FAQ: secret chats are device-specific.
        ("Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram", nil, .holdsMessageHistory),
        // WhatsApp's "How to restore your chat history": chats on WhatsApp on Mac can't be backed up or restored
        // there, and aren't on its servers. The app's entitlements name this group, where it keeps them.
        ("Library/Group Containers/group.net.whatsapp.WhatsApp.shared", nil, .holdsMessageHistory),
        // 1Password's "Migrate your existing 1Password data from standalone vaults" and "1Password backups":
        // 1Password 7 and earlier kept standalone vaults and daily backups in this group, which 1Password 8 claims too.
        ("Library/Group Containers/2BUA8C4S2C.com.agilebits", nil, .holdsPasswordsOrCodes),
        // Strongbox's "Where are Strongbox local backups stored on my Mac".
        ("Library/Group Containers/group.strongbox.mac.mcguill", "backups", .holdsPasswordsOrCodes),
        // Ente's "Offline mode": the codes are stored only on that device.
        ("Library/Containers/io.ente.auth.mac", nil, .holdsPasswordsOrCodes),
        // Proton Authenticator's entitlements; Apple: the app's primary group container holds its store.
        ("Library/Group Containers/group.me.proton.authenticator", nil, .holdsPasswordsOrCodes),
        // Tunnelblick's "File Locations" and "Uninstalling Tunnelblick".
        ("Library/Application Support/Tunnelblick", "Configurations", .holdsVPNConnections),
        // SparkLabs' "Uninstalling Viscosity (Mac)": connection data.
        ("Library/Application Support/Viscosity", nil, .holdsVPNConnections),
        // Steam Support's "Steam Cloud": cloud files are kept here by default, and with Steam Cloud off a game's saves
        // are kept only here.
        ("Library/Application Support/Steam", "userdata", .holdsWorkMadeWithTheApp),
        // Postgres.app's "Installing Postgres.app": its default data directory is `Postgres/var-XX`, and deleting the
        // data directories is an optional step of uninstalling it.
        ("Library/Application Support/Postgres", nil, .holdsWorkMadeWithTheApp),
        // OBS Studio keeps its profiles and scene collections in `obs-studio/basic` in its configuration folder
        // (`frontend/OBSApp.cpp`), and nowhere else.
        ("Library/Application Support/obs-studio", "basic", .holdsWorkMadeWithTheApp),
        // iTerm2's "Dynamic Profiles" and "Running a Script": the profiles and the scripts the person wrote.
        ("Library/Application Support/iTerm2", "Scripts", .holdsWorkMadeWithTheApp),
        ("Library/Application Support/iTerm2", "DynamicProfiles", .holdsWorkMadeWithTheApp),
        // LibreOffice's and Apache OpenOffice's user profile (`UserInstallation`, `<name>/4` on a Mac). LibreOffice
        // Help's "Paths": the person's templates, AutoText, AutoCorrect texts, dictionaries, and documents' backups.
        ("Library/Application Support/LibreOffice", nil, .holdsWorkMadeWithTheApp),
        ("Library/Application Support/OpenOffice", nil, .holdsWorkMadeWithTheApp),
        // Torrent clients keep each torrent and its progress apart from the download, and forget every transfer without
        // them. Transmission's "Configuration Files": `torrents`, `resume`, and the Mac app's `Transfers.plist`.
        ("Library/Application Support/Transmission", nil, .holdsTorrents),
        // qBittorrent's `SessionImpl`: `BT_backup`, or `torrents.db`, in its data folder.
        ("Library/Application Support/qBittorrent", "BT_backup", .holdsTorrents),
        ("Library/Application Support/qBittorrent", "torrents.db", .holdsTorrents),
        // BiglyBT's `DownloadManagerStateImpl`: `active` in its user folder.
        ("Library/Application Support/BiglyBT", "active", .holdsTorrents),
        // Deluge's `TorrentManager`: `state` in its configuration folder, which is XDG's on a Mac.
        (".config/deluge", "state", .holdsTorrents),
        // Motrix's `getSessionPath`: aria2's session, read again at every start.
        ("Library/Application Support/Motrix", "download.session", .holdsTorrents),
        // WebTorrent's `TORRENT_PATH`.
        ("Library/Application Support/WebTorrent", "Torrents", .holdsTorrents),
        // Folx's own code: its list of downloads in `Folx3`, and before it `Folx` with `TorrentFiles`.
        ("Library/Application Support/Eltima Software/Folx3", nil, .holdsTorrents),
        ("Library/Application Support/Eltima Software/Folx", nil, .holdsTorrents),
        // Docker's `docker login`: with no credential store, the credentials go in `.docker/config.json`.
        (".docker", "config.json", .holdsSignIns),
        // Cargo's `cargo login`: the token is saved in `$CARGO_HOME/credentials.toml`, and `CARGO_HOME` is `.cargo`.
        (".cargo", "credentials.toml", .holdsSignIns),
        // The `.pypirc` specification (packaging.python.org): `$HOME/.pypirc`, with passwords and API tokens in it.
        (".pypirc", nil, .holdsSignIns),
        // RubyGems' `gem push`: the API key in `~/.gem/credentials` or `~/.local/share/gem/credentials`.
        (".gem", "credentials", .holdsSignIns),
        (".local/share/gem", "credentials", .holdsSignIns),
        // Composer's "Authentication for private packages": the global `auth.json` in `COMPOSER_HOME`, which its
        // command-line reference puts at `~/.composer` on macOS.
        (".composer", "auth.json", .holdsSignIns),
        // Google Cloud CLI's "Authorize the gcloud CLI": its credential files live in its configuration directory.
        (".config/gcloud", nil, .holdsSignIns),
        // Azure CLI's "MSAL-based Azure CLI": its token cache is kept as plain files on macOS, in `~/.azure`.
        (".azure", nil, .holdsSignIns),
        // Terraform's `terraform login`: the token goes in plain text to `~/.terraform.d/credentials.tfrc.json`.
        (".terraform.d", "credentials.tfrc.json", .holdsSignIns),
    ]

    /// The same, in the Library every account on the Mac shares.
    static let localPlaces: [(folder: String, inside: String?, reason: HoldBack)] = [
        // ZeroTier's "How to clear or reset your ZeroTier address": the node's identity is in this working folder,
        // and a new one has to be authorized again on every network.
        ("Library/Application Support/ZeroTier", "One", .holdsVPNConnections),
        // Tunnelblick's "File Locations": shared configurations, and the backups of the configurations deployed
        // inside the app.
        ("Library/Application Support/Tunnelblick", "Shared", .holdsVPNConnections),
        ("Library/Application Support/Tunnelblick", "Backup", .holdsVPNConnections),
    ]

    static func reason(for path: String, home: String, root: String) -> HoldBack? {
        let item = PathComponents.of(path.lowercased())
        for (base, list) in [(home, places), (root, localPlaces)] {
            let base = (base as NSString).standardizingPath
            for (folder, inside, reason) in list {
                let folder = PathComponents.of((base as NSString).appendingPathComponent(folder).lowercased())
                let place = folder + (inside.map { PathComponents.of($0.lowercased()) } ?? [])
                if item.starts(with: place) || item == folder { return reason }
            }
        }
        // What an app names as its backups is a copy the person may need, whichever app made it.
        return namesBackups(item.last ?? "") ? .holdsWorkMadeWithTheApp : nil
    }

    static func reason(seenIn contents: FolderContents) -> HoldBack? {
        contents.holdsBackups ? .holdsWorkMadeWithTheApp : nil
    }

    static func namesBackups(_ name: String) -> Bool {
        let words = name.lowercased().split { !$0.isLetter }
        return words.contains("backup") || words.contains("backups")
    }
}
