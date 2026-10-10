public import Foundation
internal import PeelPrivileged

/// An app whose own uninstaller runs once the app leaves its place, deleting what History can't put back.
public struct UninstallsItself: Sendable, Hashable {
    public enum Uninstaller: Sendable, Hashable {
        /// Logs the Mac out of the account and deletes the settings; the script can be run instead.
        case logsOut(script: String)
        /// Asks for an administrator, then deletes the app, even from the Trash, and its system files.
        case deletesTheApp
    }

    public let app: InstalledApp
    public let uninstaller: Uninstaller
    private let removed: Set<String>

    /// Mullvad VPN's daemon watches `/Applications/Mullvad VPN.app`, and when its own program goes it logs the Mac out
    /// of the account and runs `uninstall_macos.sh`, which deletes the settings (`mullvad-daemon/src/macos.rs`).
    private static let mullvad = (identifier: "net.mullvad.vpn", path: "Applications/Mullvad VPN.app")

    private static let mullvadRemoves = (
        root: [
            "Library/LaunchDaemons/net.mullvad.daemon.plist",
            "usr/local/share/zsh/site-functions/_mullvad",
            "opt/homebrew/share/fish/vendor_completions.d/mullvad.fish",
            "usr/local/share/fish/vendor_completions.d/mullvad.fish",
            "usr/local/share/nushell/vendor/autoload/mullvad.nu",
            "usr/local/bin/mullvad",
            "usr/local/bin/mullvad-problem-report",
            "private/var/db/receipts/net.mullvad.vpn.bom",
            "private/var/db/receipts/net.mullvad.vpn.plist",
            "private/var/log/mullvad-vpn",
            "private/var/root/Library/Caches/mullvad-vpn",
            "Library/Caches/mullvad-vpn",
            "private/etc/mullvad-vpn",
        ],
        home: ["Library/Logs/Mullvad VPN", "Library/Application Support/Mullvad VPN"]
    )

    /// Citrix's agent `com.citrix.UninstallMonitor` watches the app's place and, once the app is gone, opens the
    /// uninstaller that deletes the app and its system files (Citrix's "Uninstall Citrix Workspace app for Mac").
    private static let citrix = (
        identifier: "com.citrix.receiver.nomas",
        monitor: "Library/LaunchAgents/com.citrix.UninstallMonitor.plist"
    )

    private static let citrixRemoves = (
        root: [
            "Library/LaunchAgents/com.citrix.AuthManager_Mac.plist",
            "Library/LaunchAgents/com.citrix.ReceiverHelper.plist",
            "Library/LaunchAgents/com.citrix.ServiceRecords.plist",
            "Library/LaunchAgents/com.citrix.safariadapter.plist",
            "Library/LaunchAgents/com.citrix.UninstallMonitor.plist",
            "Library/LaunchAgents/com.citrix.devicetrust.launchagent.plist",
            "Library/LaunchDaemons/com.citrix.CtxWorkspaceHelperDaemon.plist",
            "Library/LaunchDaemons/com.citrix.ReceiverUninstallHelper.plist",
            "Library/LaunchDaemons/com.citrix.ctxusbd.plist",
            "Library/LaunchDaemons/com.citrix.ctxworkspaceupdater.plist",
            "Library/Citrix Workspace",
            "Library/Application Support/Citrix Receiver",
            "Library/Application Support/deviceTRUST",
            "Library/Logs/Citrix Workspace",
            "private/var/db/receipts/com.citrix.ICAClient.bom",
            "private/var/db/receipts/com.citrix.ICAClient.plist",
        ],
        home: [
            "Library/Logs/Citrix Workspace",
            "Library/Application Support/Citrix Workspace",
            "Library/HTTPStorages/com.citrix.receiver.nomas",
            "Library/Preferences/com.citrix.receiver.nomas.plist",
        ]
    )

    public static func of(_ app: InstalledApp, environment: SearchEnvironment = .current) -> UninstallsItself? {
        mullvad(app, environment: environment) ?? citrix(app, environment: environment)
    }

    private static func mullvad(_ app: InstalledApp, environment: SearchEnvironment) -> UninstallsItself? {
        let place = environment.rootDirectory.appending(path: mullvad.path)
        guard
            app.bundleIdentifier == mullvad.identifier,
            PathPattern.comparablePath(of: app.url) == PathPattern.comparablePath(of: place)
        else { return nil }
        let script = place.appending(path: "Contents/Resources/uninstall.sh").path(percentEncoded: false)
        return UninstallsItself(
            app: app,
            uninstaller: .logsOut(script: script),
            removed: paths(mullvadRemoves, in: environment)
        )
    }

    private static func citrix(_ app: InstalledApp, environment: SearchEnvironment) -> UninstallsItself? {
        let place = PathPattern.comparablePath(of: app.url)
        guard
            app.bundleIdentifier == citrix.identifier,
            let monitor = JobDefinition(contentsOf: environment.rootDirectory.appending(path: citrix.monitor)),
            !monitor.isDisabled,
            monitor.watchPaths.contains(where: { PathPattern.comparablePath(of: URL(filePath: $0)) == place }),
            let program = monitor.program,
            FileManager.default.isExecutableFile(atPath: program)
        else { return nil }
        return UninstallsItself(app: app, uninstaller: .deletesTheApp, removed: paths(citrixRemoves, in: environment))
    }

    private static func paths(
        _ removes: (root: [String], home: [String]),
        in environment: SearchEnvironment
    ) -> Set<String> {
        let urls = removes.root.map { environment.rootDirectory.appending(path: $0) }
            + removes.home.map { environment.homeDirectory.appending(path: $0) }
        return Set(urls.map(PathPattern.comparablePath))
    }

    func removes(_ url: URL) -> Bool {
        let path = PathPattern.comparablePath(of: url)
        return removed.contains { PathComponents.isPath(path, atOrInside: $0) }
    }

    public static func when(
        moving urls: Set<URL>,
        among apps: [InstalledApp],
        environment: SearchEnvironment = .current
    ) -> [UninstallsItself] {
        apps.filter { urls.contains($0.url) }.compactMap { of($0, environment: environment) }
    }
}
