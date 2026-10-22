import Foundation
@testable import PeelCore
import Testing

struct ScreenshotFolderTests {
    @Test func takesAFolderThePersonCanWriteTo() throws {
        let directory = try TemporaryDirectory()
        let shots = try directory.directory("Shots")

        #expect(ScreenshotFolder.problem(with: shots, home: directory.url) == nil)
    }

    @Test func refusesWhatIsNotAFolder() throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file("Shots.png")

        #expect(ScreenshotFolder.problem(with: file, home: directory.url) == .notAFolder)
        #expect(ScreenshotFolder.problem(with: directory.url.appending(path: "Gone"), home: directory.url) == .notAFolder)
    }

    @Test(.permissionsHold) func refusesAFolderThatCannotBeWritten() throws {
        let directory = try TemporaryDirectory()
        let shots = try directory.directory("Shots")
        try directory.setPermissions(0o555, of: shots)
        defer { try? directory.setPermissions(0o755, of: shots) }

        #expect(ScreenshotFolder.problem(with: shots, home: directory.url) == .notWritable)
    }

    @Test func aFolderFromBeforeOnADiskThatIsNotConnectedMayStillTakeScreenshots() throws {
        let directory = try TemporaryDirectory()
        let away = "/Volumes/PeelTests-\(UUID().uuidString)/Screenshots"

        #expect(!ScreenshotFolder.cannotTakeScreenshots(away, home: directory.url))
        let gone = directory.url.appending(path: "Gone").path(percentEncoded: false)
        #expect(ScreenshotFolder.cannotTakeScreenshots(gone, home: directory.url))
        let shots = try directory.directory("Shots")
        #expect(!ScreenshotFolder.cannotTakeScreenshots(shots.path(percentEncoded: false), home: directory.url))
    }

    @Test func writesTheFolderWithoutATrailingSlash() throws {
        let directory = try TemporaryDirectory()
        let shots = try directory.directory("Shots")

        #expect(ScreenshotFolder.setting(for: shots) == PathPattern.comparablePath(of: shots))
        #expect(!ScreenshotFolder.setting(for: shots).hasSuffix("/"))
        #expect(ScreenshotFolder.setting(for: URL(filePath: "/Users/Shared/", directoryHint: .isDirectory)) == "/Users/Shared")
    }

    @Test func refusesTheTrashAndAFolderInIt() throws {
        let directory = try TemporaryDirectory()
        let trash = try directory.directory(".Trash")
        let inTheTrash = try directory.directory(".Trash/Shots")

        #expect(ScreenshotFolder.problem(with: trash, home: directory.url) == .inATrash)
        #expect(ScreenshotFolder.problem(with: inTheTrash, home: directory.url) == .inATrash)
        #expect(ScreenshotFolder.problem(with: URL.homeDirectory.appending(path: ".Trash")) == .inATrash)
    }
}
