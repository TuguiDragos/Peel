/// A root certificate a tool or an app adds to the certificates the Mac trusts, which stays trusted after it goes
/// until its maker's step takes it out. Peel never reads or changes a keychain: it names the certificate and the step.
public struct TrustedRoot: Sendable, Hashable {
    public enum Step: Sendable, Hashable {
        /// A command of the tool's own, run before it goes.
        case command(String)
        /// A command in the app's own menus, chosen before it goes.
        case menu(String)
        /// Keychain Access, where Apple's Keychain Access User Guide changes a certificate's trust settings.
        case keychainAccess
    }

    /// How the certificate's name begins in Keychain Access.
    public let certificate: String
    public let step: Step

    /// What a package Homebrew installed leaves trusted once `brew uninstall` has removed it.
    public static func of(_ package: HomebrewPackage) -> TrustedRoot? {
        switch package.kind {
        case .formula: byFormula[package.fullName]
        case .cask: byCask[package.fullName]
        }
    }

    /// What an app leaves trusted once Peel has moved it to the Trash, which runs none of a cask's uninstall steps.
    public static func of(_ app: InstalledApp) -> TrustedRoot? {
        app.bundleIdentifier.flatMap { byApp[$0] }
    }

    private static let byFormula: [String: TrustedRoot] = [
        // Caddy's "Automatic HTTPS" and "Command Line" pages.
        "caddy": TrustedRoot(certificate: "Caddy Local Authority", step: .command("caddy untrust")),
        // mkcert's README and usage text.
        "mkcert": TrustedRoot(certificate: "mkcert", step: .command("mkcert -uninstall")),
        // puma-dev's README and its `Uninstall` on macOS.
        "puma/puma/puma-dev": TrustedRoot(certificate: "Puma-dev CA", step: .command("puma-dev -uninstall")),
    ]

    /// Casks whose own uninstall steps leave their certificate, which Charles's and Proxyman's delete.
    private static let byCask: [String: TrustedRoot] = [
        // mitmproxy's "Certificates" page puts it in the System keychain, and its cask removes no certificate.
        "mitmproxy": TrustedRoot(certificate: "mitmproxy", step: .keychainAccess),
    ]

    private static let byApp: [String: TrustedRoot] = [
        // Charles's "SSL Certificates" page.
        "com.xk72.Charles": TrustedRoot(certificate: "Charles Proxy", step: .keychainAccess),
        // Proxyman's "Install & Trust Proxyman Certificates on your Mac".
        "com.proxyman.NSProxy": TrustedRoot(
            certificate: "Proxyman CA", step: .menu("Certificate > Reset all Proxyman Certificates")
        ),
        // PortSwigger's guide to installing Burp's CA certificate in Chrome on macOS: the person trusts it in the
        // System keychain, and deletes it there to stop. Burp Suite Community Edition, then Professional.
        "com.install4j.6592-1155-2163-3973.70": TrustedRoot(certificate: "PortSwigger CA", step: .keychainAccess),
        "com.install4j.7318-9294-3757-1226.70": TrustedRoot(certificate: "PortSwigger CA", step: .keychainAccess),
    ]
}
