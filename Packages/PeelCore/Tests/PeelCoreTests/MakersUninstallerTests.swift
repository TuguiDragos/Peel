import Foundation
@testable import PeelCore
import Testing

struct MakersUninstallerTests {
    private func agent(_ identifier: String, team: String?, at path: String = "/Applications/Agent.app") -> InstalledApp {
        InstalledApp(
            url: URL(filePath: path, directoryHint: .isDirectory), bundleIdentifier: identifier, name: "Agent",
            teamIdentifier: team
        )
    }

    @Test func knowsAnAgentByTheTeamAndTheIdentifierItsMakerDocuments() {
        let globalProtect = agent("com.paloaltonetworks.GlobalProtect.client", team: "PXPZ95SK77")
        #expect(
            MakersUninstaller.of(globalProtect)?.step
                == .command("sudo /Applications/GlobalProtect.app/Contents/Resources/uninstall_gp.sh")
        )
        #expect(MakersUninstaller.of(agent("com.paloaltonetworks.cortex.agent", team: "PXPZ95SK77")) != nil)
        #expect(MakersUninstaller.of(agent("com.cisco.secureclient.gui", team: "DE8Y96K9QP"))?.maker == "Cisco")
        #expect(MakersUninstaller.of(agent("com.microsoft.wdav", team: "UBF8T346G9"))?.maker == "Microsoft")
        #expect(MakersUninstaller.of(agent("com.netskope.client.Netskope-Client", team: "24W52P9M7W")) != nil)
        #expect(MakersUninstaller.of(agent("com.fortinet.FortiClient", team: "AH4XFXJ7DK")) != nil)
        #expect(
            MakersUninstaller.of(agent("com.bitdefender.EndpointSecurityforMac", team: "GUNFMW623Y"))?.step
                == .uninstaller(URL(filePath: "/Applications/Bitdefender/EndpointSecurityforMacUninstaller.app", directoryHint: .isDirectory))
        )
        #expect(
            MakersUninstaller.of(agent("com.sophos.endpoint.uiserver", team: "2H5GFH3774"))?.step
                == .uninstaller(URL(filePath: "/Applications/Sophos/Remove Sophos Endpoint.app", directoryHint: .isDirectory))
        )
        let eset = agent("com.eset.ees.g2", team: "P8DQRXPVLP", at: "/Applications/ESET Endpoint Security.app")
        #expect(
            MakersUninstaller.of(eset)?.step == .uninstaller(
                URL(
                    filePath: "/Applications/ESET Endpoint Security.app/Contents/Helpers/Uninstaller.app",
                    directoryHint: .isDirectory
                )
            )
        )
    }

    @Test func knowsAVPNWhoseMakerDocumentsItsOwnUninstall() {
        let express = agent("com.express.vpn", team: "TC292Y5427", at: "/Applications/ExpressVPN.app")
        let tunnelblick = agent("net.tunnelblick.tunnelblick", team: "Z2SG5H3HC8", at: "/Applications/Tunnelblick.app")

        #expect(MakersUninstaller.of(express)?.step == .inTheApp(express.url))
        #expect(MakersUninstaller.of(agent("com.privateinternetaccess.vpn", team: "5357M5NW9W"))?.step == .inTheApp(
            URL(filePath: "/Applications/Agent.app", directoryHint: .isDirectory)
        ))
        #expect(MakersUninstaller.of(tunnelblick)?.maker == "Tunnelblick")
        #expect(
            MakersUninstaller.of(agent("com.cloudflare.1dot1dot1dot1.macos", team: "68WVV388M8"))?.step
                == .command("\"/Applications/Cloudflare WARP.app/Contents/Resources/uninstall.sh\"")
        )
        #expect(
            MakersUninstaller.of(agent("com.zerotier.ZeroTier-UI", team: "8ZD9JUCZ4V"))?.step
                == .command("sudo \"/Library/Application Support/ZeroTier/One/uninstall.sh\"")
        )
        #expect(MakersUninstaller.of(agent("com.zerotier.ZeroTier-One", team: "8ZD9JUCZ4V"))?.maker == "ZeroTier")
        #expect(MakersUninstaller.of(agent("com.electron.ivpn-ui", team: "WQXXM75BYN"))?.step == .onItsDiskImage)
        #expect(MakersUninstaller.of(agent("net.ivpn.client.IVPN", team: "WQXXM75BYN"))?.maker == "IVPN")
        #expect(MakersUninstaller.of(agent("com.electron.ivpn-ui", team: "ABCDE12345")) == nil)
    }

    @Test func knowsAnAgentAndABackupAppWhoseMakersDocumentTheirOwnUninstall() {
        let arq = agent("com.haystacksoftware.Arq", team: "48ZCSDVL96", at: "/Applications/Arq.app")

        #expect(
            MakersUninstaller.of(agent("com.zscaler.zscaler", team: "PCBCQZJ7S7"))?.step
                == .uninstaller(URL(filePath: "/Applications/Zscaler/UninstallApplication.app", directoryHint: .isDirectory))
        )
        #expect(MakersUninstaller.of(agent("com.zscaler.tray", team: "PCBCQZJ7S7"))?.maker == "Zscaler")
        #expect(MakersUninstaller.of(arq)?.step == .inTheApp(arq.url))
        #expect(MakersUninstaller.of(agent("com.zscaler.zscaler", team: "ABCDE12345")) == nil)
    }

    @Test func knowsALocalServerStackWhoseMakerSaysToUseItsOwnUninstall() {
        let herd = agent("de.beyondco.herd", team: "8Z259RPWAC", at: "/Applications/Herd.app")

        #expect(MakersUninstaller.of(herd)?.step == .command("/Applications/Herd.app/Contents/Resources/uninstall"))
        #expect(MakersUninstaller.of(herd)?.maker == "Beyond Code")
        #expect(MakersUninstaller.of(agent("de.beyondco.herd", team: "ABCDE12345")) == nil)
    }

    @Test func knowsADataRecoveryAppAndAMalwareScannerWhoseMakersDocumentTheirOwnUninstall() {
        let diskDrill = agent("com.cleverfiles.DiskDrill", team: "Z6C22PNU8R", at: "/Applications/Disk Drill.app")
        let malwarebytes = agent(
            "com.malwarebytes.mbam.frontend.application", team: "GVZRY6KDKR", at: "/Applications/Malwarebytes.app"
        )

        #expect(MakersUninstaller.of(diskDrill)?.step == .inTheApp(diskDrill.url))
        #expect(MakersUninstaller.of(diskDrill)?.maker == "CleverFiles")
        #expect(MakersUninstaller.of(malwarebytes)?.step == .inTheApp(malwarebytes.url))
        #expect(MakersUninstaller.of(malwarebytes)?.maker == "Malwarebytes")
        #expect(MakersUninstaller.of(agent("com.cleverfiles.DiskDrill", team: "ABCDE12345")) == nil)
    }

    @Test func knowsKasperskyByTheTeamAndIdentifierItsSignatureNames() {
        let kaspersky = agent(
            "com.kaspersky.kav", team: "2Y8XE5CQ94", at: "/Applications/Kaspersky Anti-Virus For Mac.app"
        )

        #expect(MakersUninstaller.of(kaspersky)?.step == .inTheApp(kaspersky.url))
        #expect(MakersUninstaller.of(kaspersky)?.maker == "Kaspersky")
        #expect(MakersUninstaller.of(agent("com.kaspersky.kav", team: "ABCDE12345")) == nil)
    }

    @Test func knowsTheAppsWhoseMakersPagesAndSignedInstallersWereReadOnTheMac() {
        let karabiner = agent(
            "org.pqrs.Karabiner-Elements.Settings", team: "G43BCU2T37", at: "/Applications/Karabiner-Elements.app"
        )
        let eset = agent("com.eset.ecs.g2", team: "P8DQRXPVLP", at: "/Applications/ESET Cyber Security.app")
        let ccc = agent("com.bombich.ccc", team: "L4F2DED5Q7", at: "/Applications/Carbon Copy Cloner.app")
        let utility = agent(
            "com.wacom.RemoveWacomTablet", team: "EG27766DY7",
            at: "/Applications/Wacom Tablet.localized/Wacom Tablet Utility.app"
        )

        #expect(MakersUninstaller.of(karabiner)?.step == .inTheApp(karabiner.url))
        #expect(MakersUninstaller.of(agent("org.pqrs.Karabiner-EventViewer", team: "G43BCU2T37")) == nil)
        #expect(
            MakersUninstaller.of(agent("com.canonical.multipassGui", team: "X4QN7LTP59"))?.step
                == .command("sudo sh \"/Library/Application Support/com.canonical.multipass/uninstall.sh\"")
        )
        #expect(MakersUninstaller.of(eset)?.step == .uninstaller(
            URL(filePath: "/Applications/ESET Cyber Security.app/Contents/Helpers/Uninstaller.app", directoryHint: .isDirectory)
        ))
        #expect(
            MakersUninstaller.of(agent("com.crashplan.desktop", team: "UGHXR79U6M"))?.step
                == .uninstaller(URL(filePath: "/Library/Application Support/CrashPlan/Uninstall.app", directoryHint: .isDirectory))
        )
        #expect(MakersUninstaller.of(ccc)?.step == .inTheApp(ccc.url))
        #expect(MakersUninstaller.of(ccc)?.maker == "Bombich Software")
        #expect(MakersUninstaller.of(utility)?.step == .uninstaller(utility.url))
        #expect(MakersUninstaller.of(utility)?.removes == "Wacom Tablet")
        #expect(
            MakersUninstaller.of(agent("com.wacom.WacomCenter", team: "EG27766DY7"))?.step
                == .uninstaller(URL(filePath: "/Applications/Wacom Tablet.localized/Wacom Tablet Utility.app", directoryHint: .isDirectory))
        )
        #expect(MakersUninstaller.of(agent("com.wacom.Wacom-Display-Settings", team: "EG27766DY7"))?.maker == "Wacom")
        #expect(MakersUninstaller.of(agent("com.canonical.multipassGui", team: "ABCDE12345")) == nil)
        #expect(
            MakersUninstaller.of(agent("com.backblaze.Backblaze", team: "G4K4BQ7S8J"))?.step
                == .uninstaller(URL(filePath: "/Library/Backblaze.bzpkg/UninstallBackblaze.app", directoryHint: .isDirectory))
        )
        let iStat = agent("com.bjango.istatmenus", team: "Y93TK974AT", at: "/Applications/iStat Menus.app")
        #expect(MakersUninstaller.of(iStat)?.step == .inTheApp(iStat.url))
        #expect(MakersUninstaller.of(agent("com.bjango.istatmenus-mas", team: "Y93TK974AT")) == nil)
        #expect(
            MakersUninstaller.of(agent("com.splashtop.Splashtop-Streamer", team: "CPQQ3AW49Y"))?.step == .onItsDiskImage
        )
        #expect(
            MakersUninstaller.of(agent("org.opensc-project.mac.opensctoken.OpenSCTokenApp", team: "L7897KTAHV"))?.step
                == .command("sudo opensc-uninstall")
        )
    }

    @Test func knowsTheAppsWhoseUninstallerTheirMakersPageOffersToDownload() {
        #expect(MakersUninstaller.of(agent("com.box.desktop", team: "M683GB7CPW"))?.step == .fromTheMakersPage)
        #expect(MakersUninstaller.of(agent("com.box.desktop.helper", team: "M683GB7CPW"))?.maker == "Box")
        let webex = MakersUninstaller.of(agent("Cisco-Systems.Spark", team: "DE8Y96K9QP"))
        #expect(webex?.step == .fromTheMakersPage)
        #expect(webex?.maker == "Cisco")
        #expect(MakersUninstaller.of(agent("Cisco-Systems.Spark", team: "ABCDE12345")) == nil)
        #expect(MakersUninstaller.of(agent("org.gpgtools.gpgkeychain", team: "PKV8ZPD836"))?.step == .fromTheMakersPage)
        #expect(MakersUninstaller.of(agent("com.datadoghq.agent", team: "JKFCB4CN7C"))?.step == .fromTheMakersPage)
    }

    @Test func givesTheUninstallScriptOfTheCiscoClientThatIsOnTheMac() {
        let anyConnect = agent("com.cisco.anyconnect.gui", team: "DE8Y96K9QP")
        let secureClient = "/opt/cisco/secureclient/bin/cisco_secure_client_uninstall.sh"

        let found = MakersUninstaller.of(anyConnect) { $0 == secureClient }
        #expect(found?.step == .command("sudo \(secureClient)"))
        #expect(found?.instructions.absoluteString.contains("224782") == true)
        let older = MakersUninstaller.of(anyConnect) { _ in false }
        #expect(older?.step == .command("sudo /opt/cisco/anyconnect/bin/vpn_uninstall.sh"))
        #expect(older?.instructions.absoluteString.contains("anyconnect410") == true)
    }

    @Test func knowsSymantecEndpointProtectionByTheTeamItsSignatureNames() {
        let symantec = agent("com.symantec.sep.mainapp", team: "9PTGMPNXZ2", at: "/Applications/Symantec Solutions/Symantec Endpoint Protection.app")

        #expect(MakersUninstaller.of(symantec)?.step == .inTheApp(symantec.url))
        #expect(MakersUninstaller.of(agent("com.symantec.sep.mainapp", team: "ABCDE12345")) == nil)
    }

    @Test func knowsAnUninstallerItsMakerDocumentsOpeningToRemoveAProduct() {
        let path = "/Applications/Chrome Remote Desktop Host Uninstaller.app"
        let uninstaller = agent("com.google.chromeremotedesktop.me2me-host-uninstaller", team: "EQHXZ8M8AV", at: path)

        let found = MakersUninstaller.of(uninstaller)
        #expect(found?.maker == "Google")
        #expect(found?.removes == "Chrome Remote Desktop Host")
        #expect(found?.step == .uninstaller(URL(filePath: path, directoryHint: .isDirectory)))
        #expect(MakersUninstaller.of(agent("com.google.chromeremotedesktop.me2me-host-uninstaller", team: "ABCDE12345")) == nil)
        #expect(MakersUninstaller.of(agent("com.google.chromeremotedesktop.me2me-host", team: "EQHXZ8M8AV")) == nil)
        #expect(MakersUninstaller.of(agent("com.google.Chrome", team: "EQHXZ8M8AV")) == nil)
    }

    /// An identifier is what a bundle says of itself: alone, it would let any app keep Peel away. The team comes
    /// from the checked signature, and a maker's other apps share it.
    @Test func neitherTheIdentifierNorTheTeamIsEnoughAlone() {
        #expect(MakersUninstaller.of(agent("com.paloaltonetworks.GlobalProtect.client", team: nil)) == nil)
        #expect(MakersUninstaller.of(agent("com.paloaltonetworks.GlobalProtect.client", team: "ABCDE12345")) == nil)
        #expect(MakersUninstaller.of(agent("com.microsoft.Word", team: "UBF8T346G9")) == nil)
        #expect(MakersUninstaller.of(agent("com.microsoft.wdavx", team: "UBF8T346G9")) == nil)
        #expect(MakersUninstaller.of(agent("com.cisco.webexmeetingsapp", team: "DE8Y96K9QP")) == nil)
    }
}
