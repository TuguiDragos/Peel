import Foundation
@testable import Peel
@testable import PeelCore
import Testing

struct MakersUninstallerNoticeTests {
    @Test func everyStepWithNoButtonSaysWhereTheUninstallerIs() throws {
        let page = try #require(URL(string: "https://example.org/uninstall"))
        func uninstaller(_ step: MakersUninstaller.Step) -> MakersUninstaller {
            MakersUninstaller(maker: "Example", step: step, instructions: page, removes: nil)
        }

        for step in [MakersUninstaller.Step.onItsDiskImage, .fromTheMakersPage, .notOnTheMac, .notTrusted] {
            #expect(MakersUninstallerNotice.whereItIs(uninstaller(step), app: "Example Agent") != nil, "\(step)")
        }
        #expect(MakersUninstallerNotice.whereItIs(uninstaller(.command("sudo /opt/example/uninstall")), app: "") == nil)
    }
}
