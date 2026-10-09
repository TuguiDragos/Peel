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
            ("Library/Group Containers/group.strongbox.mac.mcguill", .holdsPasswordsOrCodes),
            ("Library/Containers/io.ente.auth.mac", .holdsPasswordsOrCodes),
            ("Library/Application Support/Tunnelblick/Configurations/work.tblk", .holdsVPNConnections),
            ("Library/Application Support/Viscosity", .holdsVPNConnections),
        ]
        for (path, reason) in held {
            #expect(KeptOnlyHere.reason(for: "\(home)/\(path)", home: home) == reason, "\(path)")
        }
    }

    @Test func leavesWhatSitsBesideOrAroundThem() {
        let free = [
            "Library/Application Support", "Library/Group Containers", "Library", "Library/Caches/Signal",
            "Library/Application Support/Signal Beta", "Library/Thunderbird/Crash Reports",
            "Library/Group Containers/group.strongbox.mac.mcguill/Library/Caches",
            "Library/Application Support/Tunnelblick/Logs", "Library/Logs/Viscosity",
            "Library/Group Containers/group.net.whatsapp.family",
        ]
        for path in free {
            #expect(KeptOnlyHere.reason(for: "\(home)/\(path)", home: home) == nil, "\(path)")
        }
        #expect(KeptOnlyHere.reason(for: "/Users/someone/Library/Application Support/Signal", home: home) == nil)
    }
}
