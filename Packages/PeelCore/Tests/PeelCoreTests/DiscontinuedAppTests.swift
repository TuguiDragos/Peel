import Foundation
@testable import PeelCore
import Testing

struct DiscontinuedAppTests {
    @Test func knowsAnAppItsMakerAsksPeopleToUninstall() {
        func app(_ identifier: String?) -> InstalledApp {
            InstalledApp(
                url: URL(filePath: "/Applications/Intel Power Gadget/Intel Power Gadget.app", directoryHint: .isDirectory),
                bundleIdentifier: identifier, name: "Intel Power Gadget"
            )
        }

        #expect(DiscontinuedApp.of(app("com.intel.PowerGadget"))?.maker == "Intel")
        #expect(DiscontinuedApp.of(app("com.intel.PowerGadget"))?.advisory.absoluteString.contains("intel-sa-01037") == true)
        #expect(DiscontinuedApp.of(app("org.example.gadget")) == nil)
        #expect(DiscontinuedApp.of(app(nil)) == nil)
    }
}
