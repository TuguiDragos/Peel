import Foundation
@testable import PeelCore
import Testing

/// While a page scans, it shows how many items the scan has read, so every walk counts for the scan that asked.
struct ScanCountTests {
    @Test func aFolderWalkedCountsWhatItRead() async throws {
        let directory = try TemporaryDirectory()
        for index in 1...5 {
            try directory.file("Folder/file \(index)", bytes: 16)
        }
        try directory.file("Folder/Inside/deeper", bytes: 16)
        let count = ScanCount()

        _ = await ScanCount.$current.withValue(count) {
            await FileSize.contents(of: directory.url.appending(path: "Folder", directoryHint: .isDirectory))
        }

        #expect(count.value == 7, "five files, a folder and the file inside it")
    }

    @Test func aFileMeasuredCountsOnce() async throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file("file", bytes: 16)
        let count = ScanCount()

        _ = await ScanCount.$current.withValue(count) { await FileSize.contents(of: file) }

        #expect(count.value == 1)
    }

    @Test func iCloudDrivesWalkCountsWhatItRead() async throws {
        let directory = try TemporaryDirectory()
        for index in 1...3 {
            try directory.file("Library/Mobile Documents/com~apple~CloudDocs/file \(index).bin", bytes: 1_000)
        }
        let count = ScanCount()

        _ = await ScanCount.$current.withValue(count) {
            await CloudStorage.downloaded(home: directory.url, minimumSize: 1)
        }

        #expect(count.value == 4, "a container and the three files in it")
    }

    @Test func aProjectsFolderCountsWhatItListed() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Code/App/package.json", contents: Data("{}".utf8))
        try directory.file("Code/App/node_modules/left-pad/index.js", contents: Data("//".utf8))
        let count = ScanCount()

        _ = await ScanCount.$current.withValue(count) {
            await ProjectArtifacts.scan(
                roots: [directory.url.appending(path: "Code", directoryHint: .isDirectory)],
                exclusions: .none
            ) { _ in FolderContents(size: 0, holdsRepository: false) }
        }

        #expect(count.value >= 3, "the project, its build file and its node_modules at least")
    }

    /// A count goes to the scan that asked and to nothing else: a walk made once that scan is over, with no scan
    /// around it, leaves its count where it was.
    @Test func aWalkNobodyCountsForCountsNothing() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Folder/file", bytes: 16)
        try directory.file("Other/file", bytes: 16)
        let count = ScanCount()

        _ = await ScanCount.$current.withValue(count) {
            await FileSize.contents(of: directory.url.appending(path: "Folder", directoryHint: .isDirectory))
        }
        let counted = count.value
        _ = await FileSize.contents(of: directory.url.appending(path: "Other", directoryHint: .isDirectory))

        #expect(counted == 1)
        #expect(count.value == counted, "a walk no scan asked for was counted")
    }
}
