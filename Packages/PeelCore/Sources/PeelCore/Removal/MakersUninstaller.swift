public import Foundation

/// A security or management agent, a VPN, a backup app, or another app whose maker documents removing it with an
/// uninstaller of its own, or such an uninstaller itself. Moved from its place, what the product keeps in the system
/// and the settings that manage it would stay behind.
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
        /// An uninstaller the maker's page offers to download, which is not on the Mac.
        case fromTheMakersPage
    }

    private enum Documented: Sendable {
        case command(String)
        case uninstaller(String)
        case uninstallerInsideTheApp(String)
        /// The app is the uninstaller, which removes the product named here and then itself.
        case itself(removing: String)
        case inTheApp
        case onItsDiskImage
        case fromTheMakersPage
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
    /// True when the product's own system extension keeps anyone from moving the app while it runs.
    public var isKeptInPlaceByItsSystemExtension = false

    private typealias Product = (team: String, identifiers: [String], maker: String, step: Documented, page: String)

    /// Each product with the signing team and the identifiers its maker's own pages or its signed bundle give, and the
    /// step and page of its maker's uninstall instructions. An identifier names itself and any longer one after a dot.
    private static let known: [Product] = [
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
            "L7897KTAHV", ["org.opensc-project.mac.opensctoken"], "OpenSC", .command("sudo opensc-uninstall"),
            "https://github.com/OpenSC/OpenSC/wiki/macOS-Quick-Start"
        ),
        (
            "CPQQ3AW49Y", ["com.splashtop.splashtop-streamer"], "Splashtop", .onItsDiskImage,
            "https://support-splashtopbusiness.splashtop.com/hc/en-us/articles/216378343-How-to-Uninstall-Splashtop"
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
            "8Z259RPWAC", ["de.beyondco.herd"], "Beyond Code", .command("/Applications/Herd.app/Contents/Resources/uninstall"),
            "https://herd.laravel.com/docs/macos/troubleshooting/uninstalling"
        ),
        (
            "Z6C22PNU8R", ["com.cleverfiles.diskdrill"], "CleverFiles", .inTheApp,
            "https://www.cleverfiles.com/help/how-to-uninstall-disk-drill/"
        ),
        (
            "GVZRY6KDKR", ["com.malwarebytes.mbam.frontend.application"], "Malwarebytes", .inTheApp,
            "https://help.malwarebytes.com/hc/en-us/articles/31589300070683-Uninstall-Malwarebytes-for-Windows-and-Mac"
        ),
        (
            "2Y8XE5CQ94", ["com.kaspersky.kav"], "Kaspersky", .inTheApp,
            "https://support.kaspersky.com/kaspersky-for-mac/27/118671"
        ),
        (
            "48ZCSDVL96", ["com.haystacksoftware.arq"], "Arq", .inTheApp,
            "https://www.arqbackup.com/documentation/arq7/English.lproj/troubleshooting.html"
        ),
        (
            "P8DQRXPVLP", ["com.eset.ecs"], "ESET", .uninstallerInsideTheApp("Contents/Helpers/Uninstaller.app"),
            "https://support.eset.com/en/kb3239-how-do-i-uninstall-eset-cyber-security"
        ),
        (
            "UGHXR79U6M", ["com.crashplan.desktop"], "CrashPlan",
            .uninstaller("/Library/Application Support/CrashPlan/Uninstall.app"),
            "https://support.crashplan.com/hc/en-us/articles/9025086987661-Uninstall-the-CrashPlan-app"
        ),
        // Backblaze's page opens Backblaze Uninstaller from the installer; its package puts the same app here.
        (
            "G4K4BQ7S8J", ["com.backblaze.backblaze"], "Backblaze",
            .uninstaller("/Library/Backblaze.bzpkg/UninstallBackblaze.app"),
            "https://www.backblaze.com/computer-backup/docs/uninstall-backblaze-mac"
        ),
        (
            "L4F2DED5Q7", ["com.bombich.ccc"], "Bombich Software", .inTheApp,
            "https://support.bombich.com/hc/en-us/articles/20686440822551-Uninstalling-CCC"
        ),
        (
            "X4QN7LTP59", ["com.canonical.multipassgui"], "Canonical",
            .command("sudo sh \"/Library/Application Support/com.canonical.multipass/uninstall.sh\""),
            "https://canonical.com/multipass/docs/latest/how-to-guides/install-multipass/"
        ),
        // The copy from Bjango's site; the App Store's copy, `com.bjango.istatmenus-mas`, has an article of its own.
        (
            "Y93TK974AT", ["com.bjango.istatmenus"], "Bjango", .inTheApp,
            "https://bjango.com/help/istatmenus7/install/"
        ),
        (
            "G43BCU2T37", ["org.pqrs.karabiner-elements.settings"], "pqrs.org", .inTheApp,
            "https://karabiner-elements.pqrs.org/docs/manual/operation/uninstall/"
        ),
        // Wacom's driver installs Wacom Tablet Utility beside its other apps, and the utility is what removes it.
        (
            "EG27766DY7", ["com.wacom.removewacomtablet"], "Wacom", .itself(removing: "Wacom Tablet"),
            "https://support.wacom.com/hc/en-us/articles/1500006264541-How-do-I-uninstall-manually-and-re-install-the-Wacom-driver-on-macOS-for-a-Pen-Tablet-Pen-Display-or-Pen-Computer"
        ),
        (
            "EG27766DY7", ["com.wacom.wacomcenter", "com.wacom.wacom-display-settings"], "Wacom",
            .uninstaller("/Applications/Wacom Tablet.localized/Wacom Tablet Utility.app"),
            "https://support.wacom.com/hc/en-us/articles/1500006264541-How-do-I-uninstall-manually-and-re-install-the-Wacom-driver-on-macOS-for-a-Pen-Tablet-Pen-Display-or-Pen-Computer"
        ),
        (
            "M683GB7CPW", ["com.box.desktop"], "Box", .fromTheMakersPage,
            "https://support.box.com/hc/en-us/articles/360044196293-Uninstalling-Box-Drive"
        ),
        (
            "DE8Y96K9QP", ["cisco-systems.spark"], "Cisco", .fromTheMakersPage,
            "https://help.webex.com/en-us/article/136hu4/Uninstall-Webex-App-on-macOS"
        ),
        (
            "PKV8ZPD836", ["org.gpgtools.gpgkeychain"], "GPGTools", .fromTheMakersPage,
            "https://gpgtools.tenderapp.com/kb/faq/uninstall-gpg-suite"
        ),
        // Datadog's page pipes a script it serves into the shell; Peel gives the page, never a command that runs
        // whatever a server sends.
        (
            "JKFCB4CN7C", ["com.datadoghq.agent"], "Datadog", .fromTheMakersPage,
            "https://docs.datadoghq.com/agent/supported_platforms/osx/#uninstall-the-agent"
        ),
        // The uninstaller's identifier, from Chromium's `remoting/branding_Chrome`; the host's own is not listed here.
        (
            "EQHXZ8M8AV", ["com.google.chromeremotedesktop.me2me-host-uninstaller"], "Google",
            .itself(removing: "Chrome Remote Desktop Host"),
            "https://support.google.com/chrome/answer/1649523"
        ),
        (
            "6H4HRTU5E3", ["com.avast.aafm"], "Avast", .uninstaller("/Applications/com.avast.av.uninstaller.app"),
            "https://support.avast.com/en-us/article/uninstall-mac-security/"
        ),
        (
            "6H4HRTU5E3", ["com.avast.av.uninstaller"], "Avast", .itself(removing: "Avast Security"),
            "https://support.avast.com/en-us/article/uninstall-mac-security/"
        ),
        (
            "XSJ59WMJBM", ["com.avg.antivirus"], "AVG", .uninstaller("/Applications/com.avg.av.uninstaller.app"),
            "https://support.avg.com/SupportArticleView?l=en&urlName=uninstall-avg-antivirus"
        ),
        (
            "XSJ59WMJBM", ["com.avg.av.uninstaller"], "AVG", .itself(removing: "AVG AntiVirus"),
            "https://support.avg.com/SupportArticleView?l=en&urlName=uninstall-avg-antivirus"
        ),
        (
            "E8P47U2H32", ["com.trendmicro.afmagent", "com.trendmicro.itis.supporttool"], "Trend Micro",
            .uninstaller("/Applications/TrendMicro.localized/UninstallerLauncher.app"),
            "https://helpcenter.trendlife.com/en-us/article/tmka-14475/"
        ),
        (
            "E8P47U2H32", ["com.trendmicro.itis.uninstallerlauncher"], "Trend Micro",
            .itself(removing: "Trend Micro Antivirus"),
            "https://helpcenter.trendlife.com/en-us/article/tmka-14475/"
        ),
        // Tuxera's page prefers its button in System Settings, which on macOS 27 deleted Tuxera Disk Manager alone and
        // left the file system in place, so the step is the script the same pages give.
        (
            "PPNVCC9Z68", ["com.tuxera.tuxeradiskmanager"], "Tuxera",
            .command("sudo /Library/Filesystems/tuxera_ntfs.fs/Contents/Resources/Support/uninstall-package.sh"),
            "https://macsupport.tuxera.com/hc/en-gb/articles/360021236379-How-to-uninstall-NTFS-for-Mac-using-the-provided-command-line-script"
        ),
        (
            "PR7PXC66S5", ["com.bearisdriving.bgm.app"], "Kyle Neideck",
            .command("bash \"/Applications/Background Music.app/Contents/Resources/uninstall.sh\""),
            "https://github.com/kyleneideck/BackgroundMusic#uninstall"
        ),
    ]

    /// Each product whose own system extension keeps anyone from moving the app while it runs, an administrator
    /// included, as its maker says. It is left to its maker's uninstaller only while macOS has that extension.
    private static let keptInPlaceByTheirSystemExtensions: [Product] = [
        // SAP's Managing Privileges page: the extension protects the app against uninstallation.
        (
            "7R5ZEU67FQ", ["corp.sap.privileges"], "SAP", .fromTheMakersPage,
            "https://github.com/SAP/macOS-enterprise-privileges/wiki/Uninstallation"
        ),
    ]

    /// The maker's uninstaller for `app`, known by the team of its checked signature and by its identifier, both as
    /// the maker documents them. An identifier alone is what a bundle says of itself, and would let any app keep Peel
    /// away from it.
    static func of(
        _ app: InstalledApp,
        isOnTheMac: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> MakersUninstaller? {
        uninstaller(of: app, among: known, isOnTheMac: isOnTheMac)
    }

    /// The maker's uninstaller for `app` when its own system extension keeps it in place, asked only while macOS has
    /// that extension installed.
    static func keptInPlace(_ app: InstalledApp) -> MakersUninstaller? {
        var uninstaller = uninstaller(of: app, among: keptInPlaceByTheirSystemExtensions)
        uninstaller?.isKeptInPlaceByItsSystemExtension = true
        return uninstaller
    }

    private static func uninstaller(
        of app: InstalledApp,
        among products: [Product],
        isOnTheMac: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> MakersUninstaller? {
        guard let team = app.teamIdentifier, let identifier = app.bundleIdentifier?.lowercased() else { return nil }
        guard let product = products.first(where: { product in
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
        case .fromTheMakersPage: (.fromTheMakersPage, product.page)
        case .scriptOnTheMac(let script, let page, let otherwise):
            isOnTheMac(script) ? (.command("sudo \(script)"), page) : (.command("sudo \(otherwise)"), product.page)
        }
        guard let instructions = URL(string: chosen.page) else { return nil }
        let step = chosen.step
        let removes: String? = if case .itself(let removing) = product.step { removing } else { nil }
        return MakersUninstaller(maker: product.maker, step: step, instructions: instructions, removes: removes)
    }
}
