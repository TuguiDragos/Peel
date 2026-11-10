public import ArgumentParser
import Darwin
import Foundation

public struct PeelCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "peel",
        abstract: "Find what apps leave behind and move it to the Trash.",
        discussion: "Peel only moves files to the Trash, so you can put them back. Items that need administrator access are left for the Peel app: its helper moves them, or the app says how to remove them in Finder. The tool refuses to run with sudo. History, the record of refusals, and the exclusions are in ~/Library/Application Support/Peel, shared with the Peel app, and in JSON a size Peel couldn't measure is null. The tool writes English whatever the Mac's language, since scripts read what it prints. Exit status: 0, it did what was asked; 1, something failed or stayed where it was, History couldn't record what moved, or, for `peel updates`, no check got an answer; 2, you answered no; 64, the command or its options are wrong, or Peel would have to ask and can't (add --yes).",
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

    /// A command with no subcommand is wrong, so a script that lost its subcommand doesn't read a success.
    public func run() async throws {
        Output.note(Self.helpMessage())
        throw ExitCode.validationFailure
    }

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
        if isGreeting(Array(CommandLine.arguments.dropFirst())) {
            Output.write(FaceArt.greeting())
            return
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

    /// Whether the arguments ask for `peel peel`, a greeting no help or manual page lists. It is answered before
    /// ArgumentParser reads them, since the manual page it writes names every subcommand, hidden or not.
    static func isGreeting(_ arguments: [String]) -> Bool {
        arguments == ["peel"]
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
