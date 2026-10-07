public import Foundation
internal import PeelPrivileged

/// An app whose own service uninstalls it once the app leaves its place, deleting what History can't put back.
public struct UninstallsItself: Sendable, Hashable {
    public let app: InstalledApp
    public let uninstaller: String
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

    public static func of(_ app: InstalledApp, environment: SearchEnvironment = .current) -> UninstallsItself? {
        let root = environment.rootDirectory
        let place = root.appending(path: mullvad.path)
        guard
            app.bundleIdentifier == mullvad.identifier,
            PathPattern.comparablePath(of: app.url) == PathPattern.comparablePath(of: place)
        else { return nil }
        let removed = mullvadRemoves.root.map { root.appending(path: $0) }
            + mullvadRemoves.home.map { environment.homeDirectory.appending(path: $0) }
        return UninstallsItself(
            app: app,
            uninstaller: place.appending(path: "Contents/Resources/uninstall.sh").path(percentEncoded: false),
            removed: Set(removed.map(PathPattern.comparablePath))
        )
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
