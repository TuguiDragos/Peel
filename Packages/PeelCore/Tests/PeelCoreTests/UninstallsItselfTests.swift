import Foundation
@testable import PeelCore
import Testing

struct UninstallsItselfTests {
    private let mullvad = InstalledApp(
        url: URL(filePath: "/Applications/Mullvad VPN.app"), bundleIdentifier: "net.mullvad.vpn", name: "Mullvad VPN"
    )

    @Test func mullvadUninstallsItselfOnceItLeavesTheApplicationsFolder() {
        #expect(UninstallsItself.when(moving: [mullvad.url], among: [mullvad]).map(\.app) == [mullvad])
        #expect(UninstallsItself.when(moving: [mullvad.url], among: [mullvad]).map(\.uninstaller) == [
            "/Applications/Mullvad VPN.app/Contents/Resources/uninstall.sh",
        ])
    }

    @Test func nothingHappensWhileTheAppStaysOrSitsElsewhere() {
        let elsewhere = InstalledApp(
            url: URL(filePath: "/Users/me/Applications/Mullvad VPN.app"), bundleIdentifier: "net.mullvad.vpn",
            name: "Mullvad VPN"
        )
        let another = InstalledApp(
            url: URL(filePath: "/Applications/Mullvad VPN.app"), bundleIdentifier: "org.example.vpn", name: "Mullvad VPN"
        )

        #expect(UninstallsItself.when(moving: [], among: [mullvad]).isEmpty)
        #expect(UninstallsItself.when(moving: [elsewhere.url], among: [elsewhere]).isEmpty)
        #expect(UninstallsItself.when(moving: [another.url], among: [another]).isEmpty)
    }
}
