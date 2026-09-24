import Foundation
@testable import PeelCore
import Testing

struct LocalSnapshotsTests {
    @Test func readsWhatDiskutilSaysAboutEachSnapshot() throws {
        let output = """
        Snapshot for disk3s3s1 (2 found)
        |
        +-- 2DF28783-92EA-4CF6-B83E-3F6F19539397
            Name:        com.apple.os.update-5F71F8535097458C988F984E152FFCD5
            XID:         4361058
            Purgeable:   No
            NOTE:        This snapshot limits the minimum size of APFS Container disk3
        |
        +-- A1B2C3D4-0000-0000-0000-000000000000
            Name:        com.apple.TimeMachine.2026-09-17-120000.local
            XID:         4361059
            Purgeable:   Yes
        """

        let snapshots = LocalSnapshots.parse(output)
        #expect(snapshots.count == 2)

        let update = try #require(snapshots.first)
        #expect(update.kind == .systemUpdate)
        #expect(update.isPurgeable == false)
        #expect(update.date == nil)

        let backup = snapshots.last
        #expect(backup?.kind == .timeMachine)
        #expect(backup?.isPurgeable == true)
        #expect(backup?.date != nil)
    }

    @Test func readsTheMomentATimeMachineSnapshotWasTaken() throws {
        let date = try #require(LocalSnapshots.date(in: "com.apple.TimeMachine.2026-09-17-120000.local"))
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        #expect(parts.year == 2026)
        #expect(parts.month == 9)
        #expect(parts.day == 17)
        #expect(parts.hour == 12)
        #expect(parts.minute == 0)
        #expect(parts.second == 0)

        #expect(LocalSnapshots.date(in: "com.apple.os.update-5F71") == nil)
        #expect(LocalSnapshots.date(in: "com.apple.TimeMachine.nonsense.local") == nil)
    }

    @Test func tellsTheTwoKindsApart() {
        #expect(LocalSnapshots.kind(of: "com.apple.TimeMachine.2026-09-17-120000.local") == .timeMachine)
        #expect(LocalSnapshots.kind(of: "com.apple.os.update-ABC") == .systemUpdate)
        #expect(LocalSnapshots.kind(of: "something.else") == .other)
    }

    @Test func answersWithoutComplainingWhenThereAreNone() {
        #expect(LocalSnapshots.parse("Snapshot for disk3s3s1 (0 found)").isEmpty)
        #expect(LocalSnapshots.parse("").isEmpty)
    }

    /// Lists the snapshots of the machine running the test. Listing reads and changes nothing.
    @Test func readsThisMacWithoutTouchingIt() async {
        let snapshots = await LocalSnapshots.list()
        #expect(Set(snapshots.map(\.id)).count == snapshots.count)
    }

    /// `/` is the sealed system volume: listing its snapshots finds macOS's update snapshot rather than the
    /// user's, and `tmutil deletelocalsnapshots` cannot remove that one.
    @Test func readsTheDataVolumeNotTheSealedSystemOne() async {
        #expect(LocalSnapshots.volume == "/System/Volumes/Data")
        #expect(LocalSnapshots.deleteCommand.hasSuffix(LocalSnapshots.volume))

        #expect(LocalSnapshots.deleteCommand.contains("tmutil"))
    }
}
