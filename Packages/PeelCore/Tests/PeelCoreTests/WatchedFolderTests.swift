import Foundation
@testable import PeelCore
import Testing

struct WatchedFolderTests {
    @Test func opensAFolderForItsChangesWithWhatItHolds() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Trash/one")
        try directory.directory("Trash/two.app")

        guard case .opened(let descriptor, let names) = await WatchedFolder.open(directory.url.appending(path: "Trash"))
        else {
            Issue.record("the folder did not open")
            return
        }
        defer { close(descriptor) }

        #expect(names == ["one", "two.app"])
        #expect(fcntl(descriptor, F_GETFD) != -1)
    }

    @Test func tellsAFolderThatIsNotThereFromOneItCannotList() async throws {
        let directory = try TemporaryDirectory()
        let closed = try directory.directory("Closed")
        try directory.setPermissions(0, of: "Closed")
        defer { try? directory.setPermissions(0o755, of: "Closed") }

        guard case .missing = await WatchedFolder.open(directory.url.appending(path: "Missing")) else {
            Issue.record("a missing folder read as something else")
            return
        }
        guard case .refused(.permissions?) = await WatchedFolder.open(closed) else {
            Issue.record("a folder its permissions close read as something else")
            return
        }
        #expect(await WatchedFolder.openToWait(in: directory.url.appending(path: "Missing")) == nil)
    }
}
