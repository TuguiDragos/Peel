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
