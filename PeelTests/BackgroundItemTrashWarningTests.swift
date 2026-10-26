import Foundation
@testable import Peel
@testable import PeelCore
import Testing

struct BackgroundItemTrashWarningTests {
    private func job(installed: Bool, confirmed: Bool = true) -> BackgroundItem {
        var job = BackgroundItem(
            label: "org.example.backup.agent", kind: .agent, source: .userLibrary, plistURL: nil,
            program: "/Applications/Backup.app/Contents/MacOS/agent", runsAtLoad: true, keepsAlive: true,
            ownerBundleIdentifier: "org.example.backup", ownerName: "Backup",
            ownerURL: installed ? URL(filePath: "/Applications/Backup.app", directoryHint: .isDirectory) : nil,
            isOrphan: false, state: .loaded, isDisabled: false
        )
        job.isOwnerConfirmed = confirmed
        return job
    }

    @Test func warnsThatTheAppThatAddedItMayStopWorking() throws {
        let warning = try #require(job(installed: true).trashWarning(ownerName: "Backup"))
        #expect(String(localized: warning).contains("Backup"))
        #expect(job(installed: true, confirmed: false).trashWarning(ownerName: "Backup") == nil)
        #expect(job(installed: false).trashWarning(ownerName: "Backup") == nil)
    }
}
