import Foundation
@testable import Peel
@testable import PeelCore
import Testing

struct MakersUninstallerNoticeTests {
    private let page = URL(string: "https://example.org/uninstall")!

    private func uninstaller(_ step: MakersUninstaller.Step, removes: String? = nil) -> MakersUninstaller {
        MakersUninstaller(maker: "Example", step: step, instructions: page, removes: removes)
    }

    @Test func theTitleSaysWhatToUseWithoutTheMakersName() {
        let agent = uninstaller(.command("sudo /opt/example/uninstall"))
        let itself = uninstaller(.uninstaller(URL(filePath: "/Applications/Example Uninstaller.app")), removes: "Example")

        #expect(MakersUninstallerNotice.title(of: agent, isForWhatIsLeft: false).key == "Use its own uninstaller")
        #expect(MakersUninstallerNotice.title(of: itself, isForWhatIsLeft: false).key == "This app is an uninstaller")
        #expect(MakersUninstallerNotice.title(of: agent, isForWhatIsLeft: true).key == "Use the uninstaller from its maker")
    }

    @Test func everyStepSaysWhatToDoExceptAnUninstallerThatIsTheApp() {
        let steps: [MakersUninstaller.Step] = [
            .command("sudo /opt/example/uninstall"), .uninstaller(URL(filePath: "/Applications/Uninstall.app")),
            .inTheApp(URL(filePath: "/Applications/Example.app")), .onItsDiskImage, .fromTheMakersPage, .notOnTheMac,
            .notTrusted,
        ]
        for step in steps {
            #expect(MakersUninstallerNotice.step(of: uninstaller(step), isForWhatIsLeft: false) != nil, "\(step)")
        }
        let leftover = MakersUninstallerNotice.step(
            of: uninstaller(.uninstaller(URL(filePath: "/Library/Example/Uninstall.app"))), isForWhatIsLeft: true
        )
        #expect(leftover?.key == "Its maker offers an uninstaller that removes what the app left.")
        let itself = uninstaller(.uninstaller(URL(filePath: "/Applications/Uninstall.app")), removes: "Example")
        #expect(MakersUninstallerNotice.step(of: itself, isForWhatIsLeft: false) == nil)
    }

    @Test func everyStepHasTheButtonsThatTakeIt() {
        let script = "sudo /opt/example/uninstall"
        let tool = URL(filePath: "/Applications/Uninstall Example.app")
        let app = URL(filePath: "/Applications/Example.app")

        let command = MakersUninstallerNotice.actions(for: uninstaller(.command(script)))
        #expect(command == [.copyCommand(script), .openTerminal])
        #expect(MakersUninstallerNotice.actions(for: uninstaller(.uninstaller(tool))) == [.openUninstaller(tool)])
        #expect(MakersUninstallerNotice.actions(for: uninstaller(.inTheApp(app))) == [.openApp(app)])
        for step in [MakersUninstaller.Step.onItsDiskImage, .fromTheMakersPage, .notOnTheMac, .notTrusted] {
            #expect(MakersUninstallerNotice.actions(for: uninstaller(step)) == [.openWebsite(page)], "\(step)")
        }
    }
}
