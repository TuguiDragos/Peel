import Foundation
@testable import PeelCore
import PeelPrivileged
import Testing

struct KeptOnlyHereTests {
    private let home = "/Users/me"

    /// Timed beside a reading of the same paths on the same thread, so a Mac busy with other work slows both alike.
    @Test func aQuestionCostsAFewReadingsOfItsPathHoweverManyPlacesThereAre() {
        let paths = (0..<5000).map { "\(home)/Library/Application Support/org.example.app\($0)/data" }
        let ratios = (0..<3).map { _ in
            let reading = processorTime {
                for path in paths { _ = PathComponents.of((path as NSString).standardizingPath.lowercased()) }
            }
            let asking = processorTime {
                for path in paths { _ = KeptOnlyHere.reason(for: path, home: home, root: "/") }
            }
            return asking / reading
        }
        #expect(ratios.contains { $0 < 15 }, "\(ratios)")
    }

    @Test func knowsEachPlaceWhatIsInsideAndTheAppsFolderAroundIt() {
        let held: [(String, HoldBack)] = [
            ("Library/Group Containers/2E337YPCZY.airmail", .holdsLocalMail),
            ("Library/Group Containers/UBF8T346G9.Office/Outlook", .holdsLocalMail),
            ("Library/Thunderbird", .holdsLocalMail),
            ("Library/Thunderbird/Profiles/abcd1234.default/Mail/Local Folders/Inbox", .holdsLocalMail),
            ("Library/Application Support/Signal/sql/db.sqlite", .holdsMessageHistory),
            ("Library/Application Support/riot", .holdsMessageHistory),
            ("Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram", .holdsMessageHistory),
            ("Library/Group Containers/group.net.whatsapp.WhatsApp.shared", .holdsMessageHistory),
            ("Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite", .holdsMessageHistory),
            ("Library/Group Containers/2BUA8C4S2C.com.agilebits", .holdsPasswordsOrCodes),
            ("Library/Group Containers/2BUA8C4S2C.com.agilebits/Library/Application Support/1Password/Backups",
             .holdsPasswordsOrCodes),
            ("Library/Group Containers/group.strongbox.mac.mcguill", .holdsPasswordsOrCodes),
            ("Library/Containers/io.ente.auth.mac", .holdsPasswordsOrCodes),
            ("Library/Application Support/Firefox", .holdsPasswordsOrCodes),
            ("Library/Application Support/Firefox/Profiles/abcd1234.default-release/logins.json", .holdsPasswordsOrCodes),
            ("Library/Application Support/Waterfox", .holdsPasswordsOrCodes),
            ("Library/Application Support/zen/Profiles/pzrcsk7e.Default (release)/logins.json", .holdsPasswordsOrCodes),
            ("Library/Application Support/Floorp/Profiles/y5yiweov.default-default/key4.db", .holdsPasswordsOrCodes),
            ("Library/Application Support/librewolf", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/LibreWolf/Profiles/7pwj3wse.default-default/places.sqlite", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/MullvadBrowser", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/TorBrowser-Data", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/TorBrowser-Data/Tor/onion-auth", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Google/Chrome", .holdsPasswordsOrCodes),
            ("Library/Application Support/Google/Chrome/Default/Login Data", .holdsPasswordsOrCodes),
            ("Library/Application Support/Google/Chrome Canary", .holdsPasswordsOrCodes),
            ("Library/Application Support/Chromium/Default", .holdsPasswordsOrCodes),
            ("Library/Application Support/BraveSoftware/Brave-Browser/Default/Login Data", .holdsPasswordsOrCodes),
            ("Library/Application Support/BraveSoftware/Brave-Origin-Nightly", .holdsPasswordsOrCodes),
            ("Library/Application Support/com.operasoftware.Opera/Login Data", .holdsPasswordsOrCodes),
            ("Library/Application Support/Microsoft Edge", .holdsPasswordsOrCodes),
            ("Library/Application Support/Microsoft Edge/Default/Login Data", .holdsPasswordsOrCodes),
            ("Library/Application Support/Microsoft Edge Canary/Default", .holdsPasswordsOrCodes),
            ("Library/Application Support/Vivaldi/Default/Login Data", .holdsPasswordsOrCodes),
            ("Library/Application Support/Thorium", .holdsPasswordsOrCodes),
            ("Library/Application Support/Comet/Default/Login Data", .holdsPasswordsOrCodes),
            ("Library/Application Support/Yandex", .holdsPasswordsOrCodes),
            ("Library/Application Support/Yandex/YandexBrowser/Default/Ya Passman Data", .holdsPasswordsOrCodes),
            ("Library/Application Support/Arc/User Data/Default/Login Data", .holdsPasswordsOrCodes),
            ("Library/Application Support/Arc/StorableSidebar.json", .holdsPasswordsOrCodes),
            ("Library/Application Support/Dia", .holdsPasswordsOrCodes),
            ("Library/Application Support/Orion/Defaults/favourites.plist", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Orion/profiles", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Herd", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Herd/config/services/mysql/data", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Plex Media Server/Plug-in Support/Databases", .holdsWorkMadeWithTheApp),
            ("Library/Preferences/com.plexapp.plexmediaserver.plist", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Neo4j Desktop/Application/relate-data/dbmss", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/neo4j-desktop/Application/data", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/UniFi/data/db", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Jan", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Jan/data/threads/01J0", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Jan/data/assistants/jan", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Jan/data/agent-workspace/memory", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Jan/data/agent-workspace/skills", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Jan/data/agent-workspace/subagents", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/open-webui/data/webui.db", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Little Snitch", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/nomic.ai/GPT4All", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/nomic.ai/GPT4All/gpt4all-1234.chat", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Topaz Labs LLC/Topaz Photo", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Topaz Labs LLC/Topaz Photo/Presets/Portrait.tpp", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/MacUpdater/Firefox 140.0.app", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Version Tracker", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/AutoBrew", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/AutoBrew/Snapshots/org.example.notes", .holdsWorkMadeWithTheApp),
            ("Library/Group Containers/group.com.criminalbird.typeface", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Syncthing", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Syncthing/key.pem", .holdsWorkMadeWithTheApp),
            ("Library/Containers/com.Microsoft.Word", .holdsWorkMadeWithTheApp),
            ("Library/Containers/com.microsoft.Word/Data/Library/Preferences/AutoRecovery/Report.docx",
             .holdsWorkMadeWithTheApp),
            ("Library/Containers/com.Microsoft.Powerpoint/Data/Library/Preferences/AutoRecovery", .holdsWorkMadeWithTheApp),
            ("Library/Containers/com.microsoft.Excel/Data/Library/Application Support/Microsoft", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/OpenEmu/BSNES/Battery Saves/Game.srm", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Dolphin", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Dolphin/GC/USA/Card A", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Dolphin/Wii/title", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Dolphin/StateSaves/GALE01.s01", .holdsWorkMadeWithTheApp),
            (".pgpass", .holdsPasswordsOrCodes),
            (".vault-token", .holdsSignIns),
            (".mc/config.json", .holdsSignIns),
            (".cloudflared/cert.pem", .holdsSignIns),
            (".gitlab-runner/config.toml", .holdsSignIns),
            (".jenkins", .holdsPasswordsOrCodes),
            (".jenkins/secrets/master.key", .holdsPasswordsOrCodes),
            (".n8n/config", .holdsPasswordsOrCodes),
            (".duckdb/stored_secrets/s3.duckdb_secret", .holdsSignIns),
            (".mcp-auth/mcp-remote-0.1.37/1234_tokens.json", .holdsSignIns),
            (".boto", .holdsSignIns),
            (".gemini/oauth_creds.json", .holdsSignIns),
            (".config/configstore/firebase-tools.json", .holdsSignIns),
            ("Library/Application Support/ngrok/ngrok.yml", .holdsSignIns),
            ("Library/Preferences/com.carriez.RustDesk", .holdsPasswordsOrCodes),
            ("Library/Preferences/com.carriez.RustDesk/peers/123456789.toml", .holdsPasswordsOrCodes),
            ("Library/Application Support/com.tinyapp.TablePlus", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/com.tinyapp.TablePlus/Data/Connections.plist", .holdsWorkMadeWithTheApp),
            ("Library/Containers/com.sequel-ace.sequel-ace", .holdsWorkMadeWithTheApp),
            (
                "Library/Containers/com.sequel-ace.sequel-ace/Data/Library/Application Support/Sequel Ace/Data/Favorites.plist",
                .holdsWorkMadeWithTheApp
            ),
            ("Library/Application Support/MongoDB Compass", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/MongoDB Compass/Connections/0f6c.json", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/MongoDB Compass/DataModelDescriptions/1a2b.json", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/com.proxyman.NSProxy", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/com.proxyman.NSProxy/user-data-backups/a.zip", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/BBEdit", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/BBEdit/Notes.bbnotebookd", .holdsWorkMadeWithTheApp),
            ("Library/BBEdit", .holdsWorkMadeWithTheApp),
            ("Library/BBEdit/Auto-Save Recovery/a.bbautosave", .holdsWorkMadeWithTheApp),
            ("Library/Containers/com.barebones.bbedit", .holdsWorkMadeWithTheApp),
            (
                "Library/Application Support/Blackmagic Design/DaVinci Resolve/Resolve Disk Database",
                .holdsWorkMadeWithTheApp
            ),
            ("Projects/Resolve Disk Database", .holdsWorkMadeWithTheApp),
            ("Library/Group Containers/HUAQ24HBR6.dev.orbstack", .holdsVirtualMachines),
            ("Library/Group Containers/HUAQ24HBR6.dev.orbstack/data/data.img", .holdsVirtualMachines),
            ("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", .holdsVirtualMachines),
            ("Library/Application Support/rancher-desktop/lima/0/diffdisk", .holdsVirtualMachines),
            ("Library/Application Support/rancher-desktop/snapshots/a1b2", .holdsVirtualMachines),
            (
                "Library/Group Containers/4C6364ACXT.com.parallels.desktop.appstore/Shared/Parallels/Windows 11.pvm",
                .holdsVirtualMachines
            ),
            ("Parallels/Windows 11.pvm", .holdsVirtualMachines),
            ("Library/Application Support/CrossOver/Bottles/Steam/drive_c", .holdsVirtualMachines),
            ("Library/Application Support/Tunnelblick/Configurations/work.tblk", .holdsVPNConnections),
            ("Library/Application Support/Viscosity", .holdsVPNConnections),
            ("Library/Application Support/Steam", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Steam/userdata/123/570/remote", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/minecraft", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/minecraft/saves/New World/level.dat", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/minecraft/screenshots/2026-10-25_21.04.12.png", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/PrismLauncher", .holdsWorkMadeWithTheApp),
            (
                "Library/Application Support/PrismLauncher/instances/1.21.4/minecraft/saves/New World/level.dat",
                .holdsWorkMadeWithTheApp
            ),
            ("Library/Application Support/chatbox", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/chatbox/chatbox-data.json", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Google/DriveFS", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Google/DriveFS/lost_and_found/1a2b/report.pdf", .holdsWorkMadeWithTheApp),
            (".nx", .holdsWorkMadeWithTheApp),
            (".nx/config/player.cfg", .holdsWorkMadeWithTheApp),
            ("Documents/NoMachine", .holdsWorkMadeWithTheApp),
            ("Documents/NoMachine/Office.nxs", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/net.imput.helium", .holdsPasswordsOrCodes),
            ("Library/Application Support/net.imput.helium/Default/Login Data", .holdsPasswordsOrCodes),
            ("Library/Application Support/Postgres/var-17", .holdsWorkMadeWithTheApp),
            ("Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac", .holdsWorkMadeWithTheApp),
            ("Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac/ThingsData-1A2B3/Things Database.thingsdatabase",
             .holdsWorkMadeWithTheApp),
            ("Library/Application Support/.com.example.notes.backups", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Example/Backups", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/obs-studio", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/obs-studio/basic/scenes/Untitled.json", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/LibreOffice", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/LibreOffice/4/user/basic/Standard/Module1.xba", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/OpenOffice/4/user/template/Letter.ott", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/iTerm2", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/iTerm2/Scripts/AutoLaunch/hello.py", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/iTerm2/DynamicProfiles/Work.json", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Sublime Text", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Sublime Text/Packages/User/Notes.sublime-snippet", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Sublime Text 3/Packages/User/plugin.py", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Transmission", .holdsTorrents),
            ("Library/Application Support/Transmission/Transfers.plist", .holdsTorrents),
            ("Library/Application Support/qBittorrent", .holdsTorrents),
            ("Library/Application Support/qBittorrent/BT_backup/1a2b.fastresume", .holdsTorrents),
            ("Library/Application Support/qBittorrent/torrents.db", .holdsTorrents),
            ("Library/Application Support/BiglyBT/active/1a2b.dat", .holdsTorrents),
            (".config/deluge", .holdsTorrents), (".config/deluge/state/torrents.fastresume", .holdsTorrents),
            ("Library/Application Support/Motrix/download.session", .holdsTorrents),
            ("Library/Application Support/WebTorrent/Torrents/1a2b.torrent", .holdsTorrents),
            ("Library/Application Support/Eltima Software/Folx3/Folx3Data.storedata", .holdsTorrents),
            ("Library/Application Support/Eltima Software/Folx/TorrentFiles/1a2b.torrent", .holdsTorrents),
            (".docker", .holdsSignIns), (".docker/config.json", .holdsSignIns),
            (".cargo/credentials.toml", .holdsSignIns), (".pypirc", .holdsSignIns),
            (".gem/credentials", .holdsSignIns), (".local/share/gem/credentials", .holdsSignIns),
            (".composer/auth.json", .holdsSignIns), (".config/gcloud/credentials.db", .holdsSignIns),
            (".azure/msal_token_cache.json", .holdsSignIns), (".terraform.d/credentials.tfrc.json", .holdsSignIns),
            ("Library/Application Support/CrashPlan/backupArchives", .holdsWorkMadeWithTheApp),
        ]
        for (path, reason) in held {
            #expect(KeptOnlyHere.reason(for: "\(home)/\(path)", home: home, root: "/") == reason, "\(path)")
        }
        let heldOnTheMac: [(String, HoldBack)] = [
            ("Library/Application Support/ZeroTier", .holdsVPNConnections),
            ("Library/Application Support/ZeroTier/One/identity.secret", .holdsVPNConnections),
            ("Library/Application Support/Tunnelblick", .holdsVPNConnections),
            ("Library/Application Support/Tunnelblick/Shared/Office.tblk", .holdsVPNConnections),
            ("Library/Application Support/Tunnelblick/Backup/Deployed/Office.tblk", .holdsVPNConnections),
            ("Library/Application Support/appsolute/MAMP PRO", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Objective Development/Little Snitch", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Objective Development/Little Snitch/rules.xpl", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/appsolute/MAMP PRO/db/mysql80/shop", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/CrashPlan", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/CrashPlan/backupArchives/671234567890", .holdsWorkMadeWithTheApp),
        ]
        for (path, reason) in heldOnTheMac {
            #expect(KeptOnlyHere.reason(for: "/\(path)", home: home, root: "/") == reason, "\(path)")
        }
    }

    @Test func leavesWhatSitsBesideOrAroundThem() {
        let free = [
            "Library/Application Support", "Library/Group Containers", "Library", "Library/Caches/Signal",
            ".duckdb/extensions", ".gitlab-runner/builds", ".mc/certs", ".gemini/tmp",
            ".config/configstore/update-notifier-npm.json", "Library/Application Support/ngrok/logs",
            "Library/Preferences/com.carriez.RustDesk.plist", "Library/Application Support/MongoDB Compass/Cache",
            "Library/Containers/com.sequel-ace.sequel-ace/Data/Library/Caches",
            "Library/BBEdit/Document State.plist",
            "Library/Containers/com.docker.docker/Data/log", "Library/Application Support/rancher-desktop/rd-engine",
            "Library/Application Support/Dolphin/Cache", "Library/Application Support/Dolphin/Logs",
            "Library/Containers/com.microsoft.Word/Data/Library/Caches",
            "Library/Containers/com.microsoft.Excel/Data/Library/Preferences",
            "Library/Application Support/AutoBrew/Logs",
            "Library/Application Support/nomic.ai", "Library/Application Support/Topaz Labs LLC",
            "Library/Application Support/Topaz Labs LLC/Topaz Photo/models",
            "Library/Application Support/Herd/Log/mail", "Library/Application Support/Herd/bin",
            "Library/Application Support/Jan/data/llamacpp/models", "Library/Application Support/Jan/data/logs",
            "Library/Application Support/Jan/data/agent-workspace/sessions", "Library/Application Support/open-webui/logs",
            "Library/Application Support/Neo4j Desktop/Cache", "Library/Application Support/neo4j-desktop/logs",
            "Library/Application Support/Microsoft Edge/NativeMessagingHosts/org.example.host.json",
            "Library/Application Support/Microsoft Edge Beta/NativeMessagingHosts/org.example.host.json",
            "Library/Application Support/Microsoft", "Library/Application Support/Microsoft/EdgeUpdater",
            "Library/Application Support/Yandex/YandexDisk", "Library/Application Support/Vivaldi/NativeMessagingHosts",
            "Library/Application Support/Signal Beta", "Library/Thunderbird/Crash Reports",
            "Library/Group Containers/group.strongbox.mac.mcguill/Library/Caches",
            "Library/Application Support/Tunnelblick/Logs", "Library/Logs/Viscosity",
            "Library/Group Containers/group.net.whatsapp.family", "Library/Group Containers/2BUA8C4S2C.com.1password",
            "Library/Application Support/Steam Link", "Library/Caches/Postgres", "Library/Application Support/Backupify",
            "Library/Application Support/obs-studio/logs",
            ".docker/contexts", ".cargo/registry", ".config", ".local/share", ".terraform.d/plugins",
            "Library/Application Support/qBittorrent/logs", "Library/Caches/qBittorrent", ".config/deluge/plugins",
            "Library/Application Support/Motrix/dht.dat", "Library/Application Support/WebTorrent/Posters",
            "Library/Caches/LibreOffice", "Library/Application Support/LibreOffice Beta",
            "Library/Application Support/iTerm2/version.txt", "Library/Caches/com.googlecode.iterm2",
            "Library/Application Support/Eltima Software", "Library/Application Support/Eltima Software/Elmedia Player",
            "Library/Caches/Sublime Text", "Library/Application Support/Sublime Merge",
            "Library/Application Support/minecraft/versions", "Library/Application Support/Minecraft Launcher",
            "Library/Application Support/PrismLauncher/assets", "Library/Application Support/PrismLauncher/cache",
            "Library/Application Support/Google/DriveFS/1a2b/content_cache",
            "Library/Application Support/net.imput.helium/GrShaderCache", "Library/Caches/net.imput.helium",
            ".nx/temp/D-1001-ABCD", "Documents/Notes",
            "Library/Application Support/Google/Chrome/NativeMessagingHosts/org.example.host.json",
            "Library/Application Support/Chromium/NativeMessagingHosts/org.example.host.json",
            "Library/Application Support/Mozilla/NativeMessagingHosts/org.example.host.json",
            "Library/Caches/Firefox/Profiles/abcd1234.default-release", "Library/Application Support/Google",
            "Library/Caches/Waterfox/Profiles/b1p8ayxl.default-release", "Library/Caches/zen", "Library/Caches/Floorp",
            "Library/Caches/librewolf", "Library/Caches/MullvadBrowser", "Library/Application Support/Tor Browser",
            "Library/Application Support/Google/GoogleUpdater", "Library/Application Support/BraveSoftware",
            "Library/Containers/com.culturedcode.ThingsMac", "Library/Caches/com.culturedcode.ThingsMac",
        ]
        for path in free {
            #expect(KeptOnlyHere.reason(for: "\(home)/\(path)", home: home, root: "/") == nil, "\(path)")
        }
        let freeOnTheMac = [
            "Library/Application Support/Objective Development",
            "Library/Application Support/appsolute/MAMP PRO/templates", "Library/Application Support/appsolute",
            "Library/Application Support/ZeroTier/Other", "Library/Application Support/Tunnelblick/Logs",
            "Library/Application Support/Tunnelblick/Users/me", "Library/Application Support/Signal",
            "Library/Application Support/CrashPlan/log",
        ]
        for path in freeOnTheMac {
            #expect(KeptOnlyHere.reason(for: "/\(path)", home: home, root: "/") == nil, "\(path)")
        }
        #expect(KeptOnlyHere.reason(for: "/Users/someone/Library/Application Support/Signal", home: home, root: "/") == nil)
        #expect(KeptOnlyHere.reason(for: "\(home)/Library/Application Support/ZeroTier", home: home, root: "/") == nil)
    }
}
