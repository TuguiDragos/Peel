import Foundation
import Testing

struct DiskImageToolTests {
    @Test func aDiskThatCantBeMadeSaysWhatHdiutilAnswered() throws {
        let directory = try TemporaryDirectory()

        let error = #expect(throws: (any Error).self) {
            try ScratchVolume(fileSystem: "No Such File System", mountedAt: directory.url.appending(path: "Disk"))
        }

        #expect(String(describing: error).contains("hdiutil: create failed"))
    }

    @Test func aDiskWhoseProcessEndedIsDetachedByTheNextAndNoOtherIs() throws {
        let directory = try TemporaryDirectory()
        let left = try ScratchVolume(fileSystem: "APFS", mountedAt: directory.url.appending(path: "Left"))
        let kept = try ScratchVolume(fileSystem: "APFS", mountedAt: directory.url.appending(path: "Kept"))
        try left.leaveAsIfItsProcessEnded()

        ScratchVolume.detachTheLeftovers()

        #expect(!left.isAttached)
        #expect(kept.isAttached)
    }

    @Test func aRecordOfADiskThatLeftIsNotTakenForALeftover() {
        let gone: [String: Any] = [
            "image-path": "/tmp/gone/disk.dmg",
            "system-entities": [["dev-entry": "/dev/disk12"], ["dev-entry": "/dev/disk12s1"]],
        ]
        let left: [String: Any] = [
            "image-path": "/tmp/left/disk.dmg",
            "system-entities": [["dev-entry": "/dev/disk14"], ["dev-entry": "/dev/disk15s1", "mount-point": "/tmp/left/Disk"]],
        ]
        let alive: [String: Any] = [
            "image-path": "/tmp/alive/disk.dmg",
            "system-entities": [["dev-entry": "/dev/disk16s1", "mount-point": "/tmp/alive/Disk"]],
        ]

        let places = ScratchVolume.mountPointsOfLeftovers(
            among: [gone, left, alive],
            owner: { $0.path.contains("/alive/") ? "42 1.1" : "999999 0.0" },
            identity: { $0 == 42 ? "42 1.1" : nil }
        )

        #expect(places == ["/tmp/left/Disk"])
    }

    @Test func aDiskIsTakenAwayByACommandMacOSDoesNotCallDeprecated() throws {
        let directory = try TemporaryDirectory()
        let disk = try ScratchVolume(fileSystem: "APFS", mountedAt: directory.url.appending(path: "Disk"))

        let said = try disk.eject()

        #expect(!said.localizedCaseInsensitiveContains("deprecated"), "\(said)")
        #expect(!disk.isAttached)
    }

    @Test func disksMadeTogetherHaveVolumesOfTheirOwn() async throws {
        let directory = try TemporaryDirectory()
        let places = ["First", "Second"].map { directory.url.appending(path: $0, directoryHint: .isDirectory) }

        let volumes = try await withThrowingTaskGroup(of: String?.self) { group in
            for place in places {
                group.addTask {
                    let disk = try ScratchVolume(fileSystem: "ExFAT", mountedAt: place)
                    return try withExtendedLifetime(disk) {
                        try disk.url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
                    }
                }
            }
            return try await group.reduce(into: [String?]()) { $0.append($1) }
        }

        #expect(volumes.count == 2 && !volumes.contains(nil) && Set(volumes).count == 2, "\(volumes)")
    }
}
