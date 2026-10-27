import Foundation
import Synchronization
@testable import PeelCore
import Testing
import UniformTypeIdentifiers

struct FileSearchTests {
    /// What an app keeps in a Library folder is listed last and never selected by Select All, whatever its name
    /// begins with: to a comparison of characters, a name beginning with a combining mark was outside its folder.
    @Test func whatSitsInALibraryFolderIsAppDataWhateverItsNameBeginsWith() {
        let appData = FileSearch.AppDataFolders(home: URL(filePath: "/Users/x", directoryHint: .isDirectory))

        #expect(appData.holds("/Users/x/Library/\u{301}cache.db"))
        #expect(appData.holds("/Library/\u{301}cache.db"))
        #expect(!appData.holds("/Users/x/Libraryish/cache.db"))
    }

    /// A search is stopped like any scan: it comes back at once and reads nothing more.
    @Test func aStoppedSearchStops() async throws {
        let unanswered = Unanswered()
        var search = FileSearchCriteria()
        search.name = "report"
        let criteria = search

        let stop = try await unanswered.stop {
            _ = await FileSearch.run(criteria, gather: unanswered.gather)
        }

        #expect(stop.took < .seconds(1))
        #expect(stop.askedBefore == 1)
        #expect(stop.askedAfter == 0)
    }

    @Test func anEmptySearchNamesTheDisksSpotlightDoesNotIndex() async throws {
        var criteria = FileSearchCriteria()
        criteria.name = "report"
        let disks = [
            SpotlightIndex.Disk(volume: URL(filePath: "/System/Volumes/Data"), name: "Macintosh HD"),
            SpotlightIndex.Disk(volume: URL(filePath: "/Volumes/Backup"), name: "Backup"),
        ]
        func search(indexing: Set<String>, finding paths: [String] = []) async -> FileSearchResults {
            await FileSearch.run(
                criteria, gather: { _ in paths }, disks: { _ in disks },
                isIndexing: { indexing.contains($0.path) }
            )
        }
        let directory = try TemporaryDirectory()
        let file = try directory.file("report.txt")

        let some = await search(indexing: ["/System/Volumes/Data"])
        let none = await search(indexing: [])
        let every = await search(indexing: ["/System/Volumes/Data", "/Volumes/Backup"])
        let found = await search(indexing: [], finding: [file.path(percentEncoded: false)])

        #expect(some.unindexedDisks == ["Backup"] && !some.isNothingIndexed)
        #expect(none.unindexedDisks == ["Macintosh HD", "Backup"] && none.isNothingIndexed)
        #expect(every.unindexedDisks.isEmpty && !every.isNothingIndexed)
        #expect(found.files.count == 1 && found.unindexedDisks.isEmpty)
    }

    @Test func buildsQueryFromCriteria() {
        var criteria = FileSearchCriteria()
        criteria.name = " Budget "
        criteria.minimumSize = 100_000_000
        criteria.unmodifiedDays = 180
        criteria.kind = .diskImages

        #expect(FileSearch.queryString(for: criteria) == #"kMDItemContentTypeTree != "public.directory" && kMDItemFSName == "*Budget*"cd && kMDItemFSSize >= 100000000 && kMDItemFSContentChangeDate < $time.today(-180) && (kMDItemContentTypeTree == "public.disk-image")"#)
        #expect(FileSearch.makeQuery(for: criteria) != nil)
    }

    /// Spotlight folds case by the Mac's first language, so on a Mac set to Turkish the query `"*iina*"cd` (case
    /// and diacritics ignored) misses IINA.app. Asking for each i-letter as both `i` and `I` matches every
    /// i-letter under either rule.
    @Test func asksForEachILetterInBothCases() throws {
        #expect(FileSearch.nameClause("Budget") == #"kMDItemFSName == "*Budget*"cd"#)
        #expect(FileSearch.nameClause("iina") == #"(kMDItemFSName == "*iina*"cd || kMDItemFSName == "*iIna*"cd || kMDItemFSName == "*Iina*"cd || kMDItemFSName == "*IIna*"cd)"#)
        let turkish = FileSearch.nameClause("kırmızı")
        #expect(turkish.hasPrefix(#"(kMDItemFSName == "*kırmızı*"cd || "#), "the name as typed comes first")
        #expect(turkish.contains(#""*kIrmIzI*"cd"#))
        #expect(FileSearch.nameClause("iiiii") == #"kMDItemFSName == "*iiiii*"cd"#, "past four letters, as typed")
        var criteria = FileSearchCriteria()
        criteria.name = "iina"
        #expect(FileSearch.makeQuery(for: criteria) != nil)
    }

    @Test func documentsLeaveOutSourceCode() {
        var criteria = FileSearchCriteria()
        criteria.kind = .documents

        #expect(FileSearch.queryString(for: criteria) == #"kMDItemContentTypeTree != "public.directory" && ((kMDItemContentTypeTree == "public.composite-content" || kMDItemContentTypeTree == "public.text") && kMDItemContentTypeTree != "public.source-code")"#)
        #expect(FileSearch.makeQuery(for: criteria) != nil)
    }

    @Test func escapesUserTextSoItCannotChangeTheQuery() {
        #expect(FileSearch.escaped(#"a" || kMDItemFSName == "*"#) == #"a\" || kMDItemFSName == \"\*"#)
        #expect(FileSearch.escaped(#"back\slash?"#) == #"back\\slash\?"#)

        var criteria = FileSearchCriteria()
        criteria.name = #"a" || kMDItemFSName == "*\"#
        #expect(FileSearch.makeQuery(for: criteria) != nil)
    }

    @Test func requiresSomethingToNarrowTheSearch() {
        var criteria = FileSearchCriteria()
        #expect(!criteria.isSearchable)
        criteria.unmodifiedDays = 365
        #expect(!criteria.isSearchable)
        criteria.name = "  "
        #expect(!criteria.isSearchable)
        criteria.minimumSize = 1
        #expect(criteria.isSearchable)
    }

    @Test func countsAndClearsTheFiltersThatNarrowTheSearch() {
        var criteria = FileSearchCriteria()
        criteria.name = "report"
        criteria.scope = .computer
        #expect(criteria.narrowingFilters == 0)
        criteria.kind = .movies
        criteria.minimumSize = 1_000_000_000
        criteria.unmodifiedDays = 730
        #expect(criteria.narrowingFilters == 3)

        let cleared = criteria.clearingFilters()
        #expect(cleared.narrowingFilters == 0)
        #expect(cleared.kind == .any && cleared.minimumSize == 0 && cleared.unmodifiedDays == 0)
        #expect(cleared.name == "report" && cleared.scope == .computer)
    }

    @Test func fileKindsMatchContentTypes() throws {
        let docx = try #require(UTType(filenameExtension: "docx"))
        let markdown = try #require(UTType(filenameExtension: "md"))
        let swift = try #require(UTType(filenameExtension: "swift"))
        let dmg = try #require(UTType(filenameExtension: "dmg"))

        #expect(FileKind.documents.includes(docx))
        #expect(FileKind.documents.includes(markdown))
        #expect(!FileKind.documents.includes(swift))
        #expect(!FileKind.documents.includes(.jpeg))
        #expect(FileKind.images.includes(.heic))
        #expect(FileKind.archives.includes(dmg))
        #expect(FileKind.diskImages.includes(dmg))
        #expect(!FileKind.diskImages.includes(.zip))
        #expect(FileKind.any.includes(swift))
    }

    /// Each path Spotlight returns is checked on the disk. Only regular files the removal guard allows are listed,
    /// files an app keeps in a Library folder come last, and the largest come first within each part.
    @Test func listsOnlyRegularFilesOutsideProtectedLocations() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let small = try directory.file("home/Documents/small.png", bytes: 1_000)
        let large = try directory.file("home/Documents/large.png", bytes: 9_000)
        let appData = try directory.file("home/Library/Application Support/Thing/huge.png", bytes: 90_000)
        let folder = try directory.directory("home/Documents/folder.png")
        let keychains = try directory.file("home/Library/Keychains/login.keychain-db", bytes: 4_000)

        let results = FileSearch.results(
            from: [small, large, appData, folder, keychains].map { $0.path(percentEncoded: false) } + ["/nowhere/gone.png"],
            environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url)
        )

        #expect(results.files.map(\.url.lastPathComponent) == ["large.png", "small.png", "huge.png"])
        #expect(results.files.last?.belongsToAnApp == true)
        #expect(!results.isTruncated)
        #expect(results.leftOut == [.protected: 1])
    }

    @Test func moviesLeaveOutTypeScriptThatMacOSTypesAsATransportStream() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let code = try directory.file("home/Projects/app/index.ts", contents: Data("export const answer = 42\n".utf8))
        var packets = [UInt8](repeating: 0xFF, count: 188 * 3)
        for start in stride(from: 0, to: packets.count, by: 188) { packets[start] = 0x47 }
        let clip = try directory.file("home/Movies/clip.ts", contents: Data(packets))
        var blueRay = [UInt8](repeating: 0xFF, count: 192 * 3)
        for start in stride(from: 4, to: blueRay.count, by: 192) { blueRay[start] = 0x47 }
        let recording = try directory.file("home/Movies/recording.ts", contents: Data(blueRay))
        let paths = [code, clip, recording].map { $0.path(percentEncoded: false) }
        let environment = SearchEnvironment(homeDirectory: home, rootDirectory: directory.url)

        let movies = FileSearch.results(from: paths, kind: .movies, environment: environment, refusal: { _ in nil })
        let anything = FileSearch.results(from: paths, kind: .any, environment: environment, refusal: { _ in nil })

        #expect(Set(movies.files.map(\.url.lastPathComponent)) == ["clip.ts", "recording.ts"])
        #expect(Set(anything.files.map(\.url.lastPathComponent)) == ["index.ts", "clip.ts", "recording.ts"])
    }

    @Test func neverListsAFileThatSyncsToTheCloud() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let synced = try directory.file("home/Documents/Report.pdf", bytes: 9_000)
        let local = try directory.file("home/Downloads/Setup.dmg", bytes: 1_000)
        let environment = SearchEnvironment(homeDirectory: home, rootDirectory: directory.url)
        let guardian = RemovalGuard(environment: environment, syncsToOtherDevices: { $0.lastPathComponent == "Report.pdf" })

        let results = FileSearch.results(
            from: [synced, local].map { $0.path(percentEncoded: false) },
            environment: environment,
            refusal: guardian.refusal(of:)
        )

        #expect(results.files.map(\.url.lastPathComponent) == ["Setup.dmg"])
        #expect(results.leftOut == [.syncs: 1])
    }

    @Test func aRefusedFileThatSyncsIsCountedAsSyncing() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let inICloudDrive = try directory.file("home/Library/Mobile Documents/com~apple~CloudDocs/Report.pdf")
        let keychain = try directory.file("home/Library/Keychains/login.keychain-db")

        let results = FileSearch.results(
            from: [inICloudDrive, keychain].map { $0.path(percentEncoded: false) },
            environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url),
            syncsToOtherDevices: { $0.lastPathComponent == "Report.pdf" }
        )

        #expect(results.files.isEmpty)
        #expect(results.leftOut == [.syncs: 1, .protected: 1])
    }

    @Test func aFileOnlyInTheCloudIsCountedAsSyncingAndNeverRead() throws {
        let directory = try TemporaryDirectory()
        var packets = [UInt8](repeating: 0xFF, count: 188 * 3)
        for start in stride(from: 0, to: packets.count, by: 188) { packets[start] = 0x47 }
        let clip = try directory.file("clip.ts", contents: Data(packets))
        var info = stat()
        info.st_mode = S_IFREG
        info.st_flags = UInt32(SF_DATALESS)
        func judged(_ kind: FileKind) -> FileSearch.Judgment {
            FileSearch.judge(clip, info: info, kind: kind, refusal: { _ in nil }, syncsToOtherDevices: { _ in false })
        }

        #expect(judged(.any) == .leftOut(.syncs))
        #expect(judged(.movies) == .skipped)
    }

    @Test func countsWhatItCannotCheckAgainstExclusionsNotYetRead() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let file = try directory.file("home/Documents/kept.png")

        let results = FileSearch.results(
            from: [file.path(percentEncoded: false)],
            environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url),
            exclusions: .notYetRead
        )

        #expect(results.files.isEmpty)
        #expect(results.leftOut == [.exclusionsNotKnown: 1])
    }

    @Test(.permissionsHold) func countsAFileMacOSWouldNotLetItLookAt() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let closed = try directory.file("home/Closed/Report.pdf")
        let gone = directory.url.appending(path: "home/Documents/gone.pdf")
        try directory.setPermissions(0o000, of: "home/Closed")
        defer { try? directory.setPermissions(0o755, of: "home/Closed") }

        let results = FileSearch.results(
            from: [closed, gone].map { $0.path(percentEncoded: false) },
            environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url)
        )

        #expect(results.files.isEmpty)
        #expect(results.leftOut == [.couldNotBeRead: 1])
    }

    /// A file whose contents live only in the cloud (`SF_DATALESS`) takes no room on this Mac, so moving it frees
    /// nothing here and removes it everywhere. It is never listed.
    @Test func aFileOnlyInTheCloudIsNeverListed() {
        var info = stat()
        info.st_mode = S_IFREG
        #expect(FileSearch.holdsItsContentsHere(info))
        info.st_flags = UInt32(SF_DATALESS)
        #expect(!FileSearch.holdsItsContentsHere(info))
    }

    /// `MDQuery.h` promises no order, so the results are sorted before the cap applies. Cutting first would keep
    /// an arbitrary set of files and call them the largest. The guard allows every file here, since the order is
    /// what is checked; `listsOnlyRegularFilesOutsideProtectedLocations` asks the real one.
    @Test func keepsTheLargestFilesWhenThereAreMoreThanTheCap() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        var paths: [String] = []
        for index in 0..<(FileSearch.maximumResults + 5) {
            paths.append(try directory.file("home/Documents/file\(index).png", bytes: 16).path(percentEncoded: false))
        }
        let biggest = try directory.file("home/Documents/zzz-biggest.png", bytes: 40_000)

        let results = FileSearch.results(
            from: paths + [biggest.path(percentEncoded: false)],
            environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url),
            refusal: { _ in nil }
        )

        #expect(results.files.count == FileSearch.maximumResults)
        #expect(results.files.first?.url == biggest)
        #expect(results.isTruncated)
    }

    @Test func countsOnlyWhatTheListHadRoomFor() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        var paths: [String] = []
        for index in 0..<FileSearch.maximumResults {
            paths.append(try directory.file("home/Documents/file\(index).png", bytes: 100).path(percentEncoded: false))
        }
        let bigRefused = try directory.file("home/Documents/refused-big.png", bytes: 1_000)
        let smallRefused = try directory.file("home/Documents/refused-small.png", bytes: 50)
        let last = try directory.file("home/Documents/last.png", bytes: 10)

        let results = FileSearch.results(
            from: paths + [bigRefused, smallRefused, last].map { $0.path(percentEncoded: false) },
            environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url),
            refusal: { $0.lastPathComponent.hasPrefix("refused") ? .protectedLocation : nil },
            syncsToOtherDevices: { _ in false }
        )

        #expect(results.files.count == FileSearch.maximumResults)
        #expect(results.isTruncated)
        #expect(results.leftOut == [.protected: 1])
    }

    /// The guard is asked only about the files that can make the list: the largest first, and no further once
    /// the list is full and one more file shows it had to be cut.
    /// A file's size is what moving it frees, never its length, and the list goes by it: two clones keep the same
    /// blocks, so moving either frees nothing while the other stays.
    @Test func sizesEachFileByWhatMovingItFrees() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let random = { (count: Int) in Data((0..<count).map { _ in UInt8.random(in: 0...255) }) }
        let original = try directory.file("home/Documents/original.mov", contents: random(1_048_576))
        let handle = try FileHandle(forWritingTo: original)
        try handle.synchronize()
        try handle.close()
        let clone = home.appending(path: "Documents/clone.mov")
        try #require(clonefile(original.path(percentEncoded: false), clone.path(percentEncoded: false), 0) == 0)
        let small = try directory.file("home/Documents/small.mov", contents: random(200_000))

        let results = FileSearch.results(
            from: [original, clone, small].map { $0.path(percentEncoded: false) },
            environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url)
        )

        let files = Dictionary(uniqueKeysWithValues: results.files.map { ($0.url.lastPathComponent, $0) })
        #expect(files["clone.mov"]?.length == 1_048_576)
        #expect(try #require(files["clone.mov"]?.size) < 1_048_576 / 2)
        #expect(files["clone.mov"]?.freesLessThanItsLength == true)
        #expect(files["small.mov"]?.freesLessThanItsLength == false)
        #expect(results.files.first?.url.lastPathComponent == "small.mov")
    }

    @Test func asksTheGuardOnlyAboutFilesThatCanMakeTheList() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        var paths: [String] = []
        for index in 0..<(FileSearch.maximumResults + 50) {
            paths.append(try directory.file("home/Documents/file\(index).png", bytes: index + 1).path(percentEncoded: false))
        }
        let asked = Mutex(0)

        let results = FileSearch.results(
            from: paths,
            environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url),
            refusal: { _ in
                asked.withLock { $0 += 1 }
                return nil
            }
        )

        #expect(results.files.count == FileSearch.maximumResults)
        #expect(results.isTruncated)
        #expect(results.files.first?.length == Int64(FileSearch.maximumResults + 50))
        #expect(asked.withLock { $0 } == FileSearch.maximumResults + 1)
    }

    /// An excluded file is never listed, whatever Spotlight says about it.
    @Test func leavesOutWhatTheUserExcluded() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let kept = try directory.file("home/Documents/kept.png", bytes: 1_000)
        let other = try directory.file("home/Documents/other.png", bytes: 1_000)

        let results = FileSearch.results(
            from: [kept, other].map { $0.path(percentEncoded: false) },
            environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url),
            exclusions: Exclusions(paths: [kept])
        )

        #expect(results.files.map(\.url) == [other])
        #expect(results.leftOut == [.excluded: 1])
    }

    @Test func movesTheFilesItListedAsOneRemoval() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let first = try directory.file("home/Documents/first.txt")
        let second = try directory.file("home/Documents/second.txt")
        let files = [first, second].map {
            FoundFile(
                url: $0, size: 16, length: 16, modificationDate: .now, requiresPrivileges: false,
                identity: FileIdentity.of($0)
            )
        }
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

        let result = await FileSearch.trash(files, using: service)

        #expect(result.trashed.count == 2)
        #expect(result.failures.isEmpty)
        #expect(Set(journal.entries().map(\.batch)).count == 1)
    }
}
