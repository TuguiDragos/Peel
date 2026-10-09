import Foundation
internal import PeelPrivileged

/// Where apps keep what may exist only on this Mac: local mail, message history, password vaults and sign-in codes,
/// VPN connections, and what the person made with an app, such as saved games, databases, and the app's own backups.
/// A folder at or inside one, or the app's folder that holds one, is shown and never selected for the person, who
/// can still select it.
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
    ]

    static func reason(for path: String, home: String) -> HoldBack? {
        let item = PathComponents.of(path.lowercased())
        let home = (home as NSString).standardizingPath
        for (folder, inside, reason) in places {
            let folder = PathComponents.of((home as NSString).appendingPathComponent(folder).lowercased())
            let place = folder + (inside.map { PathComponents.of($0.lowercased()) } ?? [])
            if item.starts(with: place) || item == folder { return reason }
        }
        // What an app names as its backups is a copy the person may need, whichever app made it.
        let words = (item.last ?? "").split { !$0.isLetter }
        return words.contains("backup") || words.contains("backups") ? .holdsWorkMadeWithTheApp : nil
    }
}
