import Darwin
import Foundation
@testable import PeelCore
import Testing

struct FolderDuplicateTests {
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
        scan.folderGroups.map {
            $0.folders.map { $0.url.pathComponents.drop { $0 != "home" }.dropFirst().joined(separator: "/") }
        }
    }

    /// Makes two folders that hold the same files under the same names, and nothing else.
    @discardableResult
    private func trip(in directory: borrowing TemporaryDirectory) throws -> (first: Data, second: Data) {
        let first = randomData(count: 5_000)
        let second = randomData(count: 3_000)
        for folder in ["home/Documents/Trip", "home/Pictures/Trip"] {
            try directory.file("\(folder)/a.jpg", contents: first)
            try directory.file("\(folder)/b.jpg", contents: second)
        }
        return (first, second)
    }

    /// A folder of empty disk images frees nothing, however large its files say they are. The minimum size is
    /// compared with the blocks a copy really holds, for folders as for files.
    @Test func foldersOfHolesAreNoDuplicates() async throws {
        let directory = try TemporaryDirectory()
        for folder in ["home/Documents/Images", "home/Desktop/Images"] {
            let url = try directory.file("\(folder)/disk.img", bytes: 0)
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: 100 * 1_048_576)
            try handle.close()
        }

        let result = try await scan(directory) { $0.minimumSize = 100_000 }

        #expect(names(result).isEmpty)
        #expect(result.groups.isEmpty)
    }

    @Test func aFloorOfZeroStillLeavesOutFoldersThatHoldNothing() async throws {
        let directory = try TemporaryDirectory()
        for folder in ["home/Documents/Notes", "home/Desktop/Notes"] {
            try directory.file("\(folder)/todo.txt", bytes: 0)
        }

        let result = try await scan(directory) { $0.minimumSize = 0 }

        #expect(names(result).isEmpty)
        #expect(result.groups.isEmpty)
    }

    @Test func groupsFoldersWithIdenticalContents() async throws {
        let directory = try TemporaryDirectory()
        try trip(in: directory)

        let result = try await scan(directory)

        #expect(names(result) == [["Documents/Trip", "Pictures/Trip"]])
        #expect(result.folderGroups.first?.fileCount == 2)
        #expect(result.suggestedFolderSelection.map(\.lastPathComponent) == ["Trip"])
    }

    /// The folder row speaks for every file under it, so the same bytes are never offered twice.
    @Test func filesInsideAnOfferedFolderAreNotListedOnTheirOwn() async throws {
        let directory = try TemporaryDirectory()
        try trip(in: directory)

        let result = try await scan(directory)

        #expect(result.groups.isEmpty)
        #expect(result.folderGroups.count == 1)
    }

    /// Folders that differ in one file are not copies, and the files that do match are offered one by one.
    @Test func oneFileApartIsNoCopy() async throws {
        let directory = try TemporaryDirectory()
        try trip(in: directory)
        try randomData(count: 3_000).write(to: directory.url.appending(path: "home/Pictures/Trip/b.jpg"))

        let result = try await scan(directory)

        #expect(result.folderGroups.isEmpty)
        #expect(result.groups.map { $0.files.count } == [2])
    }

    @Test func somethingExtraOnOneSideIsNoCopy() async throws {
        let directory = try TemporaryDirectory()
        try trip(in: directory)
        try directory.file("home/Pictures/Trip/notes.txt", contents: Data("more".utf8))

        #expect(try await scan(directory).folderGroups.isEmpty)
    }

    /// Hidden entries are compared like any other. Peel never moves a folder it has not read whole.
    @Test func aHiddenFileTellsTwoFoldersApart() async throws {
        let directory = try TemporaryDirectory()
        try trip(in: directory)
        try directory.file("home/Pictures/Trip/.DS_Store", contents: Data("view".utf8))

        #expect(try await scan(directory).folderGroups.isEmpty)
    }

    @Test func offersTheTopmostFolderAndNotEveryFolderInIt() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 4_000)
        for (folder, marker) in [("home/Documents/A", "one"), ("home/Pictures/B", "two")] {
            try directory.file("\(folder)/Trip/inside/photo.jpg", contents: contents)
            try directory.file("\(folder)/Trip/cover.jpg", contents: contents)
            try directory.file("\(folder)/marker.txt", contents: Data(marker.utf8))
        }

        let result = try await scan(directory)

        #expect(names(result) == [["Documents/A/Trip", "Pictures/B/Trip"]])
    }

    @Test func leavesAloneAFolderHoldingSomethingItCannotLookAt() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 2_000)
        for folder in ["home/Documents/Work", "home/Pictures/Work"] {
            try directory.file("\(folder)/report.pdf", contents: contents)
        }
        try directory.directory("home/Documents/Work/project/.git")
        try directory.directory("home/Pictures/Work/project/.git")
        try directory.file("home/Documents/Work/project/code.swift", contents: contents)
        try directory.file("home/Pictures/Work/project/code.swift", contents: contents)

        #expect(try await scan(directory).folderGroups.isEmpty)
    }

    @Test func leavesAloneAFolderHoldingNodeModules() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 2_000)
        for folder in ["home/Documents/Web", "home/Pictures/Web"] {
            try directory.file("\(folder)/report.pdf", contents: contents)
            try directory.file("\(folder)/node_modules/package/index.js", contents: contents)
        }

        #expect(try await scan(directory).folderGroups.isEmpty)
    }

    /// Folders holding a project are left to Build Artifacts, unless the projects themselves were chosen. A stray
    /// build file in Desktop or another folder every account starts with does not make that folder a project.
    @Test func leavesAloneAFolderHoldingAProject() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 2_000)
        let photo = randomData(count: 4_000)
        for folder in ["home/Documents/Work", "home/Pictures/Work"] {
            try directory.file("\(folder)/report.pdf", contents: contents)
            try directory.file("\(folder)/site/Cargo.toml")
            try directory.file("\(folder)/site/main.rs", contents: contents)
        }
        try directory.file("home/Desktop/package.json", contents: randomData(count: 20))
        try directory.file("home/Desktop/Trip/a.jpg", contents: photo)
        try directory.file("home/Movies/Trip/a.jpg", contents: photo)

        let home = try await scan(directory)
        let chosen = try await scan(directory, folders: ["home/Documents/Work/site", "home/Pictures/Work/site"])

        #expect(names(home).map { $0.sorted() } == [["Desktop/Trip", "Movies/Trip"]])
        #expect(names(chosen) == [["Documents/Work/site", "Pictures/Work/site"]])
        let offered = try #require(chosen.folderGroups.first?.folders.first)
        #expect(FolderDuplicates.holdsTheSameContents(offered), "a chosen project could not be moved")
    }

    /// A folder the user chose is never a project, build file or not, and the check before the move lists a
    /// folder the way the scan did. An offered folder holding a chosen one must still be movable: listed again
    /// without the chosen folders, the one inside read as a project and the offer could never be carried out.
    @Test func aChosenFolderInsideAnOfferedOneIsNoProjectAtTheMoveEither() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 2_000)
        for folder in ["home/Documents/Work", "home/Pictures/Work"] {
            try directory.file("\(folder)/report.pdf", contents: contents)
            try directory.file("\(folder)/site/Cargo.toml")
            try directory.file("\(folder)/site/main.rs", contents: contents)
        }

        let chosen = try await scan(
            directory, folders: ["home/Documents/Work", "home/Pictures/Work", "home/Documents/Work/site", "home/Pictures/Work/site"]
        )

        #expect(names(chosen).map { $0.sorted() } == [["Documents/Work", "Pictures/Work"]])
        let offered = try #require(chosen.folderGroups.first?.folders.first)
        #expect(FolderDuplicates.holdsTheSameContents(offered), "the move saw a project the scan did not")
    }

    @Test func leavesAloneAFolderHoldingALinkOrAPhotoLibrary() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 2_000)
        let original = try directory.file("home/Documents/Linked/report.pdf", contents: contents)
        try directory.file("home/Pictures/Linked/report.pdf", contents: contents)
        for folder in ["home/Documents/Linked", "home/Pictures/Linked"] {
            try FileManager.default.createSymbolicLink(
                at: directory.url.appending(path: "\(folder)/shortcut.pdf"),
                withDestinationURL: original
            )
        }

        let linked = try await scan(directory).folderGroups
        for folder in ["home/Documents/Linked", "home/Pictures/Linked"] {
            try FileManager.default.removeItem(at: directory.url.appending(path: "\(folder)/shortcut.pdf"))
            try directory.file("\(folder)/Album.photoslibrary/database.db", contents: contents)
        }

        #expect(linked.isEmpty)
        #expect(try await scan(directory).folderGroups.isEmpty)
    }

    @Test func leavesAloneAFolderHoldingSomethingExcluded() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 2_000)
        for folder in ["home/Documents/Work", "home/Pictures/Work"] {
            try directory.file("\(folder)/report.pdf", contents: contents)
            try directory.file("\(folder)/keep.pdf", contents: contents)
        }
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let exclusions = Exclusions(paths: [directory.url.appending(path: "home/Documents/Work/keep.pdf")])

        let result = try await DuplicateFinder(homeDirectory: home, exclusions: exclusions)
            .scan(.everySize(in: [home]))

        #expect(result.folderGroups.isEmpty)
    }

    /// The same rule applies to a scan made before the exclusion. A folder excluded itself, or with something
    /// excluded inside it, leaves its group, and a group that loses its kept folder keeps the next one.
    @Test func aFolderExcludedAfterTheScanLeavesIt() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 3_000)
        for folder in ["home/Documents/Trip", "home/Pictures/Trip", "home/Desktop/Trip"] {
            try directory.file("\(folder)/a.jpg", contents: contents)
            try directory.file("\(folder)/b.txt", contents: Data("hello".utf8))
        }
        let result = try await scan(directory)
        let folders = try #require(result.folderGroups.first).folders.map(\.url)

        let itself = await result.excluded(by: Exclusions(paths: [folders[0]]))
        let remaining = result.removing(itself)
        let inside = await result.excluded(by: Exclusions(paths: [folders[1].appending(path: "a.jpg")]))

        #expect(itself == [folders[0]])
        #expect(remaining.folderGroups.map { $0.folders.map(\.url) } == [Array(folders.dropFirst())])
        #expect(remaining.keepingOneOfEachFolder(result.suggestedFolderSelection) == [folders[2]])
        #expect(inside == [folders[1]])
    }

    @Test func keepsTheFolderThatLooksLikeTheOriginal() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 4_000)
        for folder in ["home/Downloads/Trip", "home/Documents/Trip copy", "home/Documents/Trip"] {
            try directory.file("\(folder)/photo.jpg", contents: contents)
        }

        let folders = try #require(try await scan(directory).folderGroups.first).folders

        #expect(folders.map(\.url.lastPathComponent) == ["Trip", "Trip copy", "Trip"])
        #expect(folders[0].url.path(percentEncoded: false).contains("/Documents/"))
        #expect(folders[2].url.path(percentEncoded: false).contains("/Downloads/"))
    }

    @Test func leavesOutAFolderSmallerThanTheMinimum() async throws {
        let directory = try TemporaryDirectory()
        try trip(in: directory)

        #expect(try await scan(directory) { $0.minimumSize = 100_000 }.folderGroups.isEmpty)
    }

    /// A file kind only applies to files, so choosing one skips the folder comparison.
    @Test func asksAboutFoldersOnlyWhenNoKindWasChosen() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 4_000)
        for folder in ["home/Documents/Trip", "home/Pictures/Trip"] {
            try directory.file("\(folder)/photo.png", contents: contents)
        }

        let result = try await scan(directory) { $0.kind = .images }

        #expect(result.folderGroups.isEmpty)
        #expect(result.groups.count == 1)
    }

    /// A document package is read like any other folder, so the folder holding it can be compared. A package is
    /// never offered on its own, because Duplicates does not check whether an app is running.
    @Test func comparesInsideAPackageAndNeverOffersOne() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 4_000)
        for folder in ["home/Documents/Work", "home/Pictures/Work"] {
            try directory.file("\(folder)/Notes.rtfd/TXT.rtf", contents: contents)
        }

        let result = try await scan(directory)

        #expect(names(result) == [["Documents/Work", "Pictures/Work"]])
    }

    @Test func neverOffersTwoCopiesOfAPackageOnTheirOwn() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 4_000)
        try directory.file("home/Documents/Notes.rtfd/TXT.rtf", contents: contents)
        try directory.file("home/Documents/Notes copy.rtfd/TXT.rtf", contents: contents)

        #expect(try await scan(directory).folderGroups.isEmpty)
    }

    /// Nothing inside a package is offered either: an app gutted in place would stay behind, even the copy in use.
    @Test func neverOffersAnythingInsideAPackage() async throws {
        let directory = try TemporaryDirectory()
        let binary = randomData(count: 4_000)
        let resource = randomData(count: 3_000)
        for app in ["home/Documents/Tool.app", "home/Pictures/Tool.app"] {
            try directory.file("\(app)/Contents/MacOS/Tool", contents: binary)
            try directory.file("\(app)/Contents/Resources/Tool.icns", contents: resource)
        }

        #expect(names(try await scan(directory)) == [])
    }

    /// A package chosen to be scanned, or a folder inside one, is not looked into at all, and says so: nothing inside
    /// it, folder or file, is offered.
    @Test func neverScansAChosenPackage() async throws {
        let directory = try TemporaryDirectory()
        let binary = randomData(count: 4_000)
        for app in ["home/Documents/Tool.app", "home/Pictures/Tool.app"] {
            try directory.file("\(app)/Contents/MacOS/Tool", contents: binary)
        }

        let chosen = ["home/Documents/Tool.app", "home/Pictures/Tool.app/Contents"]
        let result = try await scan(directory, folders: chosen)
        #expect(names(result) == [])
        #expect(result.groups.isEmpty)
        #expect(result.skippedLocations.map(\.lastPathComponent) == ["Tool.app", "Contents"])
    }

    /// A hidden folder, or one inside a hidden folder, is never offered, as the file scan never lists a hidden file:
    /// a tool's settings in `~/.config` stay where they are, however like a backup of them they are. Finder's hidden
    /// flag hides a folder as a leading dot does.
    @Test func neverOffersAHiddenFolder() async throws {
        let directory = try TemporaryDirectory()
        let settings = randomData(count: 4_000)
        let flagged = try directory.directory("home/Pictures/Kept")
        for folder in ["home/.config/tool", "home/Documents/tool", "home/Pictures/Kept/tool", "home/Movies/tool"] {
            try directory.file("\(folder)/settings.json", contents: settings)
        }
        #expect(chflags(flagged.path(percentEncoded: false), UInt32(UF_HIDDEN)) == 0)

        #expect(names(try await scan(directory)) == [["Documents/tool", "Movies/tool"]])
    }

    @Test func anEmptyFolderIsNoCopyOfAnything() async throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/Documents/Empty")
        try directory.directory("home/Pictures/Empty")

        #expect(try await scan(directory).folderGroups.isEmpty)
    }

    /// Like `DuplicateFile`, a folder reports its size and what moving it would free. A file shared through a
    /// hard link frees nothing.
    @Test func promisesOnlyWhatMovingTheFolderWouldReallyFree() async throws {
        let directory = try TemporaryDirectory()
        let contents = randomData(count: 40_000)
        let original = try directory.file("home/Documents/Trip/photo.jpg", contents: contents)
        try directory.directory("home/Pictures/Trip")
        try FileManager.default.linkItem(at: original, to: directory.url.appending(path: "home/Pictures/Trip/photo.jpg"))

        let group = try #require(try await scan(directory).folderGroups.first)

        #expect(group.size == 40_000)
        #expect(group.reclaimableSize == 0)
    }
}

struct FolderDuplicateRemovalTests {
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

    /// Makes two identical folders and scans them. `kept` is the one the scan suggests keeping.
    private func duplicates(
        in directory: borrowing TemporaryDirectory
    ) async throws -> (scan: DuplicateScan, kept: URL, copy: URL) {
        let contents = Data((0..<5_000).map { _ in UInt8.random(in: 0...255) })
        try directory.file("home/Documents/Trip/photo.jpg", contents: contents)
        try directory.file("home/Pictures/Trip/photo.jpg", contents: contents)
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let scan = try await DuplicateFinder(homeDirectory: home).scan(.everySize(in: [home]))
        let folders = try #require(scan.folderGroups.first).folders
        #expect(folders.count == 2)
        return (scan, folders[0].url, folders[1].url)
    }

    @Test func neverTrashesEveryCopy() async throws {
        let directory = try TemporaryDirectory()
        let (scan, kept, copy) = try await duplicates(in: directory)

        let result = await DuplicateRemoval.trash(
            [],
            folders: [kept, copy],
            from: scan,
            using: try service(in: directory)
        )

        #expect(result.trashed.isEmpty)
        #expect(Set(result.failures.map(\.reason)) == [.lastCopy])
        #expect(FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)))
    }

    @Test func refusesWhenTheKeptCopyChanged() async throws {
        let directory = try TemporaryDirectory()
        let (scan, kept, copy) = try await duplicates(in: directory)
        try Data("added".utf8).write(to: kept.appending(path: "extra.txt"))

        let result = await DuplicateRemoval.trash([], folders: [copy], from: scan, using: try service(in: directory))

        #expect(result.trashed.isEmpty)
        #expect(result.failures.map(\.reason) == [.lastCopy])
        #expect(FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)))
    }

    /// A file put into the copy after the scan would go to the Trash with it, unread and uncompared.
    @Test func refusesACopyThatChangedSinceTheScan() async throws {
        let directory = try TemporaryDirectory()
        let (scan, _, copy) = try await duplicates(in: directory)
        try Data("new".utf8).write(to: copy.appending(path: "notes.txt"))

        let result = await DuplicateRemoval.trash([], folders: [copy], from: scan, using: try service(in: directory))

        #expect(result.trashed.isEmpty)
        #expect(result.failures.map(\.reason) == [.changedSinceScan])
        #expect(FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)))
    }

    @Test func trashesAnUnchangedCopy() async throws {
        let directory = try TemporaryDirectory()
        let (scan, kept, copy) = try await duplicates(in: directory)

        let result = await DuplicateRemoval.trash([], folders: [copy], from: scan, using: try service(in: directory))

        #expect(result.failures.isEmpty)
        #expect(result.trashed.map(\.originalURL) == [copy])
        #expect(FileManager.default.fileExists(atPath: kept.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)))
        #expect(scan.removing([copy]).folderGroups.isEmpty)
    }
}
