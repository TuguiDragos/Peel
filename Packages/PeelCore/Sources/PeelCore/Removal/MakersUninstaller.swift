public import Foundation

/// A security or management agent whose maker documents removing it with an uninstaller of its own. Moved from its
/// place, what it keeps in the system and the settings that manage it would stay behind.
public struct MakersUninstaller: Sendable, Hashable {
    /// What the maker's page says to do.
    public enum Step: Sendable, Hashable {
        /// A command to run in Terminal.
        case command(String)
        /// An uninstaller to open.
        case uninstaller(URL)
    }

    private enum Documented: Sendable {
        case command(String)
        case uninstaller(String)
        case uninstallerInsideTheApp(String)
    }

    public let maker: String
    public let step: Step
    /// The maker's page that says how to remove it.
    public let instructions: URL

    /// Each product with the signing team and the identifiers its maker's own deployment pages give, and the step and
    /// page of its maker's uninstall instructions. An identifier names itself and any longer one after a dot.
    private static let known: [(team: String, identifiers: [String], maker: String, step: Documented, page: String)] = [
        (
            "PXPZ95SK77", ["com.paloaltonetworks.globalprotect"], "Palo Alto Networks",
            .command("sudo /Applications/GlobalProtect.app/Contents/Resources/uninstall_gp.sh"),
            "https://docs.paloaltonetworks.com/globalprotect/user-guide/6-3/globalprotect-app-for-mac/uninstall-the-globalprotect-app-for-mac"
        ),
        (
            "PXPZ95SK77", ["com.paloaltonetworks.cortex", "com.paloaltonetworks.traps"], "Palo Alto Networks",
            .uninstaller("/Library/Application Support/PaloAltoNetworks/Traps/bin/Cortex XDR Uninstaller.app"),
            "https://cortex-docs.paloaltonetworks.com/cortex-xdr-agent/9.2/cortex-xdr-agent-for-macos/uninstall-the-cortex-xdr-agent-for-mac"
        ),
        (
            "DE8Y96K9QP", ["com.cisco.secureclient"], "Cisco",
            .command("sudo /opt/cisco/secureclient/bin/cisco_secure_client_uninstall.sh"),
            "https://www.cisco.com/c/en/us/support/docs/security/umbrella/224782-uninstall-secure-client-from-macos.html"
        ),
        (
            "P8DQRXPVLP", ["com.eset.ees"], "ESET", .uninstallerInsideTheApp("Contents/Helpers/Uninstaller.app"),
            "https://support.eset.com/en/kb6420-uninstall-eset-endpoint-security-for-macos"
        ),
        (
            "UBF8T346G9", ["com.microsoft.wdav"], "Microsoft",
            .command("sudo '/Library/Application Support/Microsoft/Defender/uninstall/uninstall'"),
            "https://learn.microsoft.com/en-us/defender-endpoint/mac-resources"
        ),
        (
            "24W52P9M7W", ["com.netskope.client"], "Netskope", .uninstaller("/Applications/Remove Netskope Client.app"),
            "https://docs.netskope.com/en/uninstalling-the-netskope-client"
        ),
        (
            "AH4XFXJ7DK", ["com.fortinet.forticlient"], "Fortinet",
            .uninstaller("/Applications/FortiClientUninstaller.app"),
            "https://community.fortinet.com/t5/FortiGate/Technical-Tip-How-to-uninstall-FortiClient-on-macOS/ta-p/229617"
        ),
    ]

    /// The maker's uninstaller for `app`, known by the team of its checked signature and by its identifier, both as
    /// the maker documents them. An identifier alone is what a bundle says of itself, and would let any app keep Peel
    /// away from it.
    static func of(_ app: InstalledApp) -> MakersUninstaller? {
        guard let team = app.teamIdentifier else { return nil }
        let identifier = app.bundleIdentifier.lowercased()
        guard let product = known.first(where: { product in
            product.team == team && product.identifiers.contains { identifier == $0 || identifier.hasPrefix($0 + ".") }
        }), let instructions = URL(string: product.page) else { return nil }
        let step: Step = switch product.step {
        case .command(let command): .command(command)
        case .uninstaller(let path): .uninstaller(URL(filePath: path, directoryHint: .isDirectory))
        case .uninstallerInsideTheApp(let path):
            .uninstaller(app.url.appending(path: path, directoryHint: .isDirectory))
        }
        return MakersUninstaller(maker: product.maker, step: step, instructions: instructions)
    }
}
