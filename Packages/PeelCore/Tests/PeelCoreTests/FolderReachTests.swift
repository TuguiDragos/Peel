import Darwin
import Foundation
@testable import PeelCore
import Testing

struct FolderReachTests {
    @Test(.permissionsHold) func saysWhyAFolderCantBeReached() throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("Folder")
        let file = try directory.file("File", contents: Data())
        _ = try directory.directory("Closed/Inner")
        try directory.setPermissions(0o000, of: "Closed")
        defer { try? directory.setPermissions(0o755, of: "Closed") }
        let loop = directory.url.appending(path: "Loop")
        try FileManager.default.createSymbolicLink(atPath: loop.path(percentEncoded: false), withDestinationPath: "Loop")
        let disk = "NoSuchDisk-\(UUID().uuidString)"

        #expect(FolderReach.problem(with: folder) == nil)
        #expect(FolderReach.problem(with: directory.url.appending(path: "Gone")) == .gone)
        #expect(FolderReach.problem(with: file) == .notAFolder)
        #expect(FolderReach.problem(with: directory.url.appending(path: "Closed/Inner")) == .closed)
        #expect(FolderReach.problem(with: URL(filePath: "/Volumes/\(disk)/Projects")) == .diskNotConnected(disk))
        #expect(FolderReach.problem(with: loop) == .failed(SystemError(domain: NSPOSIXErrorDomain, code: Int(ELOOP))))
    }
}
