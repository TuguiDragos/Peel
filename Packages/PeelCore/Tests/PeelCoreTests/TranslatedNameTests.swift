import Foundation
@testable import PeelCore
import Testing

/// The name Finder shows for an app follows the reader's language when the app translates it (`Latest` is
/// `Siste` in Norwegian), while the bundle on disk keeps its own name. Whatever matches an app by name answers
/// to both, so the app and `peel`, which always reads the English name, reach the same answer.
@Suite struct TranslatedNameTests {
    let latest = InstalledApp(url: URL(filePath: "/Applications/Latest.app"), bundleIdentifier: "com.max-langer.Latest", name: "Siste")

    @Test func namesHoldTheTranslationAndTheFileName() {
        #expect(latest.names == ["Siste", "Latest"])
        let plain = InstalledApp(url: URL(filePath: "/Applications/Latest.app"), bundleIdentifier: "com.max-langer.Latest", name: "Latest")
        #expect(plain.names == ["Latest"])
    }

    @Test func theCaskIsStillAskedForByTheFileName() {
        #expect(CaskEvidence.tokens(for: latest).contains("latest"))
    }

    @Test func theInstallerIsStillKnownAsTheApps() {
        #expect(
            Installers.installedApp(for: URL(filePath: "/Users/me/Downloads/Latest-2.1.dmg"), in: [latest])?
                .bundleIdentifier == latest.bundleIdentifier
        )
    }

    @Test func theUninstallerBesideItIsStillItsOwn() {
        #expect(VendorRemoval.isUninstallerName("Uninstall Latest.app", app: latest, isInsideTheBundle: false))
    }
}
