@testable import PeelCore
import Testing

struct KeptOnlyHereTests {
    private let home = "/Users/me"

    @Test func answersForThousandsOfItemsAtOnce() {
        let paths = (0..<5000).map { "\(home)/Library/Application Support/org.example.app\($0)/data" }
        let took = processorTime {
            for path in paths { _ = KeptOnlyHere.reason(for: path, home: home, root: "/") }
        }
        #expect(took < .milliseconds(300))
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
            ("Library/Application Support/Tunnelblick/Configurations/work.tblk", .holdsVPNConnections),
            ("Library/Application Support/Viscosity", .holdsVPNConnections),
            ("Library/Application Support/Steam", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Steam/userdata/123/570/remote", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/minecraft", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/minecraft/saves/New World/level.dat", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/minecraft/screenshots/2026-10-25_21.04.12.png", .holdsWorkMadeWithTheApp),
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
        ]
        for (path, reason) in heldOnTheMac {
            #expect(KeptOnlyHere.reason(for: "/\(path)", home: home, root: "/") == reason, "\(path)")
        }
    }

    @Test func leavesWhatSitsBesideOrAroundThem() {
        let free = [
            "Library/Application Support", "Library/Group Containers", "Library", "Library/Caches/Signal",
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
        ]
        for path in freeOnTheMac {
            #expect(KeptOnlyHere.reason(for: "/\(path)", home: home, root: "/") == nil, "\(path)")
        }
        #expect(KeptOnlyHere.reason(for: "/Users/someone/Library/Application Support/Signal", home: home, root: "/") == nil)
        #expect(KeptOnlyHere.reason(for: "\(home)/Library/Application Support/ZeroTier", home: home, root: "/") == nil)
    }
}
