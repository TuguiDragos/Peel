public import Foundation

/// An app its maker discontinued and asks people to uninstall for its security flaws, with the advisory that says so.
public struct DiscontinuedApp: Sendable, Hashable {
    public let maker: String
    public let advisory: URL

    private static let known: [String: (maker: String, advisory: String)] = [
        "com.intel.powergadget": (
            "Intel", "https://www.intel.com/content/www/us/en/security-center/advisory/intel-sa-01037.html"
        ),
    ]

    public static func of(_ app: InstalledApp) -> DiscontinuedApp? {
        guard let identifier = app.bundleIdentifier?.lowercased(), let found = known[identifier],
              let advisory = URL(string: found.advisory)
        else { return nil }
        return DiscontinuedApp(maker: found.maker, advisory: advisory)
    }
}
