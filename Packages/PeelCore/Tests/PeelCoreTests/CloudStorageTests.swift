import Foundation
@testable import PeelCore
import Testing

struct CloudStorageTests {
    /// Freeing a file that isn't safely in iCloud yet could remove its only copy.
    @Test func freesOnlyWhatIsSafelyInTheCloud() {
        #expect(CloudStorage.isSafeToFree(status: .current, isUploaded: true, isUploading: false, hasConflicts: false))
        #expect(CloudStorage.isSafeToFree(status: .current, isUploaded: true, isUploading: nil, hasConflicts: nil))

        #expect(!CloudStorage.isSafeToFree(status: .current, isUploaded: false, isUploading: false, hasConflicts: false), "it wasn't uploaded yet")
        #expect(!CloudStorage.isSafeToFree(status: .current, isUploaded: true, isUploading: true, hasConflicts: false), "it was still uploading")
        #expect(!CloudStorage.isSafeToFree(status: .current, isUploaded: true, isUploading: false, hasConflicts: true), "it has a conflict to settle")
        #expect(!CloudStorage.isSafeToFree(status: .downloaded, isUploaded: true, isUploading: false, hasConflicts: false), "an older copy is on this Mac")
        #expect(!CloudStorage.isSafeToFree(status: .notDownloaded, isUploaded: true, isUploading: false, hasConflicts: false), "there is nothing here to free")
        #expect(!CloudStorage.isSafeToFree(status: nil, isUploaded: nil, isUploading: nil, hasConflicts: nil))
    }

    /// On macOS 26, syncing can be paused for an item. A paused item with local edits is not uploading, yet it
    /// still reads as uploaded (`NSURL.h`: `NSURLUbiquitousItemIsSyncPausedKey`).
    @Test func leavesAloneAFileWhoseSyncIsPaused() {
        #expect(!CloudStorage.isSafeToFree(status: .current, isUploaded: true, isUploading: false, hasConflicts: false, isSyncPaused: true))
        #expect(CloudStorage.isSafeToFree(status: .current, isUploaded: true, isUploading: false, hasConflicts: false, isSyncPaused: false))
        #expect(!CloudStorage.isSafeToFree(
            status: .current, isUploaded: true, isUploading: false, hasConflicts: false,
            uploadingError: CocoaError(.fileWriteNoPermission)
        ))
    }

    /// The list can stay on screen for hours, so each file is checked again at the moment it is freed. A file
    /// that changed since the scan is not freed.
    @Test func freesNothingThatChangedSinceTheScan() async throws {
        let directory = try TemporaryDirectory()
        let url = try directory.file("file.bin", bytes: 2_000_000)
        let scanned = CloudFile(url: url, name: "file.bin", container: "iCloud Drive", size: 2_000_000, modified: .distantPast)

        let refused = await CloudStorage.free([scanned], exclusions: .none)

        #expect(refused.map(\.url) == [url])
        #expect(refused.first?.reason == .changedSinceScan)
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    /// The list on screen was filtered by the exclusions as they stood at the scan, so a file excluded since, or
    /// any file while the exclusions are not known, stays downloaded.
    @Test func leavesAloneWhatWasExcludedSinceTheScan() async throws {
        let directory = try TemporaryDirectory()
        let url = try directory.file("Offline/file.bin", bytes: 2_000_000)
        let scanned = CloudFile(url: url, name: "file.bin", container: "iCloud Drive", size: 2_000_000, modified: .distantPast)
        let offline = Exclusions(paths: [directory.url.appending(path: "Offline", directoryHint: .isDirectory)])

        #expect(await CloudStorage.free([scanned], exclusions: offline).map(\.reason) == [.excluded])
        #expect(await CloudStorage.free([scanned], exclusions: .notYetRead).map(\.reason) == [.excluded])
        #expect(await CloudStorage.free([scanned], exclusions: .unreadable).map(\.reason) == [.excluded])
    }

    @Test func callsEachFolderWhatTheUserCallsIt() {
        let root = URL(filePath: "/Users/x/Library/Mobile Documents", directoryHint: .isDirectory)
        func name(_ path: String) -> String {
            CloudStorage.containerName(of: URL(filePath: "/Users/x/Library/Mobile Documents/" + path), under: root)
        }

        #expect(name("com~apple~CloudDocs/Photo.png") == "iCloud Drive")
        #expect(name("com~apple~Pages/Letter.pages") == "Pages")
        #expect(name("iCloud~com~facebook~Messenger/a.bin") == "Messenger")
        #expect(name("F3LWYJ7GM7~com~apple~garageband10/Song") == "garageband10")
        #expect(CloudStorage.containerName(of: URL(filePath: "/somewhere/else"), under: root) == "")
    }

    /// Scans the real iCloud Drive of the Mac running the tests, which must work and change nothing.
    @Test func readsThisMacWithoutFreeingAnything() async {
        let scan = await CloudStorage.downloaded()
        #expect(scan.files.allSatisfy { $0.size >= CloudStorage.minimumSize })
        #expect(scan.files.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path(percentEncoded: false)) })
        #expect(Set(scan.files.map(\.id)).count == scan.files.count)
    }

    /// A row's size is what removing the download frees, never the length the file claims: a file stored
    /// compressed takes fewer blocks than its length, and a clone shares its blocks, so removing it frees nothing.
    /// Only iCloud can say a file is safely there, so the test says it for these.
    @Test func aFilesSizeIsWhatRemovingItsDownloadFrees() throws {
        let directory = try TemporaryDirectory()
        let drive = "Library/Mobile Documents/com~apple~CloudDocs"
        let plain = try directory.file("\(drive)/plain.bin", bytes: 3_000_000)
        let compressed = try directory.compressedTextFile("\(drive)/compressed.txt")
        let original = try directory.file("\(drive)/original.bin", bytes: 2_000_000)
        let clone = original.deletingLastPathComponent().appending(path: "clone.bin")
        #expect(clonefile(original.path(percentEncoded: false), clone.path(percentEncoded: false), 0) == 0)

        let collector = CloudStorage.Collector()
        CloudStorage.collect(
            home: directory.url,
            minimumSize: 1,
            exclusions: .none,
            into: collector,
            deadline: .now + .seconds(20),
            countingFor: nil,
            isSafe: { _ in true },
            unless: { false }
        )
        let sizes = Dictionary(uniqueKeysWithValues: collector.collected.files.map { ($0.name, $0.size) })

        #expect(sizes["plain.bin"] == ReclaimableSpace.of(plain))
        #expect((sizes["plain.bin"] ?? 0) >= 3_000_000)
        #expect(sizes["compressed.txt"] == ReclaimableSpace.of(compressed))
        #expect((sizes["compressed.txt"] ?? .max) < 240_000, "the compressed file was weighed by its length")
        #expect(sizes["original.bin"] == nil, "a file whose blocks a clone shares frees nothing")
        #expect(sizes["clone.bin"] == nil, "a clone frees nothing")
    }

    @Test func leavesAFolderWithoutICloudAlone() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Mobile Documents/com~apple~CloudDocs/plain.txt", bytes: 4_000_000)

        let scan = await CloudStorage.downloaded(home: directory.url)
        #expect(scan.files.isEmpty, "an ordinary file was offered as an iCloud one")
        #expect(!scan.couldNotRead)
        #expect(!scan.wasCutShort)
    }

    /// Without Full Disk Access, iCloud Drive cannot be read. The scan then says so, rather than reporting
    /// nothing to free.
    @Test(.permissionsHold) func saysWhenICloudDriveCouldNotBeRead() async throws {
        let directory = try TemporaryDirectory()
        try directory.directory("Library/Mobile Documents")
        try directory.setPermissions(0o000, of: "Library/Mobile Documents")
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.url.appending(path: "Library/Mobile Documents").path(percentEncoded: false)) }

        let scan = await CloudStorage.downloaded(home: directory.url)

        #expect(scan.couldNotRead)
        #expect(scan.files.isEmpty)
    }

    /// A Mac where iCloud Drive was never set up has no `Mobile Documents` folder. That is nothing to list, not a
    /// folder that could not be read, so the page does not ask for Full Disk Access, which would change nothing.
    @Test func aMacWithoutICloudDriveIsNotOneThatCouldNotBeRead() async throws {
        let directory = try TemporaryDirectory()
        try directory.directory("Library")

        let scan = await CloudStorage.downloaded(home: directory.url)

        #expect(!scan.couldNotRead)
        #expect(scan.files.isEmpty)
    }

    /// A walk that stops early, because it ran out of time or filled its list, says it was cut short, so a
    /// partial list is never shown as a complete one.
    @Test func saysWhenTheWalkWasCutShort() async throws {
        let directory = try TemporaryDirectory()
        for index in 0..<20 {
            try directory.file("Library/Mobile Documents/com~apple~CloudDocs/folder\(index)/file.bin", bytes: 1_000)
        }

        let scan = await CloudStorage.downloaded(home: directory.url, within: 0)

        #expect(scan.wasCutShort)
    }

    /// A full list keeps the biggest files the walk finds, wherever they are, and still says it is not all of it.
    @Test func aFullListKeepsTheBiggestFilesFoundAnywhere() throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Mobile Documents/com~apple~CloudDocs/a/first.bin", bytes: 2_000)
        try directory.file("Library/Mobile Documents/com~apple~CloudDocs/b/second.bin", bytes: 30_000)
        try directory.file("Library/Mobile Documents/com~apple~CloudDocs/z/last.bin", bytes: 90_000)
        let collector = CloudStorage.Collector(maximum: 2)

        CloudStorage.collect(
            home: directory.url, minimumSize: 1, exclusions: .none, into: collector, deadline: .now + .seconds(20),
            countingFor: nil, isSafe: { _ in true }, unless: { false }
        )

        #expect(Set(collector.collected.files.map(\.name)) == ["last.bin", "second.bin"])
        #expect(collector.collected.wasCutShort)
    }

    /// A walk past its deadline stops on its own, without waiting for the timer that gives up on it. That timer
    /// runs on another thread and can fire late on a busy Mac, so a short walk could finish first and read as a
    /// complete list.
    @Test func aWalkPastItsDeadlineStopsWithoutWaitingForTheTimer() async throws {
        let directory = try TemporaryDirectory()
        for index in 0..<3 {
            try directory.file("Library/Mobile Documents/com~apple~CloudDocs/file\(index).bin", bytes: 1_000)
        }
        let collector = CloudStorage.Collector()

        CloudStorage.collect(home: directory.url, minimumSize: 1, exclusions: .none, into: collector, deadline: .now, countingFor: nil, unless: { false })

        #expect(collector.collected.wasCutShort)
        #expect(collector.collected.files.isEmpty)
    }

    /// iCloud Drive keeps a document saved as a package as one item, and Finder removes its download whole.
    @Test func aDocumentSavedAsAPackageIsOneItem() throws {
        let directory = try TemporaryDirectory()
        let drive = "Library/Mobile Documents/com~apple~CloudDocs"
        try directory.file("\(drive)/Notes.rtfd/TXT.rtf", bytes: 2_000_000)
        try directory.file("\(drive)/Notes.rtfd/Attachments/take.bin", bytes: 1_000_000)
        try directory.file("\(drive)/Kept.rtfd/TXT.rtf", bytes: 2_000_000)
        try directory.file("\(drive)/Kept.rtfd/private.bin", bytes: 2_000_000)
        try directory.file("\(drive)/Folder/inside.bin", bytes: 2_000_000)
        let package = directory.url.appending(path: "\(drive)/Notes.rtfd", directoryHint: .isDirectory)
        let excluded = directory.url.appending(path: "\(drive)/Kept.rtfd/private.bin")
        let collector = CloudStorage.Collector()

        CloudStorage.collect(
            home: directory.url, minimumSize: 1, exclusions: Exclusions(paths: [excluded]), into: collector,
            deadline: .now + .seconds(20), countingFor: nil, isSafe: { _ in true }, unless: { false }
        )
        let files = Dictionary(uniqueKeysWithValues: collector.collected.files.map { ($0.name, $0) })

        #expect(files.keys.sorted() == ["Notes.rtfd", "inside.bin"])
        #expect(files["Notes.rtfd"]?.size == FileSize.walk(package, unless: { false })?.size)
        #expect((files["Notes.rtfd"]?.size ?? 0) >= 3_000_000)
    }

    /// Editing a file inside a package leaves the package's own date as it was, so the newest date inside is what
    /// tells that it changed since the scan.
    @Test func freesNoPackageEditedInsideSinceTheScan() async throws {
        let directory = try TemporaryDirectory()
        let drive = "Library/Mobile Documents/com~apple~CloudDocs"
        let inside = try directory.file("\(drive)/Notes.rtfd/TXT.rtf", bytes: 2_000_000)
        let collector = CloudStorage.Collector()
        CloudStorage.collect(
            home: directory.url, minimumSize: 1, exclusions: .none, into: collector, deadline: .now + .seconds(20),
            countingFor: nil, isSafe: { _ in true }, unless: { false }
        )
        let scanned = try #require(collector.collected.files.first)

        let untouched = await CloudStorage.free([scanned], exclusions: .none, isSafe: { _ in true })
        let later: [FileAttributeKey: Any] = [.modificationDate: Date.now.addingTimeInterval(60)]
        try FileManager.default.setAttributes(later, ofItemAtPath: inside.path(percentEncoded: false))
        let edited = await CloudStorage.free([scanned], exclusions: .none, isSafe: { _ in true })

        #expect(untouched.map(\.reason) != [.changedSinceScan], "only iCloud can remove a download, so a test's fails")
        #expect(edited.map(\.reason) == [.changedSinceScan])
    }
}
