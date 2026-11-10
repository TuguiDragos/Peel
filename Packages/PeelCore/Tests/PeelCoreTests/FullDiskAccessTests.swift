import Darwin
import Foundation
@testable import PeelCore
import Testing

struct FullDiskAccessTests {
    @Test func tellsAFolderClosedByItsPermissionsFromOneMacOSKeepsPrivate() throws {
        let directory = try TemporaryDirectory()
        let closed = try directory.directory("Closed")
        let path = closed.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path) }

        #expect(FullDiskAccess.whyUnlistable(closed) == .permissions)
        #expect(FullDiskAccess.whyUnlistable(directory.url) == nil)
        #expect(FullDiskAccess.canList(closed) == .unknown)
        #expect(FullDiskAccess.Refusal(error: EPERM) == .privacy)
    }
}
