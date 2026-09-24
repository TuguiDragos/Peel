import Foundation
import Synchronization
@testable import PeelCore
import Testing
import UniformTypeIdentifiers

struct FileSearchTests {
    /// What an app keeps in a Library folder is listed last and never selected by Select All, whatever its name
    /// begins with: to a comparison of characters, a name beginning with a combining mark was outside its folder.
    @Test func whatSitsInALibraryFolderIsAppDataWhateverItsNameBeginsWith() {
        let home = URL(filePath: "/Users/x", directoryHint: .isDirectory)

        #expect(FileSearch.isAppData(URL(filePath: "/Users/x/Library/\u{301}cache.db"), home: home))
        #expect(FileSearch.isAppData(URL(filePath: "/Library/\u{301}cache.db"), home: home))
        #expect(!FileSearch.isAppData(URL(filePath: "/Users/x/Libraryish/cache.db"), home: home))
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
    }

    /// `MDQuery.h` promises no order, so the results are sorted before the cap applies. Cutting first would keep
    /// an arbitrary set of files and call them the largest.
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
            environment: SearchEnvironment(homeDirectory: home, rootDirectory: directory.url)
        )

        #expect(results.files.count == FileSearch.maximumResults)
        #expect(results.files.first?.url == biggest)
        #expect(results.isTruncated)
    }

    /// The guard is asked only about the files that can make the list: the largest first, and no further once
    /// the list is full and one more file shows it had to be cut.
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
            allows: { _ in
                asked.withLock { $0 += 1 }
                return true
            }
        )

        #expect(results.files.count == FileSearch.maximumResults)
        #expect(results.isTruncated)
        #expect(results.files.first?.size == Int64(FileSearch.maximumResults + 50))
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
    }
}
