public import ArgumentParser
import Darwin
import Foundation

public struct PeelCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "peel",
        abstract: "Find what apps leave behind and move it to the Trash.",
        discussion: "Peel only moves files to the Trash, so you can put them back. Items that need administrator access are left for the Peel app. The tool writes English whatever the Mac's language, since scripts read what it prints.",
        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        subcommands: [
            AppsCommand.self,
            InventoryCommand.self,
            LeftoversCommand.self,
            UninstallCommand.self,
            OrphansCommand.self,
            HistoryCommand.self,
            RestoreCommand.self,
            ExclusionsCommand.self,
            CachesCommand.self,
            ProjectsCommand.self,
            DuplicatesCommand.self,
            SearchCommand.self,
            UpdatesCommand.self,
        ]
    )

    public init() {}

    /// Parses the process arguments and runs the matching command.
    ///
    /// Refuses to run as root. `access(2)` checks the real user ID, which `sudo` sets to root, so every file would
    /// look writable. The tool itself would then move items that need administrator access, without the privileged
    /// helper's checks, and put them in root's Trash, where the user never sees them.
    public static func start() async {
        if geteuid() == 0 {
            Output.note("Don't run `peel` with `sudo`. What needs administrator access is removed by the Peel app, which has the checks for it.")
            Darwin.exit(1)
        }
        await main()
    }
}
