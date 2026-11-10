import PeelCore
import SwiftUI

/// A command an app's removal leaves to the person, with the sentence that says when and why to run it.
struct CommandToRun: Identifiable {
    let app: String
    let said: Text
    let command: String
    /// True for one still to run once the app is gone, which the alert after the move gives again.
    let isForAfterwards: Bool

    var id: String { "\(app)\n\(command)" }

    /// The commands of `app` going, said as its question says them: the step for its root certificate, `first`, what
    /// it leaves in the system, and Homebrew's uninstall for `cask`, which is nil while Homebrew's record of the app
    /// goes with it. `naming`, as several apps' page names the app, goes before Homebrew's sentence, which doesn't say
    /// which app it is.
    static func of(
        _ app: InstalledApp, first: CommandToRunFirst?, leftInTheSystem: LeftInTheSystem?, cask: HomebrewPackage?,
        naming: String? = nil
    ) -> [CommandToRun] {
        let name = naming ?? app.name
        var commands: [CommandToRun] = []
        if let root = TrustedRoot.of(app), case .command(let command) = root.step {
            let stays = Text("\(app.name)’s root certificate stays trusted on this Mac after the app goes.")
            commands.append(CommandToRun(
                app: name, said: Text("\(stays)\n\n\(root.step(in: app.name))"), command: command,
                isForAfterwards: false
            ))
        }
        if let first {
            commands.append(CommandToRun(
                app: name, said: first.note(for: app.name), command: first.command, isForAfterwards: false
            ))
        }
        if let left = leftInTheSystem {
            let said = Text("\(left.whatStays(after: app.name))\n\n\(left.step)")
            commands.append(CommandToRun(
                app: name,
                said: AdministratorCommand.needsAnAdministrator(left.command)
                    ? Text("\(said)\n\n\(AdministratorCommand.note)") : said,
                command: left.command,
                isForAfterwards: true
            ))
        }
        if let cask {
            let token = Homebrew.lastWord(naming: cask.name)
            let record = Text("Homebrew installed this app and will keep listing it as installed. To take it off that list, run `brew uninstall --cask \(token)`: Homebrew then carries out the cask’s own uninstall steps, which can delete files for good.")
            commands.append(CommandToRun(
                app: name, said: naming.map { Text("\($0): \(record)") } ?? record,
                command: "brew uninstall --cask \(token)", isForAfterwards: true
            ))
        }
        return commands
    }
}

/// The commands an app's removal leaves to the person, each with a way to copy it, since the words of the question
/// before the move can't be selected.
struct CommandsToRunSection: View {
    let commands: [CommandToRun]

    var body: some View {
        if !commands.isEmpty {
            Section {
                ForEach(commands) { command in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        command.said
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        CopyButton(text: command.command)
                    }
                }
                .listRowSeparator(.hidden)
            } header: {
                heading(
                    "Commands to Run",
                    "Peel never runs these itself. Copy each one and run it in Terminal, before the app goes or after, as its sentence says."
                )
            }
        }
    }
}
