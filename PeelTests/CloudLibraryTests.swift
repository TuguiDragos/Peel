import Foundation
@testable import Peel
import PeelCore
import Testing

@MainActor
struct CloudLibraryTests {
    @Test func hasNoTotalUntilICloudDriveIsRead() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        let drive = home.appending(path: "Library/Mobile Documents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        func permit(_ mode: Int) throws {
            try FileManager.default.setAttributes(
                [.posixPermissions: mode], ofItemAtPath: drive.path(percentEncoded: false)
            )
        }
        defer {
            try? permit(0o755)
            try? FileManager.default.removeItem(at: home)
        }
        let cloud = CloudLibrary(home: home)
        #expect(cloud.total == nil)

        try permit(0)
        await cloud.refresh()
        #expect(cloud.couldNotRead)
        #expect(cloud.total == nil)
        #expect(cloud.looked == nil)

        try permit(0o755)
        await cloud.refresh()
        #expect(!cloud.couldNotRead)
        #expect(cloud.total == SizeTotal(known: 0, isComplete: true))
    }
}
