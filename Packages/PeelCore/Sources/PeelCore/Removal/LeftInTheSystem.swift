import Foundation

/// What an app leaves in macOS's own settings folders, such as a rule for `sudo` in `/etc/sudoers.d` or a folder of
/// programs for the shell in `/etc/paths.d`, or in a folder of its own in `/opt`, which stays once the app goes until
/// an administrator removes it. Peel never changes those folders: it names what is there and the command that does.
public struct LeftInTheSystem: Sendable, Hashable {
    /// Each item that is on this Mac, as `/etc` and `/opt` name it.
    public let paths: [String]
    private let folders: Set<String>

    /// The rule for `sudo` among `paths`, which lets programs run as root without a password, when there is one.
    public var ruleForSudo: String? {
        paths.first { $0.hasPrefix("/etc/sudoers.d/") }
    }

    /// The command that removes `paths`, which asks for an administrator's password.
    public var command: String {
        let words = paths.map(\.wordForTheShell).joined(separator: " ")
        return paths.contains(where: folders.contains) ? "sudo rm -r \(words)" : "sudo rm \(words)"
    }

    /// What `app` leaves there, as far as any of it is on this Mac.
    public static func of(_ app: InstalledApp, environment: SearchEnvironment = .current) -> LeftInTheSystem? {
        app.bundleIdentifier.flatMap { byApp[$0] }.flatMap { found($0, under: environment.rootDirectory) }
    }

    /// What a cask's app leaves there once `brew uninstall` has carried out the cask's own steps.
    public static func of(
        _ package: HomebrewPackage,
        environment: SearchEnvironment = .current
    ) -> LeftInTheSystem? {
        guard package.kind == .cask else { return nil }
        return byCask[package.fullName].flatMap { byApp[$0] }.flatMap { found($0, under: environment.rootDirectory) }
    }

    private static func found(_ paths: [String], under root: URL) -> LeftInTheSystem? {
        var there: [String] = []
        var folders: Set<String> = []
        for path in paths {
            // On macOS `/etc` is a link to `/private/etc`.
            let item = root.appending(path: path.hasPrefix("/etc/") ? "private" + path : String(path.dropFirst()))
            guard item.isThere else { continue }
            there.append(path)
            if item.isRealFolder { folders.insert(path) }
        }
        return there.isEmpty ? nil : LeftInTheSystem(paths: there, folders: folders)
    }

    private static let byApp: [String: [String]] = [
        // battery's `battery.sh`: `battery visudo` writes the rule, and `battery uninstall` leaves it.
        "co.palokaj.battery": ["/etc/sudoers.d/battery"],
        // Rancher Desktop's `lima.ts`, for its virtual machines' network. Its "Uninstalling Rancher Desktop on macOS"
        // names only the Trash and Factory Reset, and Factory Reset removes neither.
        "io.rancherdesktop.app": ["/etc/sudoers.d/zzzzz-rancher-desktop-lima", "/opt/rancher-desktop"],
        // Postgres.app's "Installing, Upgrading and Uninstalling Postgres.app": the path of its command-line tools.
        "com.postgresapp.Postgres2": ["/etc/paths.d/postgresapp"],
        // Wireshark's "Read me first": what its package that adds Wireshark to the system path writes.
        "org.wireshark.Wireshark": ["/etc/paths.d/Wireshark", "/etc/manpaths.d/Wireshark"],
    ]

    /// Casks whose own uninstall steps leave what their app put there, which Rancher Desktop's and Wireshark's remove.
    private static let byCask: [String: String] = [
        "battery": "co.palokaj.battery",
        "postgres-app": "com.postgresapp.Postgres2",
    ]
}
