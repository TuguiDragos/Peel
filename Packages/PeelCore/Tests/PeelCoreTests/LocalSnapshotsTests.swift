import Foundation
@testable import PeelCore
import Testing

struct LocalSnapshotsTests {
    /// The property list `diskutil apfs listSnapshots -plist` prints, in the shape it has on macOS 26.
    @Test func readsWhatDiskutilSaysAboutEachSnapshot() throws {
        let output = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Snapshots</key>
            <array>
                <dict>
                    <key>LimitingContainerShrink</key>
                    <true/>
                    <key>Purgeable</key>
                    <false/>
                    <key>SnapshotName</key>
                    <string>com.apple.os.update-5F71F8535097458C988F984E152FFCD5</string>
                    <key>SnapshotUUID</key>
                    <string>2DF28783-92EA-4CF6-B83E-3F6F19539397</string>
                    <key>SnapshotXID</key>
                    <integer>4361058</integer>
                </dict>
                <dict>
                    <key>Purgeable</key>
                    <true/>
                    <key>SnapshotName</key>
                    <string>com.apple.TimeMachine.2026-09-17-120000.local</string>
                </dict>
                <dict>
                    <key>SnapshotName</key>
                    <string>com.example.snapshot</string>
                </dict>
            </array>
        </dict>
        </plist>
        """

        let snapshots = try #require(LocalSnapshots.parse(Data(output.utf8)))
        #expect(snapshots.count == 3)

        let update = try #require(snapshots.first)
        #expect(update.kind == .systemUpdate)
        #expect(update.isPurgeable == false)
        #expect(update.date == nil)

        let backup = snapshots[1]
        #expect(backup.kind == .timeMachine)
        #expect(backup.isPurgeable == true)
        #expect(backup.date != nil)

        // `diskutil` does not always say whether a snapshot is purgeable, and not saying is not "no".
        #expect(snapshots.last?.isPurgeable == nil)
    }

    @Test func readsTheMomentATimeMachineSnapshotWasTaken() throws {
        let date = try #require(LocalSnapshots.date(in: "com.apple.TimeMachine.2026-09-17-120000.local"))
        let parts = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )

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
        let none = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>Snapshots</key><array/></dict></plist>
        """
        #expect(LocalSnapshots.parse(Data(none.utf8))?.isEmpty == true)
    }

    /// An answer that is not the list `-plist` asks for, or no answer at all, leaves the snapshots unknown: never
    /// read as a disk that keeps none, when they may be what holds its space.
    @Test func anAnswerItCannotReadLeavesTheSnapshotsUnknown() async {
        #expect(LocalSnapshots.parse(Data()) == nil)
        #expect(LocalSnapshots.parse(Data("Unable to find disk".utf8)) == nil)
        #expect(await LocalSnapshots.list(volume: "/Volumes/org.example.missing") == nil)
    }

    /// Lists the snapshots of the machine running the test. Listing reads and changes nothing.
    @Test func readsThisMacWithoutTouchingIt() async throws {
        let snapshots = try #require(await LocalSnapshots.list())
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
