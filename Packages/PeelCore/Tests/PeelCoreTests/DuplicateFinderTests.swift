import Darwin
import Foundation
import Synchronization
@testable import PeelCore
import Testing

struct DuplicateFinderTests {
    @Test func oneCopyOfAGroupCanNeverBeSelected() {
        let copies = ["/a/one", "/b/one", "/c/one"].map { URL(filePath: $0) }

        #expect(DuplicateScan.canChange(copies[0], among: copies, selected: []))
        #expect(DuplicateScan.canChange(copies[1], among: copies, selected: [copies[0]]))
        #expect(!DuplicateScan.canChange(copies[2], among: copies, selected: [copies[0], copies[1]]))
        #expect(DuplicateScan.canChange(copies[1], among: copies, selected: [copies[0], copies[1]]), "a selected copy can always go back")
    }

    @Test func aReadThatNeverAnswersHoldsNeitherAStoppedScanNorItsThreads() async throws {
        let stuck = Stuck()
        let reading = Task {
            await FileDigest.many(Array(0..<8)) { _ -> ContentDigest? in
                stuck.hold()
                return nil
            }
        }
        await stuck.untilHeld()

        reading.cancel()
        _ = await reading.value

        #expect(stuck.isStillHeld, "the stopped scan waited for its reads to answer")
        stuck.letGo()
    }

    @Test func aWalkThatNeverAnswersHoldsNeitherAStoppedScanNorItsThreads() async throws {
        let stuck = Stuck()
        let walking = Task {
            try await DuplicateFinder.walk { _ throws(CancellationError) in
                stuck.hold()
                return 0
            }
        }
        await stuck.untilHeld()

        walking.cancel()
        let result = await walking.result

        #expect(stuck.isStillHeld, "the stopped scan waited for its walk to answer")
        #expect(throws: CancellationError.self) { try result.get() }
        stuck.letGo()
    }

    /// A read or a walk that never answers, as on a network volume that stopped answering. A test that would otherwise
    /// wait forever is let go after two minutes, so it fails rather than hangs.
    private final class Stuck: Sendable {
        private let gate = DispatchSemaphore(value: 0)
        private let isLetGo = Mutex(false)
        private let (holding, isHolding) = AsyncStream.makeStream(of: Void.self)

        var isStillHeld: Bool { isLetGo.withLock { !$0 } }

        func hold() {
            isHolding.yield()
            gate.wait()
        }

        func untilHeld() async {
            for await _ in holding { break }
            Task.detached { [self] in
                try? await Task.sleep(for: .seconds(120))
                letGo()
            }
        }

        /// Lets every read and walk held so far go, and any that comes after.
        func letGo() {
            let wasLetGo = isLetGo.withLock { isLetGo in
                defer { isLetGo = true }
                return isLetGo
            }
            guard !wasLetGo else { return }
            for _ in 0..<64 { gate.signal() }
        }
    }

    /// Verifying reads a mebibyte at a time, and each report is a transaction on the main actor. So reports are
    /// let through at most once every 50 ms, and the last one is always let through.
    @Test func reportsReadingAtARateTheScreenCanTake() {
        let reports = Mutex<[DuplicateScanProgress]>([])
        let reading = ReadProgress(bytesToRead: 1_000) { update in reports.withLock { $0.append(update) } }
        for _ in 0..<1_000 { reading.add(1) }

        let seen = reports.withLock { $0 }
        #expect(seen.count <= 3, "\(seen.count) reports for a thousand reads")
        #expect(seen.last == .verifying(bytesRead: 1_000, bytesToRead: 1_000))
    }

    private func randomData(count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: 0...255) })
    }

    private func scan(
        _ directory: borrowing TemporaryDirectory,
        folders: [String] = ["home"],
        configure: (inout DuplicateScanOptions) -> Void = { _ in }
    ) async throws -> DuplicateScan {
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        var options = DuplicateScanOptions.everySize(
            in: folders.map { directory.url.appending(path: $0, directoryHint: .isDirectory) }
        )
        configure(&options)
        return try await DuplicateFinder(homeDirectory: home).scan(options)
    }

    private func names(_ scan: DuplicateScan) -> [[String]] {
        scan.groups.map { $0.files.map { $0.url.pathComponents.drop { $0 != "home" }.dropFirst().joined(separator: "/") } }
    }

    /// The times come from `lstat` on files Peel did not write, on whatever volume Duplicates is pointed at. In
    /// nanoseconds an `Int` runs from 1677 to 2262, and a date outside that (a share's unset date is 1601)
    /// must not crash the scan.
    @Test func aDateNoCalendarNeedsDoesNotCrashTheScan() {
        var late = stat()
        late.st_mtimespec.tv_sec = 10_000_000_000
        late.st_mtimespec.tv_nsec = 5
        var early = stat()
        early.st_mtimespec.tv_sec = -11_644_473_600

        #expect(FileIdentity(late) != FileIdentity(early))
        #expect(FileIdentity(late) == FileIdentity(late))
        #expect(FileIdentity(late).modificationDate == Date(timeIntervalSince1970: 10_000_000_000.000000005))
    }

    /// A name that may not move leaves the file to its next name, and a group left with one file is no group. A name
    /// the guard refuses because it syncs to other devices is kept, held back: the group shows it and never moves it.
    @Test func asksWhetherAFileMayMoveOnlyOnceItsBytesMatchAnother() throws {
        let directory = try TemporaryDirectory()
        for name in ["a", "b", "refused", "other", "alone", "partner", "synced", "twin"] {
            try directory.file("files/\(name)", contents: randomData(count: 10))
        }
        try FileManager.default.linkItem(at: directory.url.appending(path: "files/refused"), to: directory.url.appending(path: "files/linked"))
        func candidate(_ name: String) throws -> DuplicateFinder.Candidate {
            let url = directory.url.appending(path: "files/\(name)")
            var info = stat()
            try #require(lstat(url.path(percentEncoded: false), &info) == 0)
            return DuplicateFinder.Candidate(url: url, identity: FileIdentity(info))
        }
        let digest = try #require(ContentDigest(bytes: [UInt8](repeating: 7, count: 32)))
        let refused = try candidate("refused")
        let groups: [[DuplicateFinder.HashedCandidate]] = [
            [(try candidate("a"), digest), (try candidate("b"), digest)],
            [(refused, digest), (try candidate("other"), digest)],
            [(try candidate("alone"), digest), (try candidate("partner"), digest)],
            [(try candidate("synced"), digest), (try candidate("twin"), digest)],
        ]

        var asked: [String] = []
        let movable = try DuplicateFinder.movable(
            groups,
            names: [refused.identity.link: [refused, try candidate("linked")]],
            refusal: { url in
                asked.append(url.lastPathComponent)
                switch url.lastPathComponent {
                case "refused", "partner": return .protectedLocation
                case "synced": return .inTheCloud
                default: return nil
                }
            },
            syncsToOtherDevices: { $0.lastPathComponent == "synced" }
        )

        #expect(asked == ["a", "b", "refused", "linked", "other", "alone", "partner", "synced", "twin"])
        #expect(movable.map { $0.map(\.item.url.lastPathComponent) } == [["a", "b"], ["linked", "other"], ["synced", "twin"]])
        #expect(movable[2].map(\.item.heldBack) == [.inTheCloud, nil])
    }

    @Test func groupsFilesWithIdenticalContents() async throws {
        let directory = try TemporaryDirectory()
        let photo = randomData(count: 4_000)
        try directory.file("home/Pictures/photo.jpg", contents: photo)
        try directory.file("home/Documents/photo copy.jpg", contents: photo)
        try directory.file("home/Documents/other.jpg", contents: randomData(count: 4_000))
        try directory.file("home/Desktop/note.txt", contents: Data("hello".utf8))
        try directory.file("home/Documents/note.txt", contents: Data("hello".utf8))

        let result = try await scan(directory)

        #expect(Set(names(result)) == [["Pictures/photo.jpg", "Documents/photo copy.jpg"], ["Desktop/note.txt", "Documents/note.txt"]])
        #expect(result.suggestedSelection.map(\.lastPathComponent).sorted() == ["note.txt", "photo copy.jpg"])
        #expect(result.groups.allSatisfy { !$0.holdsASyncedCopy })
    }

    /// Copies with the same bytes are duplicates whatever their Finder tags or resource fork. Moving a copy takes
    /// them with it, so a copy with what the others lack stays and the others may all go. Folders that differ in
    /// them still aren't copies of each other, since a folder moves whole.
    @Test func aCopyWithTagsOrAForkTheOthersLackStays() async throws {
        let directory = try TemporaryDirectory()
        let contract = randomData(count: 4_000)
        try directory.file("home/Documents/Contract.pdf", contents: contract)
        var tagged = try directory.file("home/Desktop/Contract.pdf", contents: contract)
        try directory.file("home/Downloads/Contract.pdf", contents: contract)
        let sound = randomData(count: 4_000)
        let forked = try directory.file("home/Music/sound.aiff", contents: sound)
        try directory.file("home/Documents/sound.aiff", contents: sound)
        let notes = randomData(count: 4_000)
        try directory.file("home/Projects/a/notes.txt", contents: notes)
        var taggedInside = try directory.file("home/Projects/b/notes.txt", contents: notes)
        var red = URLResourceValues()
        red.tagNames = ["Red"]
        try tagged.setResourceValues(red)
        try taggedInside.setResourceValues(red)
        let fork = Data(randomData(count: 64))
        let written = fork.withUnsafeBytes {
            setxattr(forked.path(percentEncoded: false), "com.apple.ResourceFork", $0.baseAddress, fork.count, 0, 0)
        }
        #expect(written == 0)

        let result = try await scan(directory)

        let name = { (url: URL) in url.pathComponents.drop { $0 != "home" }.dropFirst().joined(separator: "/") }
        #expect(Set(names(result)) == [
            ["Documents/Contract.pdf", "Desktop/Contract.pdf", "Downloads/Contract.pdf"],
            ["Music/sound.aiff", "Documents/sound.aiff"], ["Projects/a/notes.txt", "Projects/b/notes.txt"],
        ])
        let staying = result.groups.flatMap(\.files).filter { $0.heldBack == .keepsWhatTheOthersLack }.map(\.url)
        #expect(Set(staying.map(name)) == ["Desktop/Contract.pdf", "Music/sound.aiff", "Projects/b/notes.txt"])
        #expect(Set(result.suggestedSelection.map(name)) == [
            "Documents/Contract.pdf", "Downloads/Contract.pdf", "Documents/sound.aiff", "Projects/a/notes.txt",
        ])
        #expect(result.folderGroups.isEmpty)
    }

    /// The Finder keeps a comment in the copy's extended attributes, so it goes with the copy, as tags do. Copies
    /// that each have something the others lack all stay, so nothing could go and they aren't listed.
    @Test func aCopyWithAFinderCommentTheOthersLackStays() async throws {
        let directory = try TemporaryDirectory()
        let report = randomData(count: 4_000)
        try directory.file("home/Documents/Report.pdf", contents: report)
        let commented = try directory.file("home/Desktop/Report.pdf", contents: report)
        let memo = randomData(count: 4_000)
        var blue = try directory.file("home/Documents/Memo.pdf", contents: memo)
        var green = try directory.file("home/Downloads/Memo.pdf", contents: memo)
        var tags = URLResourceValues()
        tags.tagNames = ["Blue"]
        try blue.setResourceValues(tags)
        tags.tagNames = ["Green"]
        try green.setResourceValues(tags)
        let comment = try PropertyListSerialization.data(fromPropertyList: "Signed copy", format: .binary, options: 0)
        let written = comment.withUnsafeBytes {
            setxattr(
                commented.path(percentEncoded: false), "com.apple.metadata:kMDItemFinderComment", $0.baseAddress,
                comment.count, 0, 0
            )
        }
        #expect(written == 0)

        let result = try await scan(directory)

        #expect(names(result) == [["Documents/Report.pdf", "Desktop/Report.pdf"]])
        #expect(result.groups.first?.files.last?.heldBack == .keepsWhatTheOthersLack)
        #expect(result.suggestedSelection.map(\.lastPathComponent) == ["Report.pdf"])
    }

    /// Duplicates scans again only when asked, so what is excluded after a scan is taken out of it: the copy
    /// leaves its group, a group left with one copy goes, and a group that lost its kept copy keeps the next one.
    @Test func whatIsExcludedAfterTheScanLeavesIt() async throws {
        let directory = try TemporaryDirectory()
        let photo = randomData(count: 4_000)
        try directory.file("home/Pictures/photo.jpg", contents: photo)
        try directory.file("home/Documents/photo copy.jpg", contents: photo)
        try directory.file("home/Desktop/photo copy 2.jpg", contents: photo)
        try directory.file("home/Desktop/Notes/note.txt", contents: Data("hello".utf8))
        try directory.file("home/Documents/note.txt", contents: Data("hello".utf8))
        let result = try await scan(directory)
        let photos = try #require(result.groups.first { $0.files.count == 3 }).files.map(\.url)
        let note = try #require(
            result.groups.flatMap(\.files).first { $0.url.path(percentEncoded: false).contains("/Notes/") }
        ).url

        let excluded = await result.excluded(by: Exclusions(paths: [photos[0], note.deletingLastPathComponent()]))
        let remaining = result.removing(excluded)

        #expect(excluded == [photos[0], note])
        #expect(remaining.groups.map { $0.files.map(\.url) } == [Array(photos.dropFirst())])
        #expect(remaining.keepingOneOfEach(result.suggestedSelection) == [photos[2]])
        #expect(remaining.keepingOneOfEach([photos[1]]) == [photos[1]])
        #expect(await result.excluded(by: .none).isEmpty)
    }

    @Test func whatAnAppExcludedAfterTheScanKeepsInItsOwnFolderLeavesIt() async throws {
        let directory = try TemporaryDirectory()
        let photo = randomData(count: 4_000)
        try directory.file("home/Pictures/photo.jpg", contents: photo)
        try directory.file("home/Documents/org.example.Notes/photo.jpg", contents: photo)
        let result = try await scan(directory)
        let kept = try #require(
            result.groups.flatMap(\.files).first { $0.url.path(percentEncoded: false).contains("org.example.Notes") }
        ).url

        #expect(await result.excluded(by: Exclusions(bundleIdentifiers: ["org.example.Notes"])) == [kept])
    }

    /// A folder locked by ordinary file permissions is not one Full Disk Access would open, so the scan does not
    /// ask for it. Only macOS's privacy refusal does, and a test cannot stage that.
    @Test(.permissionsHold) func aFolderLockedByPermissionsDoesNotAskForFullDiskAccess() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Documents/locked/inside.txt", contents: Data("hello".utf8))
        try directory.setPermissions(0o000, of: "home/Documents/locked")
        defer { try? directory.setPermissions(0o755, of: "home/Documents/locked") }

        let result = try await scan(directory)

        #expect(result.unreadableLocations.map(\.lastPathComponent) == ["locked"])
        #expect(!result.needsFullDiskAccess)
    }

    @Test func comparesWholeContentsBeyondTheSamples() async throws {
        let directory = try TemporaryDirectory()
        let length = FileDigest.sampleLength * 4
        var contents = randomData(count: length)
        try directory.file("home/Documents/a.bin", contents: contents)
        try directory.file("home/Documents/b.bin", contents: contents)
        contents[length / 2] &+= 1
        try directory.file("home/Documents/c.bin", contents: contents)

        #expect(names(try await scan(directory)) == [["Documents/a.bin", "Documents/b.bin"]])
    }

    /// Dotfiles kept in a repository at the top of the home folder make no folder inside it a repository's.
    @Test func aRepositoryOfTheHomeFolderLeavesItsFoldersToScan() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 3_000)
        try directory.file("home/.git/HEAD")
        try directory.file("home/Documents/a.bin", contents: contents)
        try directory.file("home/Documents/b.bin", contents: contents)

        let found = try await scan(directory, folders: ["home/Documents"])

        #expect(found.skippedLocations.isEmpty)
        #expect(names(found) == [["Documents/a.bin", "Documents/b.bin"]])
    }

    /// A repository is left alone whether it is the chosen folder or holds it. The walk never yields the chosen
    /// folder itself, so that case is checked on its own.
    @Test func leavesAloneAFolderThatIsOrIsInsideARepository() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 3_000)
        try directory.file("home/Developer/Thing/.git/HEAD")
        try directory.file("home/Developer/Thing/assets/a.bin", contents: contents)
        try directory.file("home/Developer/Thing/assets/b.bin", contents: contents)

        let root = try await scan(directory, folders: ["home/Developer/Thing"])
        #expect(root.groups.isEmpty)
        #expect(root.skippedLocations.map(\.reason) == [.insideARepository])
        #expect(root.readNothing)

        let inside = try await scan(directory, folders: ["home/Developer/Thing/assets"])
        #expect(inside.groups.isEmpty, "a folder inside a repository was scanned")
    }

    @Test func countsOnlyTheGroupsWithSomethingToMove() async throws {
        let directory = try TemporaryDirectory()
        let synced = randomData(count: 3_000)
        let local = randomData(count: 3_000)
        try directory.directory("home/Synced/.stfolder")
        try directory.file("home/Synced/a.bin", contents: synced)
        try directory.file("home/Documents/a.bin", contents: synced)
        try directory.file("home/Documents/b.bin", contents: local)
        try directory.file("home/Documents/b copy.bin", contents: local)

        let scan = try await scan(directory, folders: ["home/Synced", "home/Documents"])

        #expect(scan.groups.count == 2)
        #expect(scan.groupsWithSomethingToMove == 1)
    }

    /// A folder that syncs to other devices is scanned, and each copy found in it is listed and held back: a copy
    /// moved there would be removed from every device. Nothing in such a group is suggested, since the one copy that
    /// could move is the only one that stays on this Mac.
    @Test func listsACopyThatSyncsApartAndNeverSelectsIt() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 3_000)
        try directory.directory("home/Synced/.stfolder")
        try directory.file("home/Synced/a.bin", contents: contents)
        try directory.file("home/Documents/a.bin", contents: contents)

        let scan = try await scan(directory, folders: ["home/Synced", "home/Documents"])
        let group = try #require(scan.groups.first)

        #expect(scan.skippedLocations.isEmpty)
        let synced = try #require(group.files.first { $0.url.pathComponents.contains("Synced") })
        let local = try #require(group.files.first { $0.url.pathComponents.contains("Documents") })
        #expect(synced.heldBack == .inTheCloud)
        #expect(local.heldBack == nil)
        #expect(!group.everyCopySyncs)
        #expect(group.holdsASyncedCopy)
        #expect(group.movableFiles.map(\.url) == [local.url])
        #expect(group.reclaimableSize == 0)
        #expect(scan.suggestedSelection.isEmpty)
        #expect(!DuplicateScan.canChange(synced, in: group, selected: []))
        #expect(DuplicateScan.canChange(local, in: group, selected: []))
    }

    @Test func aCopyInADropboxFolderOutsideFileProviderIsHeldBack() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 3_000)
        try directory.directory("home/Dropbox/.dropbox.cache")
        try directory.file("home/Dropbox/Shared/plan.bin", contents: contents)
        try directory.file("home/Documents/plan.bin", contents: contents)

        let scan = try await scan(directory, folders: ["home/Dropbox", "home/Documents"])
        let group = try #require(scan.groups.first)

        #expect(group.files.first { $0.url.pathComponents.contains("Dropbox") }?.heldBack == .inTheCloud)
        #expect(scan.suggestedSelection.isEmpty)
    }

    /// A group whose every copy syncs is listed too, under its own heading in the app, with nothing to free.
    @Test func listsAGroupWhoseEveryCopySyncs() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 3_000)
        try directory.directory("home/.stfolder")
        try directory.file("home/Desktop/a.bin", contents: contents)
        try directory.file("home/Documents/a.bin", contents: contents)

        let scan = try await scan(directory, folders: ["home/Desktop", "home/Documents"])
        let group = try #require(scan.groups.first)

        #expect(scan.skippedLocations.isEmpty)
        #expect(group.files.count == 2)
        #expect(group.everyCopySyncs)
        #expect(group.holdsASyncedCopy)
        #expect(group.movableFiles.isEmpty)
        #expect(group.reclaimableSize == 0)
        #expect(scan.suggestedSelection.isEmpty)
    }

    /// A chosen folder that is not there, as a folder on a disk that isn't connected, is named rather than passed over.
    @Test func namesAChosenFolderThatIsNotThere() async throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home")

        let scan = try await scan(directory, folders: ["home/Gone"])

        #expect(scan.skippedLocations.map(\.reason) == [.notAFolder])
        #expect(scan.readNothing)
    }

    /// Copies found elsewhere do not hide a chosen folder Peel did not look in: the page still names it.
    @Test func namesTheFoldersItDidNotLookInBesideWhatItFound() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 3_000)
        try directory.file("home/Developer/Thing/.git/HEAD")
        try directory.file("home/Documents/a.bin", contents: contents)
        try directory.file("home/Documents/b.bin", contents: contents)

        let found = try await scan(directory, folders: ["home/Developer/Thing", "home/Documents"])

        #expect(!found.groups.isEmpty)
        #expect(!found.readNothing)
        #expect(found.notLookedIn.map(\.lastPathComponent) == ["Thing"])
    }

    /// A project is left alone like a repository, even without one: it is known by its build file.
    @Test func leavesAloneAProjectKnownByItsBuildFile() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 3_000)
        try directory.file("home/Documents/Site/package.json")
        try directory.file("home/Documents/Site/assets/logo.bin", contents: contents)
        try directory.directory("home/Documents/App/App.xcodeproj")
        try directory.file("home/Documents/App/logo.bin", contents: contents)
        try directory.file("home/Pictures/logo.bin", contents: contents)
        try directory.file("home/Pictures/logo copy.bin", contents: contents)

        let found = names(try await scan(directory)).map { $0.sorted() }

        #expect(found == [["Pictures/logo copy.bin", "Pictures/logo.bin"]])
    }

    /// A stray build file makes no project of what was chosen, of the home folder, or of a folder every account
    /// starts with.
    @Test func aStrayBuildFileSkipsNothingThatWasChosen() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 3_000)
        try directory.file("home/package.json", contents: randomData(count: 20))
        try directory.file("home/Desktop/package.json", contents: randomData(count: 30))
        try directory.file("home/Desktop/a.bin", contents: contents)
        try directory.file("home/Desktop/b.bin", contents: contents)
        try directory.file("home/Stuff/requirements.txt")
        try directory.file("home/Stuff/c.bin", contents: contents)
        try directory.file("home/Stuff/d.bin", contents: contents)

        let home = names(try await scan(directory)).map { $0.sorted() }
        let stuff = names(try await scan(directory, folders: ["home/Stuff"])).map { $0.sorted() }

        #expect(home == [["Desktop/a.bin", "Desktop/b.bin"]])
        #expect(stuff == [["Stuff/c.bin", "Stuff/d.bin"]])
    }

    /// Between the listing and the read, a path can become a pipe. Opened without `O_NONBLOCK`, it would wait
    /// forever for a writer, and Stop could not interrupt it.
    @Test func doesNotWaitForeverOnAPipeWhereAFileWas() async throws {
        let directory = try TemporaryDirectory()
        let url = try directory.file("home/Documents/a.bin", bytes: 4_000)
        let identity = try #require(FileIdentity.of(url))
        try FileManager.default.removeItem(at: url)
        try #require(mkfifo(url.path(percentEncoded: false), 0o644) == 0)

        let read = await withCheckedContinuation { continuation in
            Thread.detachNewThread { continuation.resume(returning: FileDigest.full(of: url, identity: identity)) }
        }

        #expect(read == nil)
    }

    /// Mercurial and Subversion keep their store the same way git does.
    @Test func knowsEveryKindOfRepository() throws {
        let directory = try TemporaryDirectory()
        for mark in [".git", ".hg", ".svn"] {
            try directory.file("repo\(mark)/\(mark)/marker")
            #expect(DuplicateFinder.isRepository(directory.url.appending(path: "repo\(mark)")))
        }
        #expect(!DuplicateFinder.isRepository(try directory.directory("plain")))
    }

    @Test func leavesOutLinksPackagesHiddenFilesProjectsAndAppData() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 2_000)
        let original = try directory.file("home/Documents/original.bin", contents: contents)
        try directory.file("home/Pictures/copy.bin", contents: contents)
        let paths = [
            "home/Documents/.hidden/copy.bin",
            "home/Documents/Tool.app/Contents/copy.bin",
            "home/Documents/web/node_modules/package/copy.bin",
            "home/Documents/repository/copy.bin",
            "home/Library/Caches/copy.bin",
            "home/Music/Music/Media/copy.bin",
        ]
        for path in paths {
            try directory.file(path, contents: contents)
        }
        try directory.directory("home/Documents/repository/.git")
        try FileManager.default.linkItem(at: original, to: directory.url.appending(path: "home/Documents/hard link.bin"))
        try FileManager.default.createSymbolicLink(at: directory.url.appending(path: "home/Documents/symbolic link.bin"), withDestinationURL: original)
        try directory.file("home/Documents/empty-a", contents: Data())
        try directory.file("home/Documents/empty-b", contents: Data())

        let result = try await scan(directory)

        #expect(result.groups.count == 1)
        #expect(result.groups.first?.files.count == 2)
        #expect(
            result.groups.first?.files.contains {
                $0.url.lastPathComponent == "copy.bin" && $0.url.path(percentEncoded: false).contains("/home/Pictures/")
            } == true
        )
        #expect(result.folderGroups.map { $0.folders.map(\.url.lastPathComponent) } == [])
    }

    @Test func filtersByKindAndMinimumSize() async throws {
        let directory = try TemporaryDirectory()
        let image = randomData(count: 10_000)
        let text = Data("same text".utf8)
        try directory.file("home/Pictures/a.png", contents: image)
        try directory.file("home/Pictures/b.png", contents: image)
        try directory.file("home/Documents/a.txt", contents: text)
        try directory.file("home/Documents/b.txt", contents: text)

        let images = try await scan(directory) { $0.kind = .images }
        let large = try await scan(directory) { $0.minimumSize = 1_000 }

        #expect(names(images) == [["Pictures/a.png", "Pictures/b.png"]])
        #expect(names(large) == [["Pictures/a.png", "Pictures/b.png"]])
    }

    @Test func suggestsKeepingTheOriginalCopy() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 3_000)
        try directory.file("home/Downloads/report.pdf", contents: contents)
        try directory.file("home/Documents/report (1).pdf", contents: contents)
        try directory.file("home/Documents/Archive/report.pdf", contents: contents)

        let files = try #require(try await scan(directory).groups.first).files

        #expect(files.first?.url.path(percentEncoded: false).hasSuffix("Documents/Archive/report.pdf") == true)
        #expect(files.last?.url.path(percentEncoded: false).hasSuffix("Downloads/report.pdf") == true)
    }

    @Test func prefersTheShorterNameWhenCopiesAreOtherwiseAlike() async throws {
        let directory = try TemporaryDirectory()
        let original = try directory.file("home/Movies/clip.mov", contents: randomData(count: 3_000))
        let clone = directory.url.appending(path: "home/Movies/clip clone.mov")
        #expect(clonefile(original.path(percentEncoded: false), clone.path(percentEncoded: false), 0) == 0)

        #expect(names(try await scan(directory)) == [["Movies/clip.mov", "Movies/clip clone.mov"]])
    }

    @Test func recognizesCopySuffixes() {
        #expect(DuplicateFinder.hasCopySuffix("Invoice copy"))
        #expect(DuplicateFinder.hasCopySuffix("Invoice Copy 2"))
        #expect(DuplicateFinder.hasCopySuffix("Invoice (3)"))
        #expect(DuplicateFinder.hasCopySuffix("Invoice 2"))
        #expect(DuplicateFinder.hasCopySuffix("Factură copie"))
        #expect(DuplicateFinder.hasCopySuffix("Rechnung Kopie"))
        #expect(!DuplicateFinder.hasCopySuffix("Invoice 2024"))
        #expect(!DuplicateFinder.hasCopySuffix("Copywriting"))
        #expect(DuplicateFinder.hasCopySuffix("Invoice copy 123"))
        #expect(DuplicateFinder.hasCopySuffix("Invoice COPY"))
        #expect(DuplicateFinder.hasCopySuffix("Отчёт копия 2"))
        #expect(DuplicateFinder.hasCopySuffix("Invoice (12345)"))
        #expect(!DuplicateFinder.hasCopySuffix("Invoice copy "))
        #expect(!DuplicateFinder.hasCopySuffix("(3)"))
        #expect(!DuplicateFinder.hasCopySuffix("copy"))
        #expect(!DuplicateFinder.hasCopySuffix("Invoice (3a)"))
    }

    /// `hasCopySuffix` is asked once for every file in every group, so it has to stay fast on a large scan.
    @Test func recognizesCopySuffixesQuickly() {
        var copies = 0
        let took = processorTime {
            for index in 0..<20_000 where DuplicateFinder.hasCopySuffix("small-\(index) copy") {
                copies += 1
            }
        }
        #expect(copies == 20_000)
        #expect(took < .seconds(1))
    }

    @Test func scansOnlyUserContentFolders() throws {
        let directory = try TemporaryDirectory()
        let home = try directory.directory("home")
        for path in ["Documents", "Library/Application Support", "Library/Mobile Documents/com~apple~CloudDocs/Photos", "Library/CloudStorage/Dropbox", "Music/Music"] {
            try directory.directory("home/" + path)
        }
        let finder = DuplicateFinder(homeDirectory: home)

        #expect(finder.canScan(home))
        #expect(finder.canScan(home.appending(path: "Documents")))
        // A file removed from iCloud Drive is removed from every device: scanned, its copies are held back.
        #expect(finder.canScan(home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Photos")))
        #expect(finder.canScan(home.appending(path: "Library/CloudStorage/Dropbox")))
        #expect(!finder.canScan(home.appending(path: "Library")))
        #expect(!finder.canScan(home.appending(path: "Library/Application Support")))
        #expect(!finder.canScan(home.appending(path: "Music/Music")))
        #expect(!finder.canScan(URL(filePath: "/")))
        #expect(!finder.canScan(URL(filePath: "/Applications")))
        #expect(!finder.canScan(URL(filePath: "/System/Library")))
        #expect(!finder.canScan(URL(filePath: "/Volumes/")))
    }

    /// Each refusal says why, so a chosen folder Peel won't scan is named with its reason rather than counted as a
    /// folder it couldn't read.
    @Test func saysWhyAFolderIsNotScanned() throws {
        let directory = try TemporaryDirectory()
        let home = try directory.directory("home")
        for path in ["Documents", "Library", "Music/Music", "Pictures/Thing.app", "Synced/.stfolder"] {
            try directory.directory("home/" + path)
        }
        let finder = DuplicateFinder(homeDirectory: home)

        #expect(finder.refusal(of: home.appending(path: "Documents")) == nil)
        // A folder that syncs is scanned; what is found in it is held back, never moved.
        #expect(finder.refusal(of: home.appending(path: "Synced")) == nil)
        #expect(finder.refusal(of: home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs")) == nil)
        #expect(finder.refusal(of: home.appending(path: "Library/CloudStorage/Dropbox")) == nil)
        #expect(finder.refusal(of: home.appending(path: "Library")) == .appData)
        #expect(finder.refusal(of: home.appending(path: "Music/Music")) == .appData)
        #expect(finder.refusal(of: home.appending(path: "Pictures/Thing.app")) == .inAPackage)
        #expect(finder.refusal(of: URL(filePath: "/")) == .outsideTheHome)
        #expect(finder.refusal(of: URL(filePath: "/Applications")) == .outsideTheHome)
    }

    @Test func refusesTheTrashOfEveryDisk() throws {
        let directory = try TemporaryDirectory()
        let home = try directory.directory("home")
        let finder = DuplicateFinder(homeDirectory: home)

        #expect(!finder.canScan(URL(filePath: "/Volumes/Backup/.Trashes/501", directoryHint: .isDirectory)))
        #expect(!finder.canScan(URL(filePath: "/Volumes/Backup/.Trashes", directoryHint: .isDirectory)))
        #expect(!finder.canScan(home.appending(path: ".Trash", directoryHint: .isDirectory)))
        #expect(finder.canScan(URL(filePath: "/Volumes/Backup/Work", directoryHint: .isDirectory)))
    }


    /// A folder a sync app keeps in step is scanned like any other; what is found in it is held back, never moved.
    @Test func scansAFolderASyncAppKeepsInStep() throws {
        let directory = try TemporaryDirectory()
        let home = try directory.directory("home")
        try directory.directory("home/Sync/.stfolder")
        try directory.directory("home/Sync/Photos")
        try directory.directory("home/Documents")
        let finder = DuplicateFinder(homeDirectory: home)

        #expect(finder.canScan(home.appending(path: "Sync", directoryHint: .isDirectory)))
        #expect(finder.canScan(home.appending(path: "Sync/Photos", directoryHint: .isDirectory)))
        #expect(finder.canScan(home.appending(path: "Documents", directoryHint: .isDirectory)))
    }

    @Test func aFolderSpelledInAnotherCaseIsJudgedAsTheDiskSpellsIt() throws {
        let directory = try TemporaryDirectory()
        let volume = try ScratchVolume(
            fileSystem: "APFS", mountedAt: directory.url.appending(path: "Disk", directoryHint: .isDirectory)
        )
        let home = volume.url.appending(path: "home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: home.appending(path: "Library/Application Support"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: home.appending(path: "Music/Music"), withIntermediateDirectories: true)
        let finder = DuplicateFinder(homeDirectory: home)

        for path in ["library", "LIBRARY/application support", "music/MUSIC"] {
            let url = home.appending(path: path)
            try #require(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)), "this disk does not fold \(path)")
            #expect(!finder.canScan(url), "\(path) was offered")
        }
    }

    /// The copy on the disk the home folder is on is kept before an older one on another disk, such as photos that
    /// were on a card before they were on the Mac.
    @Test func keepsTheCopyOnTheHomeDisk() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let volume = try ScratchVolume(
            fileSystem: "APFS", mountedAt: home.appending(path: "Card", directoryHint: .isDirectory)
        )
        let contents = Data(repeating: 7, count: 200_000)
        let onTheMac = try directory.file("home/Pictures/Holiday/photo.jpg", contents: contents)
        let onTheCard = volume.url.appending(path: "Holiday/photo.jpg")
        try FileManager.default.createDirectory(
            at: onTheCard.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try contents.write(to: onTheCard)
        let earlier = Date.now.addingTimeInterval(-2 * 24 * 3_600)
        for url in [onTheCard, onTheCard.deletingLastPathComponent()] {
            try FileManager.default.setAttributes(
                [.creationDate: earlier, .modificationDate: earlier], ofItemAtPath: url.path(percentEncoded: false)
            )
        }

        let pictures = home.appending(path: "Pictures", directoryHint: .isDirectory)
        let finder = DuplicateFinder(homeDirectory: home)
        let kept = { (url: URL?) in url.map { PathPattern.comparablePath(of: $0) } }

        let folders = try await finder.scan(.everySize(in: [pictures, volume.url]))
        #expect(kept(folders.folderGroups.first?.folders.first?.url) == kept(onTheMac.deletingLastPathComponent()))

        try directory.file("home/Pictures/Holiday/notes.txt", contents: Data("only here".utf8))
        let files = try await finder.scan(.everySize(in: [pictures, volume.url]))
        #expect(kept(files.groups.first?.files.first?.url) == kept(onTheMac))
    }

    /// Select Recommended and Deselect All change only the groups they are asked about, which a search narrows:
    /// what is selected in the others stays.
    @Test func selectsWhatItRecommendsOnlyInTheGroupsShown() async throws {
        let directory = try TemporaryDirectory()
        let first = randomData(count: 4_000)
        let second = randomData(count: 4_000)
        for name in ["a", "b", "c"] {
            try directory.file("home/Documents/first-\(name).bin", contents: first)
            try directory.file("home/Pictures/second-\(name).bin", contents: second)
        }
        let result = try await scan(directory)
        let shown = try #require(result.groups.first { $0.files.first?.url.lastPathComponent.hasPrefix("first") == true })
        let other = try #require(result.groups.first { $0 != shown })
        let otherSelected = Set(other.files.map(\.url))

        let recommended = result.selectingRecommended(in: [shown], [], files: otherSelected, folders: [])
        #expect(recommended.files == otherSelected.union(shown.suggestedFiles.map(\.url)))
        #expect(shown.suggestedFiles.count == 2)

        let none = result.deselecting([shown], [], files: recommended.files, folders: [])
        #expect(none.files == otherSelected)
    }

    @Test func stopsWhenCanceled() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Documents/a.txt", contents: Data("same".utf8))
        try directory.file("home/Documents/b.txt", contents: Data("same".utf8))
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let options = DuplicateScanOptions.everySize(in: [home])

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await DuplicateFinder(homeDirectory: home).scan(options)
        }

        await #expect(throws: CancellationError.self) { try await task.value }
    }

    /// A file that may share blocks with a clone frees only its private size. Any other frees every block it takes,
    /// since what a snapshot keeps of it comes back once macOS deletes the snapshot. A snapshot can't be made in a
    /// test, so the rule is asked with what `getattrlist(2)` would say of such a file.
    @Test func aFileThatSharesNoBlockFreesEveryBlockItTakes() {
        let freed = { (privateSize: Int64?, mayBeShared: Bool?, isCompressed: Bool) in
            ReclaimableSpace.freed(
                allocated: 4_096_000, privateSize: privateSize, mayBeShared: mayBeShared, isCompressed: isCompressed
            )
        }
        #expect(freed(0, false, false) == 4_096_000, "kept by a snapshot")
        #expect(freed(nil, nil, false) == 4_096_000)
        #expect(freed(1_000, true, false) == 1_000, "cloned")
        #expect(freed(0, true, true) == 0, "compressed and cloned")
        #expect(freed(0, false, true) == 4_096_000, "compressed")
    }

    @Test func reportsSpaceThatClonesAndHardLinksDoNotFree() throws {
        let directory = try TemporaryDirectory()
        let original = try directory.file("original.bin", contents: randomData(count: 1_048_576))
        let handle = try FileHandle(forWritingTo: original)
        try handle.synchronize()
        try handle.close()
        let clone = directory.url.appending(path: "clone.bin")
        #expect(clonefile(original.path(percentEncoded: false), clone.path(percentEncoded: false), 0) == 0)

        #expect(ReclaimableSpace.of(clone) < 1_048_576 / 2)

        let separate = try directory.file("separate.bin", contents: randomData(count: 1_048_576))
        let separateHandle = try FileHandle(forWritingTo: separate)
        try separateHandle.synchronize()
        try separateHandle.close()
        #expect(ReclaimableSpace.of(separate) >= 1_048_576)

        try FileManager.default.linkItem(at: separate, to: directory.url.appending(path: "link.bin"))
        #expect(ReclaimableSpace.of(separate) == 0)
    }

    /// What a row promises to free is the file's blocks on the disk, never the length it claims. On APFS, a file
    /// made only of holes, like an empty disk image, takes no blocks, so it promises nothing.
    @Test func promisesNothingForAFileMadeOfHoles() throws {
        let directory = try TemporaryDirectory()
        let url = try directory.file("holes.img", bytes: 0)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 100 * 1_048_576)
        try handle.close()

        #expect((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) == 100 * 1_048_576)
        #expect(ReclaimableSpace.of(url) == 0)
        #expect(ReclaimableSpace.allocated(url) == 0)
    }

    /// The smallest size is a floor on what removing a copy frees, which for a file made of holes is its blocks.
    /// Two empty disk images of 100 MB each take none, so they are not listed.
    @Test func filesMadeOfHolesAreNoDuplicates() async throws {
        let directory = try TemporaryDirectory()
        for name in ["home/Documents/first.img", "home/Documents/second.img"] {
            let url = try directory.file(name, bytes: 0)
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: 100 * 1_048_576)
            try handle.close()
        }
        try directory.file("home/Documents/kept.bin", contents: randomData(count: 200_000))
        try directory.file("home/Documents/kept copy.bin", contents: try Data(contentsOf: directory.url.appending(path: "home/Documents/kept.bin")))

        let result = try await scan(directory) { $0.minimumSize = 100_000 }

        #expect(names(result) == [["Documents/kept.bin", "Documents/kept copy.bin"]])
    }

    /// Compression is not a hole: a compressed file's blocks hold its bytes written smaller. So the smallest size
    /// weighs a compressed copy by its length.
    @Test func aCompressedFileIsWeighedByItsLength() async throws {
        let directory = try TemporaryDirectory()
        for name in ["home/Documents/notes.txt", "home/Desktop/notes.txt"] {
            let copy = try directory.compressedTextFile(name)
            #expect(ReclaimableSpace.allocated(copy) < 100_000)
        }

        let result = try await scan(directory) { $0.minimumSize = 100_000 }

        #expect(names(result).map(Set.init) == [["Documents/notes.txt", "Desktop/notes.txt"]])
    }

    /// A compressed file keeps its bytes in its resource fork or an extended attribute, which the private size
    /// does not count. A copy never cloned frees every block it takes. Once cloned, it may share them all, so it
    /// is counted as freeing nothing.
    @Test func aCompressedCopyFreesItsBlocksUntilItIsCloned() throws {
        let directory = try TemporaryDirectory()
        let compressed = try directory.compressedTextFile("compressed.txt")
        #expect(ReclaimableSpace.allocated(compressed) > 0)
        #expect(ReclaimableSpace.of(compressed) == ReclaimableSpace.allocated(compressed))

        let clone = directory.url.appending(path: "clone.txt")
        #expect(clonefile(compressed.path(percentEncoded: false), clone.path(percentEncoded: false), 0) == 0)
        #expect(ReclaimableSpace.of(compressed) == 0)
        #expect(ReclaimableSpace.of(clone) == 0)
    }

    /// A USB stick or a card formatted exFAT or FAT can neither clone a file nor keep a snapshot, so its copies share
    /// no block, yet it answers the private size with zero. Removing a copy there frees every block the copy takes.
    @Test(arguments: ["ExFAT", "MS-DOS FAT32"])
    func aCopyOnADiskThatSharesNothingFreesAllItTakes(fileSystem: String) async throws {
        let directory = try TemporaryDirectory()
        let home = try directory.directory("home")
        let volume = try ScratchVolume(
            fileSystem: fileSystem,
            mountedAt: home.appending(path: "Stick", directoryHint: .isDirectory)
        )
        let photo = randomData(count: 1_048_576)
        for (path, contents) in [("one/photo.bin", photo), ("two/photo.bin", photo), ("two/other.bin", randomData(count: 4_096))] {
            let url = volume.url.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url)
        }
        for folder in ["a", "b"] {
            let url = volume.url.appending(path: "\(folder)/scan.bin")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try photo.prefix(524_288).write(to: url)
        }

        let result = try await DuplicateFinder(homeDirectory: home).scan(.everySize(in: [volume.url]))

        let photos = try #require(result.groups.first { $0.files.contains { $0.url.lastPathComponent == "photo.bin" } })
        let copy = try #require(photos.files.last)
        #expect(copy.reclaimableSize == copy.allocatedSize && copy.allocatedSize >= 1_048_576)
        #expect(!copy.sharesStorage)
        let folders = try #require(result.folderGroups.first { $0.folders.contains { $0.url.lastPathComponent == "b" } })
        #expect(folders.reclaimableSize >= 524_288)
    }
}

struct DuplicateRemovalTests {
    private func service(in directory: borrowing TemporaryDirectory) throws -> TrashService {
        let trash = try directory.directory("Trash")
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        return TrashService(environment: environment) { url in
            let destination = trash.appending(path: UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    /// Creates and scans two identical files. The first is the copy Peel suggests keeping.
    private func duplicates(
        in directory: borrowing TemporaryDirectory
    ) async throws -> (scan: DuplicateScan, kept: URL, copy: URL) {
        let contents = Data((0..<5_000).map { _ in UInt8.random(in: 0...255) })
        try directory.file("home/Documents/kept.bin", contents: contents)
        try directory.file("home/Documents/kept copy.bin", contents: contents)
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let scan = try await DuplicateFinder(homeDirectory: home).scan(.everySize(in: [home]))
        let files = try #require(scan.groups.first).files
        #expect(files.map(\.url.lastPathComponent) == ["kept.bin", "kept copy.bin"])
        return (scan, files[0].url, files[1].url)
    }

    @Test func neverTrashesEveryCopy() async throws {
        let directory = try TemporaryDirectory()
        let (scan, kept, copy) = try await duplicates(in: directory)

        let result = await DuplicateRemoval.trash([kept, copy], from: scan, using: try service(in: directory))

        #expect(result.trashed.isEmpty)
        #expect(Set(result.failures.map(\.reason)) == [.lastCopy])
        #expect(FileManager.default.fileExists(atPath: kept.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)))
    }

    @Test func refusesWhenTheKeptCopyChanged() async throws {
        let directory = try TemporaryDirectory()
        let (scan, kept, copy) = try await duplicates(in: directory)
        let handle = try FileHandle(forWritingTo: kept)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([1]))
        try handle.close()

        let result = await DuplicateRemoval.trash([copy], from: scan, using: try service(in: directory))

        #expect(result.trashed.isEmpty)
        #expect(result.failures.map(\.reason) == [.lastCopy])
        #expect(FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)))
    }

    @Test func refusesCopiesChangedSinceTheScan() async throws {
        let directory = try TemporaryDirectory()
        let (scan, _, copy) = try await duplicates(in: directory)
        try Data("changed".utf8).write(to: copy)

        let result = await DuplicateRemoval.trash([copy], from: scan, using: try service(in: directory))

        #expect(result.trashed.isEmpty)
        #expect(result.failures.map(\.reason) == [.changedSinceScan])
    }

    @Test func trashesUnchangedCopies() async throws {
        let directory = try TemporaryDirectory()
        let (scan, kept, copy) = try await duplicates(in: directory)

        let result = await DuplicateRemoval.trash([copy], from: scan, using: try service(in: directory))

        #expect(result.failures.isEmpty)
        #expect(result.trashed.map(\.originalURL) == [copy])
        #expect(FileManager.default.fileExists(atPath: kept.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)))
        #expect(scan.removing([copy]).groups.isEmpty)
    }

    /// While deciding, the user may open the copy Peel suggests keeping or add a tag to it. Each of those changes
    /// its status change time, which must not make removing another copy fail as "last copy".
    @Test func aTagOnTheKeptCopyDoesNotStopTheRemoval() async throws {
        let directory = try TemporaryDirectory()
        let (scan, kept, copy) = try await duplicates(in: directory)

        // What Finder does when a file is tagged, and what a sync client does for its own bookkeeping.
        let value = Data("peel".utf8)
        try #require(
            value.withUnsafeBytes {
                setxattr(kept.path(percentEncoded: false), "com.peel.test", $0.baseAddress, $0.count, 0, 0)
            } == 0
        )

        let result = await DuplicateRemoval.trash([copy], from: scan, using: try service(in: directory))

        #expect(result.failures.isEmpty, "the tagged copy was read as changed")
        #expect(result.trashed.map(\.originalURL) == [copy])
    }

    @Test func movesEveryCopyAsOneRemoval() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        for name in ["one", "two"] {
            let contents = Data((0..<4_000).map { _ in UInt8.random(in: 0...255) })
            try directory.file("home/Documents/\(name).bin", contents: contents)
            try directory.file("home/Documents/\(name) copy.bin", contents: contents)
        }
        let scan = try await DuplicateFinder(homeDirectory: home).scan(.everySize(in: [home]))
        #expect(scan.groups.count == 2)
        let journal = RemovalJournal(beside: home.appending(path: "removals.json"))
        let trash = try directory.directory("Trash")
        let environment = SearchEnvironment(
            homeDirectory: home, rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        let service = TrashService(environment: environment, journal: journal) { url in
            let destination = trash.appending(path: UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }

        let result = await DuplicateRemoval.trash(scan.suggestedSelection, from: scan, using: service)

        #expect(result.trashed.count == 2)
        #expect(result.failures.isEmpty)
        #expect(Set(journal.entries().map(\.batch)).count == 1)
    }
}
