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
}
