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
        // Mozilla's "Profiles - Where Firefox stores your bookmarks, passwords and other user data": each profile keeps
        // the saved passwords in `key4.db` and `logins.json`, and Firefox can be uninstalled without losing them.
        ("Library/Application Support/Firefox", "Profiles", .holdsPasswordsOrCodes),
        // Browsers built on Firefox keep the same profiles and save passwords as it does: Waterfox's
        // `moz.configure` and Zen's `moz-configure.patch` name the folder (`MOZ_APP_PROFILE`), Zen's "Managing
        // Firefox Profiles" says `logins.json` holds the saved passwords, and Floorp keeps them under its own name.
        ("Library/Application Support/Waterfox", "Profiles", .holdsPasswordsOrCodes),
        ("Library/Application Support/zen", "Profiles", .holdsPasswordsOrCodes),
        ("Library/Application Support/Floorp", "Profiles", .holdsPasswordsOrCodes),
        // LibreWolf, Mullvad Browser and Tor Browser save no passwords unless the person turns it on, but keep the
        // bookmarks, and Tor Browser the keys added for onion services, which nothing syncs: LibreWolf's FAQ, Mullvad's
        // "Install Mullvad Browser" and Tor Browser's manual, "Uninstalling", name the folders.
        ("Library/Application Support/librewolf", "Profiles", .holdsWorkMadeWithTheApp),
        ("Library/Application Support/MullvadBrowser", "Profiles", .holdsWorkMadeWithTheApp),
        ("Library/Application Support/TorBrowser-Data", nil, .holdsWorkMadeWithTheApp),
        // Chromium's `docs/user_data_dir.md` and `password_manager_constants.cc`: each browser's folder holds its
        // profiles, most often `Default`, and a profile keeps the saved passwords in `Login Data`. Brave's folders are
        // named by its `build/config.gni` and `BRANDING`. Opera's desktop blog names its folder, which before Opera 102
        // was the profile itself.
        ("Library/Application Support/Google/Chrome", "Default", .holdsPasswordsOrCodes),
        ("Library/Application Support/Google/Chrome Beta", "Default", .holdsPasswordsOrCodes),
        ("Library/Application Support/Google/Chrome Dev", "Default", .holdsPasswordsOrCodes),
        ("Library/Application Support/Google/Chrome Canary", "Default", .holdsPasswordsOrCodes),
        ("Library/Application Support/Chromium", "Default", .holdsPasswordsOrCodes),
        ("Library/Application Support/BraveSoftware/Brave-Browser", "Default", .holdsPasswordsOrCodes),
        ("Library/Application Support/BraveSoftware/Brave-Browser-Beta", "Default", .holdsPasswordsOrCodes),
        ("Library/Application Support/BraveSoftware/Brave-Browser-Dev", "Default", .holdsPasswordsOrCodes),
        ("Library/Application Support/BraveSoftware/Brave-Browser-Nightly", "Default", .holdsPasswordsOrCodes),
        ("Library/Application Support/BraveSoftware/Brave-Origin", "Default", .holdsPasswordsOrCodes),
        ("Library/Application Support/BraveSoftware/Brave-Origin-Beta", "Default", .holdsPasswordsOrCodes),
        ("Library/Application Support/BraveSoftware/Brave-Origin-Nightly", "Default", .holdsPasswordsOrCodes),
        ("Library/Application Support/com.operasoftware.Opera", nil, .holdsPasswordsOrCodes),
        // Microsoft's "Native messaging" names Edge's folder for each channel and Vivaldi's team names Vivaldi's;
        // Thorium's, Comet's, Arc's and Dia's come from their casks. Yandex Browser's help, "Profile for settings and
        // data storing", keeps the profiles and their site logins in `YandexBrowser`.
        ("Library/Application Support/Microsoft Edge", "Default", .holdsPasswordsOrCodes),
        ("Library/Application Support/Microsoft Edge Beta", "Default", .holdsPasswordsOrCodes),
        ("Library/Application Support/Microsoft Edge Dev", "Default", .holdsPasswordsOrCodes),
        ("Library/Application Support/Microsoft Edge Canary", "Default", .holdsPasswordsOrCodes),
        ("Library/Application Support/Vivaldi", "Default", .holdsPasswordsOrCodes),
        ("Library/Application Support/Thorium", "Default", .holdsPasswordsOrCodes),
        ("Library/Application Support/Comet", "Default", .holdsPasswordsOrCodes),
        ("Library/Application Support/Yandex", "YandexBrowser", .holdsPasswordsOrCodes),
        ("Library/Application Support/Arc", nil, .holdsPasswordsOrCodes),
        ("Library/Application Support/Dia", nil, .holdsPasswordsOrCodes),
        // Helium's macOS patch `change-product-dir-name.patch` names its folder.
        ("Library/Application Support/net.imput.helium", "Default", .holdsPasswordsOrCodes),
        // Kagi's "Technical Information" for Orion: its profiles and bookmarks are in its folder.
        ("Library/Application Support/Orion", nil, .holdsWorkMadeWithTheApp),
        // Tunnelblick's "File Locations" and "Uninstalling Tunnelblick".
        ("Library/Application Support/Tunnelblick", "Configurations", .holdsVPNConnections),
        // SparkLabs' "Uninstalling Viscosity (Mac)": connection data.
        ("Library/Application Support/Viscosity", nil, .holdsVPNConnections),
        // CrashPlan's "Uninstall the CrashPlan app", for a copy installed for one account: backups another computer
        // sent here.
        ("Library/Application Support/CrashPlan", "backupArchives", .holdsWorkMadeWithTheApp),
        // Steam Support's "Steam Cloud": cloud files are kept here by default, and with Steam Cloud off a game's saves
        // are kept only here.
        ("Library/Application Support/Steam", "userdata", .holdsWorkMadeWithTheApp),
        // OpenEmu's "User Guide: Transfer Save Files": each core's in-game saves are in its folder.
        ("Library/Application Support/OpenEmu", nil, .holdsWorkMadeWithTheApp),
        // Dolphin's `Source/Core/Common/CommonPaths.h`: memory cards in `GC`, the Wii's storage in `Wii`, and the save
        // states.
        ("Library/Application Support/Dolphin", "GC", .holdsWorkMadeWithTheApp),
        ("Library/Application Support/Dolphin", "Wii", .holdsWorkMadeWithTheApp),
        ("Library/Application Support/Dolphin", "StateSaves", .holdsWorkMadeWithTheApp),
        // Mojang's "Manually Uninstall Minecraft: Java Edition": the saved worlds and screenshots are in this folder,
        // and Minecraft support can't recover deleted files.
        ("Library/Application Support/minecraft", "saves", .holdsWorkMadeWithTheApp),
        ("Library/Application Support/minecraft", "screenshots", .holdsWorkMadeWithTheApp),
        // Prism Launcher's "Data Locations" and `MinecraftInstance.cpp`: each instance keeps its worlds in `saves`.
        ("Library/Application Support/PrismLauncher", "instances", .holdsWorkMadeWithTheApp),
        // Chatbox's "Data Storage": the conversations stay on this device, and its team can't recover them.
        ("Library/Application Support/chatbox", nil, .holdsWorkMadeWithTheApp),
        // Google's "Fix problems in Drive for desktop": a file it couldn't upload is copied to `lost_and_found`.
        ("Library/Application Support/Google/DriveFS", "lost_and_found", .holdsWorkMadeWithTheApp),
        // Postgres.app's "Installing Postgres.app": its default data directory is `Postgres/var-XX`, and deleting the
        // data directories is an optional step of uninstalling it.
        ("Library/Application Support/Postgres", nil, .holdsWorkMadeWithTheApp),
        // Laravel Herd's "Uninstalling Herd": the Herd Pro services' databases are in `config/services`, to back up
        // before the folder goes.
        ("Library/Application Support/Herd", "config/services", .holdsWorkMadeWithTheApp),
        // Plex's "Where is the Plex Media Server data directory located?" and "Backing up Plex Media Server data": what
        // was watched, the metadata, and the settings in its preferences file.
        ("Library/Application Support/Plex Media Server", nil, .holdsWorkMadeWithTheApp),
        ("Library/Preferences/com.plexapp.plexmediaserver.plist", nil, .holdsWorkMadeWithTheApp),
        // Neo4j Desktop's "Re-installation of Desktop" for 1.x and "Installation" for 2.x: each version keeps its
        // databases in `Application`, to back up before removing it.
        ("Library/Application Support/Neo4j Desktop", "Application", .holdsWorkMadeWithTheApp),
        ("Library/Application Support/neo4j-desktop", "Application", .holdsWorkMadeWithTheApp),
        // UniFi's "How to Uninstall the Self-Hosted UniFi Network Server": a backup first, then this folder.
        ("Library/Application Support/UniFi", nil, .holdsWorkMadeWithTheApp),
        // Jan's "Data Folder": threads, assistants, memories, skills and subagents live there permanently.
        ("Library/Application Support/Jan", "data/threads", .holdsWorkMadeWithTheApp),
        ("Library/Application Support/Jan", "data/assistants", .holdsWorkMadeWithTheApp),
        ("Library/Application Support/Jan", "data/agent-workspace/memory", .holdsWorkMadeWithTheApp),
        ("Library/Application Support/Jan", "data/agent-workspace/skills", .holdsWorkMadeWithTheApp),
        ("Library/Application Support/Jan", "data/agent-workspace/subagents", .holdsWorkMadeWithTheApp),
        // Open WebUI's desktop app runs Open WebUI with its data, the chats among them, in `data`
        // (`src/main/utils/index.ts`).
        ("Library/Application Support/open-webui", "data", .holdsWorkMadeWithTheApp),
        // Objective Development's "How can I uninstall Little Snitch 4?": the person's rules and settings are here and
        // in `Objective Development/Little Snitch` in the Library every account shares.
        ("Library/Application Support/Little Snitch", nil, .holdsWorkMadeWithTheApp),
        // GPT4All's "Settings" names its folder, and its 2.4.1 release notes keep saved chats beside the models there.
        ("Library/Application Support/nomic.ai/GPT4All", nil, .holdsWorkMadeWithTheApp),
        // Topaz Photo's "Presets": the presets the person made, which can be shared.
        ("Library/Application Support/Topaz Labs LLC/Topaz Photo", "Presets", .holdsWorkMadeWithTheApp),
        // Copies of other apps an updater keeps: MacUpdater's FAQ, Version Tracker's "Uninstalling Version Tracker",
        // and AutoBrew's README, "Creating an App Snapshot".
        ("Library/Application Support/MacUpdater", nil, .holdsWorkMadeWithTheApp),
        ("Library/Application Support/Version Tracker", nil, .holdsWorkMadeWithTheApp),
        ("Library/Application Support/AutoBrew", "Snapshots", .holdsWorkMadeWithTheApp),
        // Typeface's site: the tags that organize the person's fonts can be lost, unless exported. Its group from its
        // cask.
        ("Library/Group Containers/group.com.criminalbird.typeface", nil, .holdsWorkMadeWithTheApp),
        // Syncthing's "Syncthing Configuration": the folders it shares and the device's private key, the basis of its
        // device ID.
        ("Library/Application Support/Syncthing", nil, .holdsWorkMadeWithTheApp),
        // Microsoft's "Recover files in Office for Mac": the work AutoRecover kept and was never saved.
        ("Library/Containers/com.Microsoft.Word", "Data/Library/Preferences/AutoRecovery", .holdsWorkMadeWithTheApp),
        ("Library/Containers/com.Microsoft.Powerpoint", "Data/Library/Preferences/AutoRecovery", .holdsWorkMadeWithTheApp),
        ("Library/Containers/com.microsoft.Excel", "Data/Library/Application Support/Microsoft", .holdsWorkMadeWithTheApp),
        // Cultured Code's "Completely Uninstalling Things": deleting this group container deletes the to-dos.
        ("Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac", nil, .holdsWorkMadeWithTheApp),
        // OBS Studio keeps its profiles and scene collections in `obs-studio/basic` in its configuration folder
        // (`frontend/OBSApp.cpp`), and nowhere else.
        ("Library/Application Support/obs-studio", "basic", .holdsWorkMadeWithTheApp),
        // iTerm2's "Dynamic Profiles" and "Running a Script": the profiles and the scripts the person wrote.
        ("Library/Application Support/iTerm2", "Scripts", .holdsWorkMadeWithTheApp),
        ("Library/Application Support/iTerm2", "DynamicProfiles", .holdsWorkMadeWithTheApp),
        // Sublime Text's "Reverting to a Freshly Installed State" and "Packages": its data folder keeps the person's
        // settings and the packages they made in `Packages`, which can't be installed again.
        ("Library/Application Support/Sublime Text", "Packages", .holdsWorkMadeWithTheApp),
        ("Library/Application Support/Sublime Text 3", "Packages", .holdsWorkMadeWithTheApp),
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
        // PostgreSQL's "The Password File": passwords for its connections.
        (".pgpass", nil, .holdsPasswordsOrCodes),
        // Vault's token helpers: the default one keeps the token in `~/.vault-token`.
        (".vault-token", nil, .holdsSignIns),
        // MinIO Client's configuration file, with each alias's access and secret keys.
        (".mc", "config.json", .holdsSignIns),
        // Cloudflare's "Useful terms": the tunnels' credentials files and the `cert.pem` of `cloudflared login`.
        (".cloudflared", nil, .holdsSignIns),
        // GitLab Runner's "Commands": its configuration file when it runs as a person.
        (".gitlab-runner", "config.toml", .holdsSignIns),
        // Jenkins' home is `~/.jenkins` unless one is named (`WebAppMain`), and "Backing up" keeps the credentials in
        // `secrets`.
        (".jenkins", "secrets", .holdsPasswordsOrCodes),
        // n8n's "Set a custom encryption key": the key its saved credentials are encrypted with.
        (".n8n", nil, .holdsPasswordsOrCodes),
        // DuckDB's "Secrets Manager": its persistent secrets.
        (".duckdb", "stored_secrets", .holdsSignIns),
        // mcp-remote's README: all its credential information.
        (".mcp-auth", nil, .holdsSignIns),
        // gsutil's boto configuration file and its `[Credentials]`.
        (".boto", nil, .holdsSignIns),
        // Gemini CLI's `storage.ts`: its sign-in.
        (".gemini", "oauth_creds.json", .holdsSignIns),
        // Firebase CLI's `auth.ts` keeps its tokens in its Configstore, named after the package.
        (".config/configstore", "firebase-tools.json", .holdsSignIns),
        // ngrok's "Agent Configuration File": its `authtoken` is a setting there.
        ("Library/Application Support/ngrok", "ngrok.yml", .holdsSignIns),
        // NoMachine's "How to move client connection files from one computer to another one": by default, the
        // connections and recordings go in Documents/NoMachine, and the favorites in .nx/config/player.cfg.
        (".nx", "config/player.cfg", .holdsWorkMadeWithTheApp),
        ("Documents/NoMachine", nil, .holdsWorkMadeWithTheApp),
        // RustDesk's `config.rs`: this Mac's permanent password and keys, and the passwords saved for other computers.
        ("Library/Preferences/com.carriez.RustDesk", nil, .holdsPasswordsOrCodes),
        // TablePlus' "Connections" page: saved connections stay on this Mac unless a synced folder is chosen. Its
        // folder from its cask.
        ("Library/Application Support/com.tinyapp.TablePlus", nil, .holdsWorkMadeWithTheApp),
        // Sequel Ace's "Migrating from Sequel Pro": its favorites, the saved connections.
        (
            "Library/Containers/com.sequel-ace.sequel-ace",
            "Data/Library/Application Support/Sequel Ace/Data/Favorites.plist",
            .holdsWorkMadeWithTheApp
        ),
        // MongoDB Compass' `connection-storage` and `compass-data-modeling`: saved connections and data models.
        ("Library/Application Support/MongoDB Compass", "Connections", .holdsWorkMadeWithTheApp),
        ("Library/Application Support/MongoDB Compass", "DataModelDescriptions", .holdsWorkMadeWithTheApp),
        // Proxyman's "Lost data after updating Proxyman app?": its debugging rules, settings, and their backups.
        ("Library/Application Support/com.proxyman.NSProxy", nil, .holdsWorkMadeWithTheApp),
        // BBEdit's User Manual: its notes, Scratchpad, and worksheet in its application support folder, and the
        // unsaved documents in `Auto-Save Recovery` in its settings folder, in its container or in `~/Library/BBEdit`.
        ("Library/Application Support/BBEdit", nil, .holdsWorkMadeWithTheApp),
        ("Library/BBEdit", "Auto-Save Recovery", .holdsWorkMadeWithTheApp),
        ("Library/Containers/com.barebones.bbedit", nil, .holdsWorkMadeWithTheApp),
        // OrbStack's FAQ: the data of its containers, images, volumes, and machines.
        ("Library/Group Containers/HUAQ24HBR6.dev.orbstack", "data", .holdsVirtualMachines),
        // Docker's FAQ for Mac: its containers and images in one disk image, `Data/vms/0/data/Docker.raw`.
        ("Library/Containers/com.docker.docker", "Data/vms", .holdsVirtualMachines),
        // Rancher Desktop's `paths_darwin.go`: its virtual machine in `lima`, and its snapshots.
        ("Library/Application Support/rancher-desktop", "lima", .holdsVirtualMachines),
        ("Library/Application Support/rancher-desktop", "snapshots", .holdsVirtualMachines),
        // Parallels' KB 117333: where the App Store edition keeps its virtual machines.
        (
            "Library/Group Containers/4C6364ACXT.com.parallels.desktop.appstore",
            "Shared/Parallels",
            .holdsVirtualMachines
        ),
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
        // Little Snitch's rules and settings, from the same page as its folder in the home.
        ("Library/Application Support/Objective Development/Little Snitch", nil, .holdsWorkMadeWithTheApp),
        // MAMP PRO's "Uninstall MAMP PRO": uninstalling it removes the databases kept here.
        ("Library/Application Support/appsolute/MAMP PRO", "db", .holdsWorkMadeWithTheApp),
        // CrashPlan's "Uninstall the CrashPlan app": this folder may hold backups another computer sent here.
        ("Library/Application Support/CrashPlan", "backupArchives", .holdsWorkMadeWithTheApp),
    ]

    static func reason(for path: String, home: String, root: String) -> HoldBack? {
        let item = PathComponents.of((path as NSString).standardizingPath.lowercased())
        for (base, places) in [(home, placesByFolder), (root, localPlacesByFolder)] {
            let base = PathComponents.of((base as NSString).standardizingPath.lowercased())
            guard item.starts(with: base), item.count > base.count else { continue }
            let rest = item.dropFirst(base.count)
            // An item at or inside several places takes the one listed first.
            let held = (1...rest.count).flatMap { depth in
                (places[Array(rest.prefix(depth))] ?? []).filter {
                    depth == rest.count || rest.dropFirst(depth).starts(with: $0.inside)
                }
            }
            if let first = held.min(by: { $0.order < $1.order }) { return first.reason }
        }
        if namesAVirtualMachine(item.last ?? "") { return .holdsVirtualMachines }
        return namesWorkMadeWithAnApp(item.last ?? "") ? .holdsWorkMadeWithTheApp : nil
    }

    private struct Place {
        let inside: [String]
        let reason: HoldBack
        let order: Int
    }

    private static let placesByFolder = byFolder(places)
    private static let localPlacesByFolder = byFolder(localPlaces)

    private static func byFolder(_ list: [(folder: String, inside: String?, reason: HoldBack)]) -> [[String]: [Place]] {
        var index: [[String]: [Place]] = [:]
        for (order, (folder, inside, reason)) in list.enumerated() {
            let place = Place(inside: PathComponents.of((inside ?? "").lowercased()), reason: reason, order: order)
            index[PathComponents.of(folder.lowercased()), default: []].append(place)
        }
        return index
    }

    static func reason(seenIn contents: FolderContents) -> HoldBack? {
        if contents.holdsVirtualMachines { return .holdsVirtualMachines }
        return contents.holdsWorkMadeWithAnApp ? .holdsWorkMadeWithTheApp : nil
    }

    /// Whether a name is a virtual machine's or a Windows bottle's, as each maker gives it: VirtualBuddy's,
    /// Parallels', VMware Fusion's, UTM's, and Viable's packages, the `drive_c` Wine makes in every prefix, which
    /// CrossOver and Whisky call bottles, and the `86box.cfg` of an 86Box machine.
    static func namesAVirtualMachine(_ name: String) -> Bool {
        // A walk asks this of every name, so a name that can't end like one is passed over before it is copied.
        guard let last = name.utf8.last, lastLetters.contains(last | 0x20) else { return false }
        let name = name.lowercased()
        return name == "drive_c" || name == "86box.cfg"
            || virtualMachinePackages.contains { name.hasSuffix($0) && name.count > $0.count }
    }

    private static let virtualMachinePackages = [".vbvm", ".pvm", ".vmwarevm", ".utm", ".vimi"]
    private static let lastLetters: Set<UInt8> = [
        UInt8(ascii: "m"), UInt8(ascii: "i"), UInt8(ascii: "c"), UInt8(ascii: "g"),
    ]

    /// Whether an app gives this name to the person's work or its copies, whichever app it is: backups, and
    /// `Resolve Disk Database`, where DaVinci Resolve's Reference Manual keeps local project libraries by default.
    static func namesWorkMadeWithAnApp(_ name: String) -> Bool {
        let words = name.lowercased().split { !$0.isLetter }
        return words.contains("backup") || words.contains("backups") || words == ["resolve", "disk", "database"]
    }
}
