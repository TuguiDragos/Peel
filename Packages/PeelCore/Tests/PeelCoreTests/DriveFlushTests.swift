import Foundation
@testable import PeelPrivileged
import Testing

struct DriveFlushTests {
    @Test func flushesAFileThisMacWrote() throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file("written")

        #expect(DriveFlush.file(at: file.path(percentEncoded: false)))
        #expect(!DriveFlush.file(at: directory.url.appending(path: "missing").path(percentEncoded: false)))
    }
}
