public import Foundation

/// An app whose own service uninstalls it once the app leaves its place, deleting what History can't put back.
public struct UninstallsItself: Sendable, Hashable {
    public let app: InstalledApp
    public let uninstaller: String

    /// Mullvad VPN's daemon watches `/Applications/Mullvad VPN.app`, and when its own program goes it logs the Mac out
    /// of the account and runs `uninstall_macos.sh`, which deletes the settings (`mullvad-daemon/src/macos.rs`).
    private static let mullvad = (identifier: "net.mullvad.vpn", path: "/Applications/Mullvad VPN.app")

    public static func when(moving urls: Set<URL>, among apps: [InstalledApp]) -> [UninstallsItself] {
        apps.filter { app in
            urls.contains(app.url) && app.bundleIdentifier == mullvad.identifier
                && PathPattern.comparablePath(of: app.url) == mullvad.path
        }.map { UninstallsItself(app: $0, uninstaller: mullvad.path + "/Contents/Resources/uninstall.sh") }
    }
}
