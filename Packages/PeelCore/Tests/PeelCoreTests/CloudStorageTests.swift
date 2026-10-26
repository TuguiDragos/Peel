import Foundation
@testable import PeelCore
import Testing

struct CloudStorageTests {
    /// Freeing a file that isn't safely in iCloud yet could remove its only copy.
    @Test func freesOnlyWhatIsSafelyInTheCloud() {
        #expect(CloudStorage.isSafeToFree(status: .current, isUploaded: true, isUploading: false, hasConflicts: false))
        #expect(CloudStorage.isSafeToFree(status: .current, isUploaded: true, isUploading: nil, hasConflicts: nil))

        #expect(
            !CloudStorage.isSafeToFree(status: .current, isUploaded: false, isUploading: false, hasConflicts: false),
            "it wasn't uploaded yet"
        )
        #expect(
            !CloudStorage.isSafeToFree(status: .current, isUploaded: true, isUploading: true, hasConflicts: false),
            "it was still uploading"
        )
        #expect(
            !CloudStorage.isSafeToFree(status: .current, isUploaded: true, isUploading: false, hasConflicts: true),
            "it has a conflict to settle"
        )
        #expect(
            !CloudStorage.isSafeToFree(status: .downloaded, isUploaded: true, isUploading: false, hasConflicts: false),
            "an older copy is on this Mac"
        )
        #expect(
            !CloudStorage.isSafeToFree(
                status: .notDownloaded,
                isUploaded: true,
                isUploading: false,
                hasConflicts: false
            ),
            "there is nothing here to free"
        )
        #expect(!CloudStorage.isSafeToFree(status: nil, isUploaded: nil, isUploading: nil, hasConflicts: nil))
    }

    /// On macOS 26, syncing can be paused for an item. A paused item with local edits is not uploading, yet it
    /// still reads as uploaded (`NSURL.h`: `NSURLUbiquitousItemIsSyncPausedKey`).
    @Test func leavesAloneAFileWhoseSyncIsPaused() {
        #expect(
            !CloudStorage.isSafeToFree(
                status: .current,
                isUploaded: true,
                isUploading: false,
                hasConflicts: false,
                isSyncPaused: true
            )
        )
        #expect(
            CloudStorage.isSafeToFree(
                status: .current,
                isUploaded: true,
                isUploading: false,
                hasConflicts: false,
                isSyncPaused: false
            )
        )
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

        let refused = await CloudStorage.free([scanned], exclusions: .none).refused

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

        #expect(await CloudStorage.free([scanned], exclusions: offline).refused.map(\.reason) == [.excluded])
        #expect(await CloudStorage.free([scanned], exclusions: .notYetRead).refused.map(\.reason) == [.excluded])
        #expect(await CloudStorage.free([scanned], exclusions: .unreadable).refused.map(\.reason) == [.excluded])
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

    @Test func namesAnAppsFolderAsMacOSShowsIt() {
        let root = URL.homeDirectory.appending(path: "Library/Mobile Documents", directoryHint: .isDirectory)
        let containers = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for container in containers where container.lastPathComponent != "com~apple~CloudDocs" {
            guard let shown = try? container.resourceValues(forKeys: [.ubiquitousItemContainerDisplayNameKey])
                .ubiquitousItemContainerDisplayName, !shown.isEmpty
            else { continue }
            let file = container.appending(path: "Documents/Report.pages")
            #expect(CloudStorage.containerName(of: file, under: root) == shown, "\(container.lastPathComponent)")
        }
    }

    @Test func groupsTheDownloadsByTheFolderFinderShowsThemIn() throws {
        let directory = try TemporaryDirectory()
        let root = directory.url.appending(path: "Library/Mobile Documents", directoryHint: .isDirectory)
        func file(_ path: String, _ size: Int64) throws -> CloudFile {
            let url = try directory.file("Library/Mobile Documents/\(path)")
            let container = CloudStorage.containerName(of: url, under: root)
            return CloudFile(url: url, name: url.lastPathComponent, container: container, size: size, modified: nil)
        }
        let files = [
            try file("com~apple~CloudDocs/Muzica/A.mp3", 20),
            try file("iCloud~org~example~Notes/Documents/Letter.txt", 5),
            try file("com~apple~CloudDocs/Archive.zip", 40),
            try file("com~apple~CloudDocs/Muzica/B.mp3", 30),
            try file("com~apple~CloudDocs/Documents/pfp/Me.png", 15),
            try file("iCloud~org~example~Notes/documents/Drafts/Plan.txt", 2),
        ]

        let folders = CloudStorage.folders(of: files, home: directory.url)

        #expect(folders.map(\.names) == [
            ["iCloud Drive", "Muzica"], ["iCloud Drive"], ["iCloud Drive", "Documents", "pfp"], ["Notes"],
            ["Notes", "Drafts"],
        ])
        #expect(folders.map(\.size) == [50, 40, 15, 5, 2])
        #expect(folders.first?.files.map(\.name) == ["B.mp3", "A.mp3"])
        let found = Set(files.filter { $0.name == "A.mp3" }.map(\.url))
        #expect(folders.first?.keeping(found)?.files.map(\.name) == ["A.mp3"])
        #expect(folders.first?.keeping(found)?.size == 20)
        #expect(folders.last?.keeping(found) == nil)
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

    /// A folder kept only in the cloud, which no test can make, is named to the walk.
    @Test func neverLooksIntoAFolderThatLivesOnlyInTheCloud() throws {
        let directory = try TemporaryDirectory()
        let drive = "Library/Mobile Documents/com~apple~CloudDocs"
        try directory.file("\(drive)/plain.bin", bytes: 3_000_000)
        try directory.file("\(drive)/Evicted/inside.bin", bytes: 3_000_000)
        let evicted = PathPattern.comparablePath(of: directory.url.appending(path: "\(drive)/Evicted"))

        let collector = CloudStorage.Collector()
        CloudStorage.collect(
            home: directory.url,
            minimumSize: 1,
            exclusions: .none,
            into: collector,
            deadline: .now + .seconds(20),
            countingFor: nil,
            isSafe: { _ in true },
            isDataless: { PathPattern.comparablePath(of: $0) == evicted },
            unless: { false }
        )

        #expect(collector.collected.files.map(\.name) == ["plain.bin"])
    }

    /// A download that takes a row's worth of space but shares it with another copy frees nothing, so it is left
    /// out of the list and counted, for the page to say why it is missing.
    @Test func countsTheDownloadsLeftOutBecauseAnotherCopySharesTheirSpace() throws {
        let directory = try TemporaryDirectory()
        let drive = "Library/Mobile Documents/com~apple~CloudDocs"
        try directory.file("\(drive)/plain.bin", bytes: 3_000_000)
        let original = try directory.file("\(drive)/original.bin", bytes: 2_000_000)
        let small = try directory.file("\(drive)/small.bin", bytes: 200_000)
        let inPackage = try directory.file("\(drive)/Notes.rtfd/TXT.rtf", bytes: 2_000_000)
        let drivePath = directory.url.appending(path: drive)
        for (source, name) in [(original, "clone.bin"), (small, "small clone.bin"), (inPackage, "Notes.rtf")] {
            let clone = drivePath.appending(path: name)
            #expect(clonefile(source.path(percentEncoded: false), clone.path(percentEncoded: false), 0) == 0)
        }

        let collector = CloudStorage.Collector()
        CloudStorage.collect(
            home: directory.url, minimumSize: CloudStorage.minimumSize, exclusions: .none, into: collector,
            deadline: .now + .seconds(20), countingFor: nil, isSafe: { _ in true }, unless: { false }
        )

        #expect(collector.collected.files.map(\.name) == ["plain.bin"])
        #expect(collector.collected.sharedDownloads == 4, "only the clones that take a row's worth count")
    }

    @Test func leavesAFolderWithoutICloudAlone() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Mobile Documents/com~apple~CloudDocs/plain.txt", bytes: 4_000_000)

        let scan = await CloudStorage.downloaded(home: directory.url)
        #expect(scan.files.isEmpty, "an ordinary file was offered as an iCloud one")
        #expect(!scan.couldNotRead)
        #expect(scan.cutShort == nil)
    }

    /// Without Full Disk Access, iCloud Drive cannot be read. The scan then says so, rather than reporting
    /// nothing to free.
    @Test(.permissionsHold) func saysWhenICloudDriveCouldNotBeRead() async throws {
        let directory = try TemporaryDirectory()
        try directory.directory("Library/Mobile Documents")
        try directory.setPermissions(0o000, of: "Library/Mobile Documents")
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: directory.url.appending(path: "Library/Mobile Documents").path(percentEncoded: false)
            )
        }

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

        #expect(scan.cutShort == .ranOutOfTime)
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
        #expect(collector.collected.cutShort == .listIsFull)
    }

    @Test func aListThatFilledBeforeTheTimeRanOutSaysTheTimeRanOut() {
        let collector = CloudStorage.Collector(maximum: 1)
        for name in ["a.bin", "b.bin"] {
            collector.add(CloudFile(
                url: URL(filePath: "/org.example/\(name)"), name: name, container: "iCloud Drive", size: 2_000_000,
                modified: nil
            ))
        }
        #expect(collector.collected.cutShort == .listIsFull)

        collector.ranOutOfTime()
        collector.add(CloudFile(
            url: URL(filePath: "/org.example/c.bin"), name: "c.bin", container: "iCloud Drive", size: 3_000_000,
            modified: nil
        ))
        #expect(collector.collected.cutShort == .ranOutOfTime)
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

        CloudStorage.collect(
            home: directory.url,
            minimumSize: 1,
            exclusions: .none,
            into: collector,
            deadline: .now,
            countingFor: nil,
            unless: { false }
        )

        #expect(collector.collected.cutShort == .ranOutOfTime)
        #expect(collector.collected.files.isEmpty)
    }

    @Test func listsOnlyWhatFinderShows() throws {
        let directory = try TemporaryDirectory()
        let cloud = "Library/Mobile Documents"
        try directory.file("\(cloud)/com~apple~CloudDocs/Song.mp3", bytes: 2_000_000)
        try directory.file("\(cloud)/com~apple~CloudDocs/Data/Shared.bin", bytes: 2_000_000)
        try directory.file("\(cloud)/iCloud~org~example~notes/Documents/Note.bin", bytes: 2_000_000)
        try directory.file("\(cloud)/iCloud~org~example~notes/Data/cache.bin", bytes: 2_000_000)
        try directory.file("\(cloud)/iCloud~org~example~notes/state.bin", bytes: 2_000_000)
        let collector = CloudStorage.Collector()

        CloudStorage.collect(
            home: directory.url, minimumSize: 1, exclusions: .none, into: collector,
            deadline: .now + .seconds(20), countingFor: nil, isSafe: { _ in true }, unless: { false }
        )

        #expect(collector.collected.files.map(\.name).sorted() == ["Note.bin", "Shared.bin", "Song.mp3"])
    }

    @Test func looksIntoTheFolderAfterAFileWhoseDownloadWasRemoved() throws {
        let directory = try TemporaryDirectory()
        let drive = "Library/Mobile Documents/com~apple~CloudDocs"
        let evicted = try directory.file("\(drive)/Evicted.bin", bytes: 2_000_000)
        for folder in ["A", "B", "C", "D", "E"] {
            try directory.file("\(drive)/\(folder)/x.bin", bytes: 2_000_000)
        }
        let collector = CloudStorage.Collector()

        CloudStorage.collect(
            home: directory.url, minimumSize: 1, exclusions: .none, into: collector,
            deadline: .now + .seconds(20), countingFor: nil, isSafe: { _ in true },
            isDataless: { $0.lastPathComponent == evicted.lastPathComponent }, unless: { false }
        )

        let folders = collector.collected.files.map { $0.url.deletingLastPathComponent().lastPathComponent }
        #expect(folders.sorted() == ["A", "B", "C", "D", "E"])
    }

    @Test func namesAFileAsFinderShowsIt() throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Mobile Documents/com~apple~CloudDocs/Buget 3:4.bin", bytes: 16)
        let collector = CloudStorage.Collector()

        CloudStorage.collect(
            home: directory.url, minimumSize: 1, exclusions: .none, into: collector, deadline: .now + .seconds(20),
            countingFor: nil, isSafe: { _ in true }, unless: { false }
        )

        #expect(collector.collected.files.map(\.name) == ["Buget 3/4.bin"])
    }

    @Test func anExcludedFolderIsNotWalked() throws {
        let directory = try TemporaryDirectory()
        let drive = "Library/Mobile Documents/com~apple~CloudDocs"
        for index in 0..<20 {
            try directory.file("\(drive)/Archive/old\(index).bin", bytes: 16)
        }
        try directory.file("\(drive)/kept.bin", bytes: 16)
        let archive = directory.url.appending(path: "\(drive)/Archive", directoryHint: .isDirectory)
        let collector = CloudStorage.Collector()
        let count = ScanCount()

        CloudStorage.collect(
            home: directory.url, minimumSize: 1, exclusions: Exclusions(paths: [archive]), into: collector,
            deadline: .now + .seconds(20), countingFor: count, isSafe: { _ in true }, unless: { false }
        )

        #expect(collector.collected.files.map(\.name) == ["kept.bin"])
        #expect(count.value == 3, "iCloud Drive, the archive and kept.bin, nothing inside the archive")
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

        let untouched = await CloudStorage.free([scanned], exclusions: .none, isSafe: { _ in true }).refused
        let later: [FileAttributeKey: Any] = [.modificationDate: Date.now.addingTimeInterval(60)]
        try FileManager.default.setAttributes(later, ofItemAtPath: inside.path(percentEncoded: false))
        let edited = await CloudStorage.free([scanned], exclusions: .none, isSafe: { _ in true }).refused

        #expect(untouched.map(\.reason) != [.changedSinceScan], "only iCloud can remove a download, so a test's fails")
        #expect(edited.map(\.reason) == [.changedSinceScan])
    }

    @Test func leavesAlonePackagesThatHoldSomethingExcludedSinceTheScan() async throws {
        let directory = try TemporaryDirectory()
        let drive = "Library/Mobile Documents/com~apple~CloudDocs"
        let inside = try directory.file("\(drive)/Notes.rtfd/TXT.rtf", bytes: 2_000_000)
        let collector = CloudStorage.Collector()
        CloudStorage.collect(
            home: directory.url, minimumSize: 1, exclusions: .none, into: collector, deadline: .now + .seconds(20),
            countingFor: nil, isSafe: { _ in true }, unless: { false }
        )
        let scanned = try #require(collector.collected.files.first)
        let undated = CloudFile(
            url: scanned.url, name: scanned.name, container: scanned.container, size: 1, modified: nil
        )
        let excluded = Exclusions(paths: [inside])
        var evicted: [URL] = []

        let refused = await CloudStorage.free([scanned], exclusions: excluded, isSafe: { _ in true }) {
            evicted.append($0)
        }.refused
        let undatedRefused = await CloudStorage.free([undated], exclusions: excluded, isSafe: { _ in true }) {
            evicted.append($0)
        }.refused

        #expect(refused.map(\.reason) == [.excluded])
        #expect(undatedRefused.map(\.reason) == [.excluded])
        #expect(evicted.isEmpty)
    }

    @Test func stopsBetweenFilesOnceItsTaskIsCancelled() async throws {
        let directory = try TemporaryDirectory()
        let files = try downloads(3, in: directory)

        let done = await Task {
            await CloudStorage.free(files, exclusions: .none, isSafe: { _ in true }) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }.value

        #expect(done.freed.map(\.url) == [files[0].url])
        #expect(done.refused.isEmpty)
    }

    @Test func countsEachFileItFrees() async throws {
        let directory = try TemporaryDirectory()
        let files = try downloads(3, in: directory)
        let counted = MoveCount()

        let done = await MoveCount.$current.withValue(counted) {
            await CloudStorage.free(files, exclusions: .none, isSafe: { _ in true }) { url in
                if url == files[2].url { throw CocoaError(.fileLocking) }
            }
        }

        #expect(done.freed.map(\.url) == [files[0].url, files[1].url])
        #expect(done.refused.map(\.reason) == [.inUse])
        #expect(counted.value == 2)
    }

    private func downloads(_ count: Int, in directory: borrowing TemporaryDirectory) throws -> [CloudFile] {
        try (1...count).map { index in
            let url = try directory.file("file\(index).bin", bytes: 2_000_000)
            let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return CloudFile(
                url: url, name: url.lastPathComponent, container: "iCloud Drive", size: 2_000_000, modified: modified
            )
        }
    }

    /// A file a program holds, as the desktop picture is held, cannot be locked, and the person is told so.
    @Test func aFileAProgramHoldsIsRefusedAsInUse() {
        let locked = CocoaError(.fileLocking)
        #expect(CloudStorage.reason(for: locked) == .inUse)
        let other = CocoaError(.fileWriteNoPermission)
        #expect(CloudStorage.reason(for: other) == .failed(other.localizedDescription))
    }

    /// The desktop picture is open for as long as it is shown, so the scan says which file it is.
    @Test func theDesktopPictureIsMarked() throws {
        let directory = try TemporaryDirectory()
        let drive = "Library/Mobile Documents/com~apple~CloudDocs"
        let picture = try directory.file("\(drive)/Wallpaper.png", bytes: 2_000_000)
        try directory.file("\(drive)/Other.png", bytes: 2_000_000)

        let collector = CloudStorage.Collector()
        CloudStorage.collect(
            home: directory.url, minimumSize: 1, exclusions: .none, desktopPictures: [picture], into: collector,
            deadline: .now + .seconds(20), countingFor: nil, isSafe: { _ in true }, unless: { false }
        )
        let marked = Dictionary(uniqueKeysWithValues: collector.collected.files.map { ($0.name, $0.isDesktopPicture) })

        #expect(marked == ["Wallpaper.png": true, "Other.png": false])
    }
}
