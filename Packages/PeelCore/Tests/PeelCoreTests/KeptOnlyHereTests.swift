@testable import PeelCore
import Testing

struct KeptOnlyHereTests {
    private let home = "/Users/me"

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
            ("Library/Application Support/Tunnelblick/Configurations/work.tblk", .holdsVPNConnections),
            ("Library/Application Support/Viscosity", .holdsVPNConnections),
            ("Library/Application Support/Steam", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Steam/userdata/123/570/remote", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Postgres/var-17", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/.com.example.notes.backups", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Example/Backups", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/obs-studio", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/obs-studio/basic/scenes/Untitled.json", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/LibreOffice", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/LibreOffice/4/user/basic/Standard/Module1.xba", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/OpenOffice/4/user/template/Letter.ott", .holdsWorkMadeWithTheApp),
            ("Library/Application Support/Transmission", .holdsTorrents),
            ("Library/Application Support/Transmission/Transfers.plist", .holdsTorrents),
            ("Library/Application Support/qBittorrent", .holdsTorrents),
            ("Library/Application Support/qBittorrent/BT_backup/1a2b.fastresume", .holdsTorrents),
            ("Library/Application Support/qBittorrent/torrents.db", .holdsTorrents),
            ("Library/Application Support/BiglyBT/active/1a2b.dat", .holdsTorrents),
            (".config/deluge", .holdsTorrents), (".config/deluge/state/torrents.fastresume", .holdsTorrents),
            ("Library/Application Support/Motrix/download.session", .holdsTorrents),
            ("Library/Application Support/WebTorrent/Torrents/1a2b.torrent", .holdsTorrents),
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
        ]
        for (path, reason) in heldOnTheMac {
            #expect(KeptOnlyHere.reason(for: "/\(path)", home: home, root: "/") == reason, "\(path)")
        }
    }

    @Test func leavesWhatSitsBesideOrAroundThem() {
        let free = [
            "Library/Application Support", "Library/Group Containers", "Library", "Library/Caches/Signal",
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
        ]
        for path in free {
            #expect(KeptOnlyHere.reason(for: "\(home)/\(path)", home: home, root: "/") == nil, "\(path)")
        }
        let freeOnTheMac = [
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
