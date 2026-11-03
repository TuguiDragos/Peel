import Foundation
@testable import PeelCore
import Testing

struct AppFoldersTests {
    @Test func aLinkIsJudgedByWhereItLeads() throws {
        let directory = try TemporaryDirectory()
        let home = try directory.directory("home")
        try directory.directory("home/Applications")
        try directory.directory("home/.Trash/Old")
        try directory.directory("elsewhere")
        func link(_ name: String, to destination: String) throws -> URL {
            try FileManager.default.createSymbolicLink(
                atPath: directory.url.appending(path: name).path(percentEncoded: false),
                withDestinationPath: destination
            )
            return directory.url.appending(path: name, directoryHint: .isDirectory)
        }

        #expect(AppFolders.refusal(of: try link("one", to: "home/Applications"), home: home) == .alreadyLookedIn)
        #expect(AppFolders.refusal(of: try link("two", to: "home/.Trash/Old"), home: home) == .inATrash)
        #expect(AppFolders.refusal(of: try link("three", to: "elsewhere"), home: home) == nil)
        #expect(AppFolders.refusal(of: try link("nowhere", to: "/Volumes/org-example-not-connected/Apps"), home: home) == nil)
        #expect(AppFolders.refusal(of: try link("round", to: "round"), home: home) == nil)
    }

    /// A folder chosen for apps is looked through three levels deep. The whole disk, the home folder or a folder
    /// Peel already looks in would only repeat or slow every reading of the apps.
    @Test func refusesAFolderTooBroadOrAlreadyLookedIn() {
        let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)
        for path in ["/", "/Users", "/Volumes", "/System", "/Library", "/Users/someone", "/Users/someone/Library",
                     "/Applications", "/Applications/Utilities", "/Users/someone/Applications"] {
            let folder = URL(filePath: path, directoryHint: .isDirectory)
            #expect(AppFolders.refusal(of: folder, home: home) != nil, "\(path)")
        }
        for path in ["/Volumes/Studio/Apps", "/Users/someone/Tools"] {
            let folder = URL(filePath: path, directoryHint: .isDirectory)
            #expect(AppFolders.refusal(of: folder, home: home) == nil, "\(path)")
        }
    }

    @Test func refusesAsLookedInExactlyWhatTheWalkOfAnApplicationsFolderReads() throws {
        let directory = try TemporaryDirectory()
        let paths = [
            "Applications/Suite", "Applications/Suite/Pro", "Applications/Suite/Pro/Editor",
            "Applications/Suite/Pro/Editor/2026", "Applications/.Hidden", "Applications/.Hidden/Inner",
            "Applications/Tool.app/Contents", "Applications/Tool.app/Contents/Helpers",
        ]
        let folders = try paths.map { try directory.directory($0) }
        for path in paths {
            try directory.directory(path + "/Probe.app")
        }

        let found = Set(AppCatalog.appBundles(in: directory.url.appending(path: "Applications")).bundles.map {
            PathPattern.comparablePath(of: $0)
        })

        for folder in folders {
            let isFound = found.contains(PathPattern.comparablePath(of: folder.appending(path: "Probe.app")))
            let isRefused = AppFolders.refusal(of: folder, home: directory.url) == .alreadyLookedIn
            #expect(isRefused == isFound, "\(folder.lastPathComponent)")
        }
        #expect(AppFolders.refusal(of: folders[2], home: directory.url) == nil, "Unity Hub's Editor folder")
    }

    @Test func refusesAWholeDiskMacOSsOwnFoldersAndTheCloud() {
        let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)
        func refusal(_ path: String, inTheCloud: Bool = false) -> AppFolders.Refusal? {
            AppFolders.refusal(of: URL(filePath: path, directoryHint: .isDirectory), home: home) { _ in inTheCloud }
        }
        for path in ["/Volumes/Backup", "/System/Applications", "/System/Library/CoreServices",
                     "/Library/Application Support", "/Users/someone/Library/Application Support"] {
            #expect(refusal(path) == .tooBroad, "\(path)")
        }
        #expect(refusal("/Users/someone/Library/Application Support/Steam/steamapps/common") == nil)
        #expect(refusal("/Users/someone/Library/CloudStorage/Dropbox/Apps", inTheCloud: true) == .inTheCloud)
    }

    @Test func refusesTheTrashAndAFolderInIt() throws {
        let directory = try TemporaryDirectory()
        let trash = try directory.directory(".Trash")
        let inTheTrash = try directory.directory(".Trash/Apps")
        let tools = try directory.directory("Tools")

        #expect(AppFolders.refusal(of: trash, home: directory.url) == .inATrash)
        #expect(AppFolders.refusal(of: inTheTrash, home: directory.url) == .inATrash)
        #expect(AppFolders.refusal(of: tools, home: directory.url) == nil)
    }

    @Test func leavesOutAFolderInTheTrashChosenBefore() throws {
        let directory = try TemporaryDirectory()
        let inTheTrash = try directory.directory(".Trash/Apps")
        let tools = try directory.directory("Tools")
        let saved = [inTheTrash, tools].map { $0.path(percentEncoded: false) }
        let list = try directory.file("app-folders.json", contents: JSONEncoder().encode(saved))

        #expect(AppFolders(url: list, home: directory.url).load()?.map(\.lastPathComponent) == ["Tools"])
    }

    @Test func leavesOutAFolderNowRefusedThatWasChosenBefore() throws {
        let directory = try TemporaryDirectory()
        let tools = try directory.directory("Tools")
        let saved = ["/Volumes/Backup", "/System/Applications", tools.path(percentEncoded: false)]
        let list = try directory.file("app-folders.json", contents: JSONEncoder().encode(saved))

        #expect(AppFolders(url: list, home: directory.url).load()?.map(\.lastPathComponent) == ["Tools"])
    }

    @Test func aFolderReachedThroughTheDataVolumeIsJudgedAsItself() throws {
        let directory = try TemporaryDirectory()
        let tools = try directory.directory("Tools")
        let real = PathPattern.canonical(tools).path(percentEncoded: false)
        let reached = URL(filePath: "/System/Volumes/Data" + real, directoryHint: .isDirectory)

        #expect(reached.isThere)
        #expect(AppFolders.refusal(of: reached, home: directory.url) == nil)
        #expect(AppFolders.refusal(of: URL(filePath: "/System/Applications"), home: directory.url) == .tooBroad)
        #expect(AppFolders.refusal(of: URL(filePath: "/System/Volumes/Data/Users"), home: directory.url) == .tooBroad)
        #expect(
            AppFolders.refusal(of: URL(filePath: "/System/Volumes/Data/Applications"), home: directory.url)
                == .alreadyLookedIn
        )
    }

    @Test func namesWhatItLeavesOutAndKeepsItUntilItIsTakenOff() throws {
        let directory = try TemporaryDirectory()
        let tools = try directory.directory("Tools")
        let other = try directory.directory("Other")
        let saved = ["/Volumes/Backup", tools.path(percentEncoded: false)]
        let list = try directory.file("app-folders.json", contents: JSONEncoder().encode(saved))
        let folders = AppFolders(url: list, home: directory.url)

        let backup = URL(filePath: "/Volumes/Backup", directoryHint: .isDirectory)
        #expect(folders.leftOut() == [AppFolders.LeftOut(folder: backup, refusal: .tooBroad)])

        #expect(folders.add([other]) == .saved)
        #expect(folders.leftOut().map(\.refusal) == [.tooBroad], "an edit lost it without a word")
        #expect(folders.load()?.map(\.lastPathComponent) == ["Tools", "Other"])

        #expect(folders.remove([URL(filePath: "/Volumes/Backup")]) == .saved)
        #expect(folders.leftOut().isEmpty)
    }

    @Test func aFolderPeelReadsAnywayIsNotLeftOut() throws {
        let directory = try TemporaryDirectory()
        let inside = directory.url.appending(path: "Applications/Tools", directoryHint: .isDirectory)
        let list = try directory.file(
            "app-folders.json", contents: JSONEncoder().encode([inside.path(percentEncoded: false)])
        )

        #expect(AppFolders(url: list, home: directory.url).leftOut().isEmpty)
    }

    @Test func aMissingListLeavesOutNothingAndMakesNothing() throws {
        let directory = try TemporaryDirectory()
        let folder = directory.url.appending(path: "Peel")

        #expect(AppFolders(url: folder.appending(path: "app-folders.json"), home: directory.url).leftOut().isEmpty)
        #expect(folder.isMissing)
    }

    @Test func aReadingOfAnotherHomeLeavesOutAFolderInThatHomesTrash() throws {
        let directory = try TemporaryDirectory()
        let saved = [try directory.directory(".Trash/Apps"), try directory.directory("Tools")]
            .map { $0.path(percentEncoded: false) }
        try directory.file("Library/Application Support/Peel/app-folders.json", contents: JSONEncoder().encode(saved))
        let environment = SearchEnvironment(
            homeDirectory: directory.url,
            rootDirectory: directory.url.appending(path: "root")
        )

        let read = AppCatalog.directories(in: environment).map(\.lastPathComponent)

        #expect(read.contains("Tools"))
        #expect(!read.contains("Apps"))
    }

    @Test func remembersTheFoldersChosenForApps() throws {
        let directory = try TemporaryDirectory()
        let folders = AppFolders(url: directory.url.appending(path: "app-folders.json"))
        let studio = directory.url.appending(path: "Studio Apps", directoryHint: .isDirectory)
        #expect(folders.load() == [])

        #expect(folders.add([studio]) == .saved)
        #expect(folders.load()?.map(\.lastPathComponent) == ["Studio Apps"])
        let chosen = try #require(folders.load())
        #expect(AppCatalog.directories(adding: chosen).count == AppCatalog.standardDirectories.count + 1)

        #expect(folders.remove([studio]) == .saved)
        #expect(folders.load() == [])
    }

    @Test(.permissionsHold) func aListThatCannotBeReadIsNoEmptyList() throws {
        let directory = try TemporaryDirectory()
        let damaged = try directory.file("damaged.json", contents: Data("not a list".utf8))
        let closed = try directory.file("closed.json", contents: Data("[]".utf8))
        try directory.setPermissions(0o000, of: "closed.json")
        defer { try? directory.setPermissions(0o644, of: "closed.json") }

        #expect(AppFolders(url: damaged).load() == nil)
        #expect(AppFolders(url: closed).load() == nil)
        #expect(AppFolders(url: directory.url.appending(path: "missing.json")).load() == [])

        let closedRead = FileProblem.failed(SystemError(domain: NSPOSIXErrorDomain, code: Int(EACCES)))
        #expect(AppFolders(url: damaged).whyUnreadable() == .damaged)
        #expect(AppFolders(url: closed).whyUnreadable() == closedRead)
        #expect(AppFolders(url: directory.url.appending(path: "missing.json")).whyUnreadable() == nil)
        #expect(AppFolders(url: damaged).add([directory.url]) == .notSaved(.damaged), "a list it can't read was written over")
        #expect(try String(contentsOf: damaged, encoding: .utf8) == "not a list")
    }

    @Test(.permissionsHold) func saysWhyAChangeCouldNotBeSaved() throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("Peel")
        let tools = try directory.directory("Tools")
        try directory.setPermissions(0o500, of: folder)
        defer { try? directory.setPermissions(0o755, of: folder) }

        let refusedWrite = SystemError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        #expect(AppFolders(url: folder.appending(path: "app-folders.json")).add([tools]) == .notSaved(.failed(refusedWrite)))
    }

    @Test func startsNothingOverWhileTheListCanBeRead() throws {
        let directory = try TemporaryDirectory()
        let folders = AppFolders(url: try directory.file("app-folders.json", contents: Data("[]".utf8)))

        #expect(folders.startOver() == .notNeeded)
        #expect(AppFolders(url: directory.url.appending(path: "missing.json")).startOver() == .notNeeded)
    }

    @Test func startingOverKeepsTheDamagedListBesideAnEmptyOne() throws {
        let directory = try TemporaryDirectory()
        let folders = AppFolders(url: try directory.file("app-folders.json", contents: Data("not a list".utf8)))

        #expect(folders.startOver() == .started)

        #expect(folders.load() == [])
        let kept = try FileManager.default.contentsOfDirectory(atPath: directory.url.path(percentEncoded: false))
            .filter { $0.hasPrefix("app-folders-damaged-") }
        #expect(kept.count == 1)
    }
}
