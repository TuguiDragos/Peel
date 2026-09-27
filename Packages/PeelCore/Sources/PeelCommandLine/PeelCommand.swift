public import ArgumentParser
import Darwin
import Foundation

public struct PeelCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "peel",
        abstract: "Find what apps leave behind and move it to the Trash.",
        discussion: "Peel only moves files to the Trash, so you can put them back. Items that need administrator access are left for the Peel app. The tool writes English whatever the Mac's language, since scripts read what it prints. Exit status: 0 when it did what was asked, 1 when something failed or stayed where it was, 2 when you answered no, and 64 when the command or its options are wrong, or when Peel would have to ask and can't (add --yes).",
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
        do {
            var command = try await asyncParseAsRoot()
            if var asynchronous = command as? any AsyncParsableCommand {
                try await asynchronous.run()
            } else {
                try command.run()
            }
        } catch {
            guard report(error) else { exit(withError: error) }
            Darwin.exit(EXIT_FAILURE)
        }
    }

    /// Writes a failure of Peel's own as a note, where what could hide or reorder text is shown as `?`: it names
    /// apps and paths from other people's bundles. Any other error is left for ArgumentParser to print.
    @discardableResult
    static func report(_ error: any Error) -> Bool {
        guard error is CommandFailure || error is AppLookup.Failure else { return false }
        Output.note("Error: \(error)")
        return true
    }
}
