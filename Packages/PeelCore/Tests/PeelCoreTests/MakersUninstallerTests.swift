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
