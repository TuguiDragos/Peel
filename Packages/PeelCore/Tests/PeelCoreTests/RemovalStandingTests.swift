import Foundation
@testable import PeelCore
import Testing

struct RemovalStandingTests {
    private func record(_ trashed: URL, size: Int64?) -> RemovalRecord {
        let item = TrashedItem(originalURL: URL(filePath: "/Users/Shared/org.example/\(trashed.lastPathComponent)"), trashedURL: trashed, date: .now)
        return RemovalRecord(batch: UUID(), item: item, size: size, source: "Example", tool: "duplicates")
    }

    @Test func sortsEachRecordByWhereItStandsAndTotalsWhatCanBePutBack() throws {
        let directory = try TemporaryDirectory()
        let kept = record(try directory.file(".Trash/kept.txt"), size: 10)
        let gone = record(directory.url.appending(path: ".Trash/gone.txt"), size: 5)
        let away = record(URL(filePath: "/Volumes/org.example.not-connected/.Trashes/501/away.txt"), size: 7)
        let closed = try directory.directory("closed")
        let notKnown = record(try directory.file("closed/hidden.txt"), size: 3)
        let alsoKept = record(try directory.file(".Trash/also kept.txt"), size: nil)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: closed.path(percentEncoded: false)
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: closed.path(percentEncoded: false)
            )
        }
        let records = [kept, gone, away, notKnown, alsoKept]

        let standing = RemovalStanding(records)

        #expect(standing.inTrash == [kept.id, alsoKept.id])
        #expect(standing.away == [away.id])
        #expect(standing.notKnown == [notKnown.id])
        #expect(standing.restorable == [kept.id, alsoKept.id])
        #expect(standing.restorableSize == SizeTotal([10, nil]))
        #expect(standing.missingCount == 1)
        #expect(standing.missing(among: records).map(\.id) == [gone.id])
    }

    @Test func knowsAnItemsDiskByItsVolumeRatherThanItsName() throws {
        let directory = try TemporaryDirectory()
        let place = directory.url.appending(path: "Disk", directoryHint: .isDirectory)
        var disk: ScratchVolume? = try ScratchVolume(fileSystem: "MS-DOS FAT32", mountedAt: place)
        let trashed = place.appending(path: ".Trashes/\(getuid())/report.txt")
        let trash = trashed.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data("report".utf8).write(to: trashed)
        let moved = record(trashed, size: 6)

        try disk?.remount(at: directory.url.appending(path: "Renamed", directoryHint: .isDirectory))
        let elsewhere = RemovalStanding([moved])
        disk = nil
        let other = try ScratchVolume(fileSystem: "MS-DOS FAT32", mountedAt: place)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data("other".utf8).write(to: trashed)
        let sameName = RemovalStanding([moved])

        #expect(elsewhere.inTrash == [moved.id])
        #expect(sameName.away == [moved.id] && sameName.inTrash.isEmpty)
        withExtendedLifetime(other) {}
    }

    @Test func countsAndListsOnlyWhatIsSelectedAndCanBePutBack() throws {
        let directory = try TemporaryDirectory()
        let first = record(try directory.file(".Trash/first.txt"), size: 1)
        let gone = record(directory.url.appending(path: ".Trash/gone.txt"), size: 1)
        let second = record(try directory.file(".Trash/second.txt"), size: 1)
        let records = [first, gone, second]

        let standing = RemovalStanding(records)
        let selection: Set = [second.id, gone.id, first.id, UUID()]

        #expect(standing.selectedCount(in: selection) == 2)
        #expect(standing.selected(among: records, in: selection).map(\.id) == [first.id, second.id])
        #expect(standing.selectedCount(in: []) == 0)
    }
}
