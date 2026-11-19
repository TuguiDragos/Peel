import PeelCore
import SwiftUI

/// The note on the page of a security or management agent or a VPN, or of such an uninstaller: its maker's own
/// uninstaller removes it whole, so Peel leaves it and its files where they are and offers the maker's step and
/// instructions.
struct MakersUninstallerNotice: View {
    @Environment(HelperModel.self) private var helper
    let app: String
    let uninstaller: MakersUninstaller
    /// The page's own words for why Peel leaves it, in place of the app page's, as on a job's page.
    var saying: Text?
    var isForWhatIsLeft = false

    var body: some View {
        Notice(
            title: Text(Self.title(of: uninstaller, isForWhatIsLeft: isForWhatIsLeft)), detail: explanation,
            kind: .note,
            link: (uninstaller.instructions, String(localized: "Instructions from \(uninstaller.maker)"))
        ) {
            ForEach(Self.actions(for: uninstaller), id: \.self) { action in
                switch action {
                case .openUninstaller(let url):
                    OpenUninstallerButton(uninstaller: url, team: uninstaller.team)
                case .copyCommand(let command):
                    CopyButton(text: command, title: "Copy Command")
                case .openTerminal:
                    OpenTerminalButton()
                case .openApp(let url):
                    OpenAppButton(app: url, name: app)
                case .openWebsite(let url):
                    Link("Open Website", destination: url)
                }
            }
        }
    }

    /// A button of the note, by the step it takes.
    enum Action: Hashable {
        case openUninstaller(URL)
        case copyCommand(String)
        case openTerminal
        case openApp(URL)
        case openWebsite(URL)
    }

    /// The buttons for `uninstaller`'s step: what is on the Mac opens, a command is copied for Terminal, and any other
    /// step leads to its maker's page.
    static func actions(for uninstaller: MakersUninstaller) -> [Action] {
        switch uninstaller.step {
        case .command(let command): [.copyCommand(command), .openTerminal]
        case .uninstaller(let url): [.openUninstaller(url)]
        case .inTheApp(let url): [.openApp(url)]
        case .onItsDiskImage, .fromTheMakersPage, .notOnTheMac, .notTrusted: [.openWebsite(uninstaller.instructions)]
        }
    }

    static func title(of uninstaller: MakersUninstaller, isForWhatIsLeft: Bool) -> LocalizedStringResource {
        if isForWhatIsLeft { return "Use the uninstaller from its maker" }
        return uninstaller.removes == nil ? "Use its own uninstaller" : "This app is an uninstaller"
    }

    /// What to do, as the maker's step says it: the first sentence of the circled i.
    static func step(of uninstaller: MakersUninstaller, isForWhatIsLeft: Bool) -> LocalizedStringResource? {
        switch uninstaller.step {
        case .command: "Copy the command, paste it into Terminal, and press Return."
        case .uninstaller:
            if uninstaller.removes != nil { nil } else if isForWhatIsLeft {
                "Its maker offers an uninstaller that removes what the app left."
            } else {
                "Its uninstaller removes the app and everything it keeps in the system."
            }
        case .inTheApp: "Open the app and follow the steps its maker gives."
        case .onItsDiskImage: "Its uninstaller is on the disk image the app came on."
        case .fromTheMakersPage: "Its maker offers the uninstaller on its website."
        case .notOnTheMac:
            "The uninstaller \(uninstaller.maker) names is not on this Mac, so follow the instructions from \(uninstaller.maker)."
        case .notTrusted:
            "Peel cannot vouch for the uninstaller on this Mac, since programs not made by \(uninstaller.maker) could have changed it, so follow the instructions from \(uninstaller.maker)."
        }
    }

    /// The step, what a command run with `sudo` asks for, and why Peel leaves it where it is.
    private var explanation: Text {
        var sentences = [Self.step(of: uninstaller, isForWhatIsLeft: isForWhatIsLeft).map { Text($0) }]
        if case .command(let command) = uninstaller.step, AdministratorCommand.runsWithSudo(command) {
            sentences.append(helper.isAdministrator ? Text("It asks for an administrator password.") : AdministratorCommand.note)
        }
        sentences.append(saying ?? said)
        let parts = sentences.compactMap(\.self)
        return parts.dropFirst().reduce(parts[0]) { Text("\($0)\n\n\($1)") }
    }

    private var said: Text {
        guard !isForWhatIsLeft else {
            return Text("The uninstaller from \(uninstaller.maker) also takes what the app kept in the system, which may not all be listed here.")
        }
        let why = if let product = uninstaller.removes {
            Text("\(uninstaller.maker) documents removing \(product) by opening this app, which then removes itself too. Moving only this app would leave \(product) behind, so Peel leaves it for you to open.")
        } else {
            Text("Peel leaves it where it is, since a move would leave behind what it keeps in the system.")
        }
        guard let left = uninstaller.leftBehind else { return why }
        return [left.whatStays(after: app), left.step].reduce(why) { Text("\($0)\n\n\($1)") }
    }
}
