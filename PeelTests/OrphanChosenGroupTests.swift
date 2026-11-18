import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct OrphanChosenGroupTests {
    @Test func aSelectionThatNamesNoPageFollowsTheGroupItsIdentifierFallsIn() {
        let job = OrphanItem(
            url: URL(filePath: "/Library/LaunchDaemons/org.example.sync.daemon.plist"), kind: .launchDaemons, size: 10,
            modificationDate: nil, requiresPrivileges: true
        )
        let scan = OrphanScan(groups: [OrphanGroup(identifier: "org.example", items: [job])], unreadableLocations: [])

        #expect(OrphanLibrary.settled(.group("org.example.sync"), in: scan) == .group("org.example"))
        #expect(OrphanLibrary.settled(.group("Org.Example"), in: scan) == .group("org.example"))
        #expect(OrphanLibrary.settled(.group("org.elsewhere"), in: scan) == nil)
        #expect(OrphanLibrary.settled(.forAnAdministrator, in: scan) == nil)
    }
}
