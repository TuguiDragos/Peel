public import Foundation

/// A security or management agent, a VPN, or a backup app whose maker documents removing it with an uninstaller of its
/// own, or such an uninstaller itself. Moved from its place, what the product keeps in the system and the settings that
/// manage it would stay behind.
public struct MakersUninstaller: Sendable, Hashable {
    /// What the maker's page says to do.
    public enum Step: Sendable, Hashable {
        /// A command to run in Terminal.
        case command(String)
        /// An uninstaller to open.
        case uninstaller(URL)
        /// A command in the app's own windows or menus, so the app is what to open.
        case inTheApp(URL)
        /// An uninstaller that comes on the disk image the app came on rather than on the Mac.
        case onItsDiskImage
    }

    private enum Documented: Sendable {
        case command(String)
        case uninstaller(String)
        case uninstallerInsideTheApp(String)
        /// The app is the uninstaller, which removes the product named here and then itself.
        case itself(removing: String)
        case inTheApp
        case onItsDiskImage
        /// The first script, run with `sudo`, with its own page while it is on the Mac, and the other one, with the
        /// product's page, when it is not.
        case scriptOnTheMac(String, page: String, otherwise: String)
    }

    public let maker: String
    public let step: Step
    /// The maker's page that says how to remove it.
    public let instructions: URL
    /// The product this app removes, when the app is the uninstaller itself rather than the product.
    public let removes: String?

    /// Each product with the signing team and the identifiers its maker's own pages or its signed bundle give, and the
    /// step and page of its maker's uninstall instructions. An identifier names itself and any longer one after a dot.
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
        (
            "GUNFMW623Y", ["com.bitdefender.endpointsecurityformac"], "Bitdefender",
            .uninstaller("/Applications/Bitdefender/EndpointSecurityforMacUninstaller.app"),
            "https://www.bitdefender.com/business/support/en/77209-87953-uninstalling-security-agents.html"
        ),
        (
            "2H5GFH3774", ["com.sophos.endpoint.uiserver"], "Sophos",
            .uninstaller("/Applications/Sophos/Remove Sophos Endpoint.app"),
            "https://docs.sophos.com/esg/endpoint/help/en-us/help/Uninstall/"
        ),
        (
            "TC292Y5427", ["com.express.vpn"], "ExpressVPN", .inTheApp,
            "https://www.expressvpn.com/support/troubleshooting/uninstall-expressvpn-app/"
        ),
        (
            "5357M5NW9W", ["com.privateinternetaccess.vpn"], "Private Internet Access", .inTheApp,
            "https://helpdesk.privateinternetaccess.com/hc/en-us/articles/46565840048027-macOS-Uninstalling-the-PIA-App-Using-the-In-App-Uninstaller"
        ),
        (
            "68WVV388M8", ["com.cloudflare.1dot1dot1dot1.macos"], "Cloudflare",
            .command("\"/Applications/Cloudflare WARP.app/Contents/Resources/uninstall.sh\""),
            "https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/cloudflare-one-client/uninstall/"
        ),
        (
            "8ZD9JUCZ4V", ["com.zerotier.zerotier-ui", "com.zerotier.zerotier-one"], "ZeroTier",
            .command("sudo \"/Library/Application Support/ZeroTier/One/uninstall.sh\""),
            "https://docs.zerotier.com/faq/macos-uninstall/"
        ),
        (
            "Z2SG5H3HC8", ["net.tunnelblick.tunnelblick"], "Tunnelblick", .inTheApp,
            "https://tunnelblick.net/cUninstall.html"
        ),
        (
            "WQXXM75BYN", ["com.electron.ivpn-ui", "net.ivpn.client"], "IVPN", .onItsDiskImage,
            "https://www.ivpn.net/knowledgebase/macos/macos-how-do-i-completely-uninstall-or-remove-the-ivpn-application/"
        ),
        // AnyConnect 4 and Secure Client up to 5.1.2 share this identifier; the script on the Mac says which it is.
        (
            "DE8Y96K9QP", ["com.cisco.anyconnect.gui"], "Cisco",
            .scriptOnTheMac(
                "/opt/cisco/secureclient/bin/cisco_secure_client_uninstall.sh",
                page: "https://www.cisco.com/c/en/us/support/docs/security/umbrella/224782-uninstall-secure-client-from-macos.html",
                otherwise: "/opt/cisco/anyconnect/bin/vpn_uninstall.sh"
            ),
            "https://www.cisco.com/c/en/us/td/docs/security/vpn_client/anyconnect/anyconnect410/administration/guide/b-anyconnect-admin-guide-4-10/deploy-anyconnect.html"
        ),
        (
            "9PTGMPNXZ2", ["com.symantec.sep.mainapp"], "Symantec", .inTheApp,
            "https://knowledge.broadcom.com/external/article/156148"
        ),
        // Zscaler's guide for deploying with Jamf names the team and `com.zscaler` as the prefix of its apps.
        (
            "PCBCQZJ7S7", ["com.zscaler"], "Zscaler",
            .uninstaller("/Applications/Zscaler/UninstallApplication.app"),
            "https://help.zscaler.com/zscaler-client-connector/uninstalling-zscaler-client-connector"
        ),
        (
            "48ZCSDVL96", ["com.haystacksoftware.arq"], "Arq", .inTheApp,
            "https://www.arqbackup.com/documentation/arq7/English.lproj/troubleshooting.html"
        ),
        // The uninstaller's identifier, from Chromium's `remoting/branding_Chrome`; the host's own is not listed here.
        (
            "EQHXZ8M8AV", ["com.google.chromeremotedesktop.me2me-host-uninstaller"], "Google",
            .itself(removing: "Chrome Remote Desktop Host"),
            "https://support.google.com/chrome/answer/1649523"
        ),
    ]

    /// The maker's uninstaller for `app`, known by the team of its checked signature and by its identifier, both as
    /// the maker documents them. An identifier alone is what a bundle says of itself, and would let any app keep Peel
    /// away from it.
    static func of(
        _ app: InstalledApp,
        isOnTheMac: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> MakersUninstaller? {
        guard let team = app.teamIdentifier, let identifier = app.bundleIdentifier?.lowercased() else { return nil }
        guard let product = known.first(where: { product in
            product.team == team && product.identifiers.contains { identifier == $0 || identifier.hasPrefix($0 + ".") }
        }) else { return nil }
        let chosen: (step: Step, page: String) = switch product.step {
        case .command(let command): (.command(command), product.page)
        case .uninstaller(let path): (.uninstaller(URL(filePath: path, directoryHint: .isDirectory)), product.page)
        case .uninstallerInsideTheApp(let path):
            (.uninstaller(app.url.appending(path: path, directoryHint: .isDirectory)), product.page)
        case .itself: (.uninstaller(app.url), product.page)
        case .inTheApp: (.inTheApp(app.url), product.page)
        case .onItsDiskImage: (.onItsDiskImage, product.page)
        case .scriptOnTheMac(let script, let page, let otherwise):
            isOnTheMac(script) ? (.command("sudo \(script)"), page) : (.command("sudo \(otherwise)"), product.page)
        }
        guard let instructions = URL(string: chosen.page) else { return nil }
        let step = chosen.step
        let removes: String? = if case .itself(let removing) = product.step { removing } else { nil }
        return MakersUninstaller(maker: product.maker, step: step, instructions: instructions, removes: removes)
    }
}
