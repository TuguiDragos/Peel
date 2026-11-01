import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct CloudLibraryTests {
    private final class Asked {
        var scans = 0
        var removals: [[URL]] = []
    }

    private static func download(_ name: String) -> CloudFile {
        CloudFile(
            url: URL(filePath: "/org.example/\(name)"), name: name, container: "iCloud Drive", size: 2_000_000,
            modified: nil
        )
    }

    @Test func aFolderOfTheHomeThatCouldNotBeReadLeavesTheTotalOnlyTheLeastItCanBe() async {
        let cloud = CloudLibrary(scan: { _, _, _ in
            CloudScan(files: [Self.download("Plan.pdf")], unreadableFolders: ["Documents"])
        })

        await cloud.refresh()

        #expect(cloud.unreadableFolders == ["Documents"])
        #expect(cloud.total?.isComplete == false)
    }

    @Test func aFolderInsideThatCouldNotBeReadLeavesTheTotalOnlyTheLeastItCanBe() async {
        let locked = URL(filePath: "/org.example/Locked")
        let cloud = CloudLibrary(scan: { _, _, _ in
            CloudScan(files: [Self.download("Plan.pdf")], notRead: [locked])
        })

        await cloud.refresh()

        #expect(cloud.notRead == [locked])
        #expect(cloud.total?.isComplete == false)
    }

    @Test func anEmptyListTellsVoiceOverWhyWhenThereIsAReason() async {
        func spoken(_ found: CloudScan) async -> String? {
            let cloud = CloudLibrary(scan: { _, _, _ in found })
            await cloud.refresh()
            return cloud.couldNotLook?.key
        }

        #expect(await spoken(CloudScan(isNotSetUp: true)) == "iCloud Drive Isn’t Set Up")
        #expect(await spoken(CloudScan(couldNotRead: true)) == "iCloud Drive Couldn’t Be Read")
        #expect(await spoken(CloudScan(cutShort: .ranOutOfTime)) == "Nothing Found So Far")
        #expect(await spoken(CloudScan(notRead: [URL(filePath: "/org.example/Locked")])) == "Nothing Found So Far")
        #expect(await spoken(CloudScan()) == nil)
        #expect(await spoken(CloudScan(files: [Self.download("Plan.pdf")], isNotSetUp: true)) == nil)
    }

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

    @Test func saysWhatStayedOnceTheListIsReadAgain() async {
        let freed = Self.download("Freed.mov")
        let kept = Self.download("Kept.mov")
        let asked = Asked()
        let cloud = CloudLibrary(
            scan: { _, _, _ in
                asked.scans += 1
                return CloudScan(files: asked.scans == 1 ? [freed, kept] : [kept])
            },
            removeDownloads: { files, _ in
                asked.removals.append(files.map(\.url))
                return CloudFreeing(freed: [freed], refused: [CloudRefusal(url: kept.url, reason: .changedSinceScan)])
            }
        )
        await cloud.refresh()
        cloud.selectedURLs = [freed.url, kept.url]

        let size = await cloud.freeSelected()

        #expect(asked.removals == [[freed.url, kept.url]])
        #expect(size == freed.size)
        #expect(cloud.files == [kept])
        #expect(cloud.selectedURLs == [kept.url])
        #expect(cloud.refusals.map(\.url) == [kept.url])
    }

    @Test func aRescanStoppedAfterRemovingDownloadsListsNothingThatWasRemoved() async {
        let freed = Self.download("Freed.mov")
        let kept = Self.download("Kept.mov")
        let everything = CloudStorage.folders(of: [freed, kept], home: URL(filePath: "/org.example"))
        let (rescan, rescans) = AsyncStream.makeStream(of: Void.self)
        let asked = Asked()
        let cloud = CloudLibrary(
            scan: { _, _, _ in
                asked.scans += 1
                if asked.scans > 1 {
                    rescans.yield()
                    try? await Task.sleep(for: .seconds(30))
                }
                return CloudScan(files: [freed, kept], folders: everything)
            },
            removeDownloads: { _, _ in CloudFreeing(freed: [freed]) }
        )
        await cloud.refresh()
        cloud.selectedURLs = [freed.url]

        let removal = Task { await cloud.freeSelected() }
        var waiting = rescan.makeAsyncIterator()
        await waiting.next()

        #expect(cloud.isFreeing)
        #expect(!cloud.freeing.isMoving)
        #expect(cloud.files == [kept])
        #expect(cloud.folders.flatMap(\.files) == [kept])
        #expect(cloud.files(matching: "Freed").isEmpty)
        #expect(cloud.selectedURLs.isEmpty)

        cloud.scanRun.stop()

        #expect(await removal.value == freed.size)
        #expect(cloud.files == [kept])
        #expect(!cloud.isFreeing)
    }

    @Test func stopsRemovingDownloadsWhenAsked() async {
        let download = Self.download("Film.mov")
        let (started, starts) = AsyncStream.makeStream(of: Void.self)
        let cloud = CloudLibrary(
            scan: { _, _, _ in CloudScan(files: [download]) },
            removeDownloads: { files, _ in
                starts.yield()
                do {
                    try await Task.sleep(for: .seconds(30))
                    return CloudFreeing(freed: files)
                } catch {
                    return CloudFreeing()
                }
            }
        )
        await cloud.refresh()
        cloud.selectedURLs = [download.url]
        let removal = Task { await cloud.freeSelected() }
        var waiting = started.makeAsyncIterator()
        await waiting.next()

        cloud.stopFreeing()

        #expect(await removal.value == 0)
        #expect(!cloud.isFreeing)
    }
}
