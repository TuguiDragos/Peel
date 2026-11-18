import PeelCore
import SwiftUI

/// The note on the page of a security or management agent or a VPN, or of such an uninstaller: its maker's own
/// uninstaller removes it whole, so Peel leaves it and its files where they are and offers the maker's step and
/// instructions.
struct MakersUninstallerNotice: View {
    @Environment(HelperModel.self) private var helper
    let app: String
    let uninstaller: MakersUninstaller
    /// The page's own words for the circled i, in place of the app page's, as on a job's page, which offers its
    /// buttons.
    var saying: Text?

    var body: some View {
        Notice(
            title: Text(Self.title(of: uninstaller)), detail: detail, kind: .note,
            info: (name: String(localized: Self.title(of: uninstaller)), detail: saying ?? said)
        ) {
            Link("\(uninstaller.maker)’s Instructions", destination: uninstaller.instructions)
            switch uninstaller.step {
            case .command(let command):
                CopyButton(text: command, title: "Copy Uninstall Command")
            case .uninstaller(let url):
                OpenUninstallerButton(uninstaller: url, team: uninstaller.team)
            case .inTheApp(let url):
                Button("Open \(app)") { NSWorkspace.shared.open(url) }
            case .onItsDiskImage, .fromTheMakersPage, .notOnTheMac, .notTrusted:
                EmptyView()
            }
        }
    }

    static func title(of uninstaller: MakersUninstaller) -> LocalizedStringResource {
        if let product = uninstaller.removes {
            "\(uninstaller.maker)’s uninstaller for \(product)"
        } else {
            "Removed with \(uninstaller.maker)’s own uninstaller"
        }
    }

    /// Where the uninstaller is, for a step the note offers no button for, as `peel uninstall` says it.
    static func whereItIs(_ uninstaller: MakersUninstaller, app: String) -> LocalizedStringResource? {
        switch uninstaller.step {
        case .onItsDiskImage: "Its uninstaller is on the disk image \(app) came on."
        case .fromTheMakersPage: "Its uninstaller is a download from \(uninstaller.maker)’s page."
        case .notOnTheMac: "The uninstaller \(uninstaller.maker) names isn’t on this Mac, so follow \(uninstaller.maker)’s instructions."
        case .notTrusted:
            "Peel can’t vouch for the uninstaller on this Mac, since programs other than \(uninstaller.maker)’s could have changed it, so follow \(uninstaller.maker)’s instructions."
        case .command, .uninstaller, .inTheApp: nil
        }
    }

    /// What has to be seen to act: where the uninstaller is, or that its command needs an administrator. The rest is
    /// in the circled i beside the title.
    private var detail: Text? {
        if let whereItIs = Self.whereItIs(uninstaller, app: app) {
            return Text(whereItIs)
        }
        guard case .command(let command) = uninstaller.step,
              AdministratorCommand.needsAnAdministrator(command, isAdministrator: helper.isAdministrator)
        else { return nil }
        return AdministratorCommand.note
    }

    private var said: Text {
        let why = if let product = uninstaller.removes {
            Text("\(uninstaller.maker) documents removing \(product) by opening this app, which then removes itself too. Moving only this app would leave \(product) behind, so Peel leaves it for you to open.")
        } else {
            Text("\(uninstaller.maker) documents removing \(app) with its own uninstaller, which also takes what it keeps in the system and the settings that manage it. Moved from here, those would stay behind, so Peel leaves it and its files where they are.")
        }
        guard let left = uninstaller.leftBehind else { return why }
        return [left.whatStays(after: app), left.step].reduce(why) { Text("\($0)\n\n\($1)") }
    }
}
