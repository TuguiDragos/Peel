import Foundation

/// A command an app's maker gives to undo what the app changed in the Mac's own settings, such as battery's
/// `battery uninstall`. Peel names it before the app goes, and runs nothing itself.
public struct CommandToRunFirst: Sendable, Hashable {
    public enum Undoes: Sendable, Hashable {
        /// A limit on charging the app set in the Mac's System Management Controller, which the command lifts while it
        /// removes the tools the app put in `/usr/local/bin`.
        case chargingLimit
    }

    public let command: String
    public let undoes: Undoes

    /// The command for `app`, when the tool that runs it is on this Mac.
    public static func of(_ app: InstalledApp, environment: SearchEnvironment = .current) -> CommandToRunFirst? {
        app.bundleIdentifier.flatMap { byApp[$0] }.flatMap { found($0, under: environment.rootDirectory) }
    }

    /// The command for a cask's app, before `brew uninstall` takes the app and what the cask's own steps delete.
    public static func of(
        _ package: HomebrewPackage,
        environment: SearchEnvironment = .current
    ) -> CommandToRunFirst? {
        guard package.kind == .cask else { return nil }
        return byCask[package.fullName].flatMap { byApp[$0] }.flatMap { found($0, under: environment.rootDirectory) }
    }

    private static func found(
        _ entry: (tool: String, command: String, undoes: Undoes),
        under root: URL
    ) -> CommandToRunFirst? {
        root.appending(path: entry.tool).isThere ? CommandToRunFirst(command: entry.command, undoes: entry.undoes) : nil
    }

    private static let byApp: [String: (tool: String, command: String, undoes: Undoes)] = [
        // battery's README and `battery.sh`: `battery uninstall` enables charging again and removes `smc` and `battery`
        // from `/usr/local/bin`, where the app puts them.
        "co.palokaj.battery": ("usr/local/bin/battery", "battery uninstall", .chargingLimit),
    ]

    /// Casks whose own uninstall steps leave the change, as the battery cask does: it deletes only `smc`.
    private static let byCask: [String: String] = [
        "battery": "co.palokaj.battery",
    ]
}
