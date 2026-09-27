import Darwin
import Foundation
@testable import PeelCore
import Testing

struct FileLockTests {
    private func isLocked(_ url: URL) -> Bool {
        let descriptor = open(url.path(percentEncoded: false) + ".lock", O_RDWR | O_CLOEXEC)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return errno == EWOULDBLOCK }
        flock(descriptor, LOCK_UN)
        return false
    }

    @Test func holdsTheLockForTheChangeAndNoLonger() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appending(path: "Peel/exclusions.json")

        let heldDuringTheChange = FileLock.whileHeld(beside: url) { isLocked(url) }

        #expect(heldDuringTheChange)
        #expect(!isLocked(url))
        #expect(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path(percentEncoded: false)))
    }

    @Test(.permissionsHold) func runsTheChangeWhenNoLockCanBeMade() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("Locked")
        try directory.setPermissions(0o555, of: "Locked")
        defer { try? directory.setPermissions(0o755, of: "Locked") }

        #expect(FileLock.whileHeld(beside: directory.url.appending(path: "Locked/exclusions.json")) { 42 } == 42)
    }
}
