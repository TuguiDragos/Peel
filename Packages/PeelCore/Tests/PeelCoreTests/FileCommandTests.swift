import ArgumentParser
import Foundation
@testable import PeelCommandLine
@testable import PeelCore
import Testing

/// Tests what the four cleaning commands (`caches`, `projects`, `duplicates`, and `orphans`) decide to move.
struct FileCommandTests {
    private func command<Command: AsyncParsableCommand>(_ arguments: [String]) throws -> Command {
        try #require(try PeelCommand.parseAsRoot(arguments) as? Command)
    }

    private func logs(in directory: borrowing TemporaryDirectory) -> (removals: RemovalLog, refusals: RefusalLog) {
        (RemovalLog(url: directory.url.appending(path: "Peel/removals.json")),
         RefusalLog(url: directory.url.appending(path: "Peel/refusals.json")))
    }

    private func service(in directory: borrowing TemporaryDirectory) throws -> TrashService {
        let trash = try directory.directory("Trash")
        return TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            ),
            moveToTrash: { url in
                let destination = trash.appending(path: UUID().uuidString)
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            }
        )
    }

    private func moved(_ logs: (removals: RemovalLog, refusals: RefusalLog)) async -> [String] {
        (await logs.removals.load().records ?? []).map(\.originalURL.lastPathComponent).sorted()
    }

    // MARK: Developer caches

    private func environment(
        _ name: String,
        id: String,
        apps: [String] = [],
        locations: [(String, DeveloperEnvironment.ContentKind)],
        in directory: borrowing TemporaryDirectory
    ) throws -> DeveloperEnvironment {
        DeveloperEnvironment(
            id: id,
            name: name,
            systemImage: "hammer",
            appBundleIdentifiers: apps,
            locations: try locations.map { path, kind in
                DeveloperEnvironment.Location(url: try directory.file("home/\(path)/blob", bytes: 30).deletingLastPathComponent(), kind: kind, size: 30, source: "https://example.com/\(path)")
            }
        )
    }

    @Test func narrowsTheCachesByNameOrIdentifier() throws {
        let directory = try TemporaryDirectory()
        let brew = try environment("Homebrew", id: "homebrew", locations: [("Library/Caches/Homebrew", .cache)], in: directory)
        let cargo = try environment("Rust", id: "rust", locations: [("Library/Caches/cargo", .cache)], in: directory)

        #expect(try CachesCommand.chosen(from: [brew, cargo], named: []).map(\.id) == ["homebrew", "rust"])
        #expect(try CachesCommand.chosen(from: [brew, cargo], named: ["homebrew"]).map(\.id) == ["homebrew"])
        #expect(try CachesCommand.chosen(from: [brew, cargo], named: ["RUST"]).map(\.id) == ["rust"])
        #expect(try CachesCommand.chosen(from: [brew, cargo], named: ["Homebrew", "Rust"]).count == 2)
        #expect(throws: CommandFailure.self) { try CachesCommand.chosen(from: [brew, cargo], named: ["Nonesuch"]) }
        // A name that matches nothing beside one that does is a typo, never a tool with nothing to show.
        let typo = #expect(throws: CommandFailure.self) {
            try CachesCommand.chosen(from: [brew, cargo], named: ["rust", "hombrew"])
        }
        let hombrew = Output.quoted("hombrew")
        #expect(typo?.description == "No developer caches of \(hombrew) were found. See `peel caches`.")
    }

    /// Model weights and installed packages are listed and never suggested, so `--remove` leaves them.
    @Test func movesOnlyTheCachesItWouldSuggest() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let tool = try environment("Rust", id: "rust", locations: [
            ("Library/Caches/cargo", .cache),
            ("Library/Models/llama", .models),
            ("Library/Envs/venv", .environments),
        ], in: directory)

        try await (command(["caches", "--remove", "-y"]) as CachesCommand)
            .clean([tool], using: try service(in: directory), recordingIn: logs.removals, refusals: logs.refusals)

        #expect(await moved(logs) == ["cargo"])
        #expect(FileManager.default.fileExists(atPath: directory.url.appending(path: "home/Library/Models/llama").path(percentEncoded: false)))
    }

    /// Nothing of a tool moves while its app runs, since the app writes in those folders: the Developer page waits,
    /// and so does `peel caches`. Finder runs on every Mac, so it stands for an app that is open.
    @Test func leavesTheCachesOfAnAppThatRuns() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let open = try environment("Finder Tools", id: "finder", apps: ["com.apple.finder"], locations: [("Library/Caches/finder-tool", .cache)], in: directory)
        let closed = try environment("Rust", id: "rust", locations: [("Library/Caches/cargo", .cache)], in: directory)
        #expect(open.runningApp == "Finder")
        #expect(closed.runningApp == nil)

        let collected = Output.Collected()
        try await Output.$collected.withValue(collected) {
            try await (command(["caches", "--remove", "-y"]) as CachesCommand)
                .clean([open, closed], using: try service(in: directory), recordingIn: logs.removals, refusals: logs.refusals)
        }
        #expect(await moved(logs) == ["cargo"])
        #expect(collected.notes.contains("Quit Finder first"))
        #expect(FileManager.default.fileExists(atPath: directory.url.appending(path: "home/Library/Caches/finder-tool").path(percentEncoded: false)))

        await #expect(throws: CommandFailure.self) {
            try await (command(["caches", "--remove", "-y"]) as CachesCommand)
                .clean([open], using: try service(in: directory), recordingIn: logs.removals, refusals: logs.refusals)
        }
    }

    @Test func aDryRunOnCachesMovesNothing() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let tool = try environment("Rust", id: "rust", locations: [("Library/Caches/cargo", .cache)], in: directory)

        try await (command(["caches", "--remove", "--dry-run"]) as CachesCommand)
            .clean([tool], using: try service(in: directory), recordingIn: logs.removals, refusals: logs.refusals)

        #expect(await moved(logs).isEmpty)
        #expect(FileManager.default.fileExists(atPath: directory.url.appending(path: "home/Library/Caches/cargo").path(percentEncoded: false)))
    }

    // MARK: Build artifacts

    @Test func movesOnlyTheBuildArtifactsItWouldSuggest() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let project = try directory.directory("home/Developer/App")
        func artifact(_ name: String, lastActivity: Date) throws -> ProjectArtifact {
            ProjectArtifact(
                url: try directory.file("home/Developer/App/\(name)/blob", bytes: 20).deletingLastPathComponent(),
                project: project,
                name: name,
                tool: "Xcode",
                size: 20,
                lastActivity: lastActivity,
                hasGenericName: false,
                isEnvironment: false
            )
        }
        // A project untouched for longer than `recentlyActive` is suggested; one changed today is not.
        let stale = try artifact("DerivedData", lastActivity: .now.addingTimeInterval(-ProjectArtifacts.recentlyActive * 2))
        let fresh = try artifact("build", lastActivity: .now)

        try await (command(["projects", "~/Developer", "--remove", "-y"]) as ProjectsCommand)
            .clean([stale, fresh], using: try service(in: directory), recordingIn: logs.removals, refusals: logs.refusals)

        #expect(await moved(logs) == ["DerivedData"])
        #expect(FileManager.default.fileExists(atPath: fresh.url.path(percentEncoded: false)))
    }

    // MARK: Duplicates

    /// One copy of every group is always kept, whether the group is of folders or of files.
    @Test func keepsOneCopyOfEveryDuplicateGroup() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let contents = Data((0..<4_000).map { _ in UInt8.random(in: 0...255) })
        for folder in ["home/Documents/Trip", "home/Pictures/Trip"] {
            try directory.file("\(folder)/photo.jpg", contents: contents)
        }
        try directory.file("home/Documents/lonely.bin", contents: Data(repeating: 7, count: 4_000))
        try directory.file("home/Documents/lonely copy.bin", contents: Data(repeating: 7, count: 4_000))
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let scan = try await DuplicateFinder(homeDirectory: home).scan(DuplicateScanOptions(folders: [home]))
        let keptFolder = try #require(scan.folderGroups.first?.folders.first?.url)
        let keptFile = try #require(scan.groups.first?.files.first?.url)

        try await (command(["duplicates", "--remove", "-y"]) as DuplicatesCommand)
            .clean(scan, using: try service(in: directory), recordingIn: logs.removals, refusals: logs.refusals)

        #expect(await moved(logs) == ["Trip", "lonely copy.bin"])
        #expect(FileManager.default.fileExists(atPath: keptFolder.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: keptFile.path(percentEncoded: false)))
    }

    @Test func aDryRunOnDuplicatesMovesNothing() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let contents = Data((0..<4_000).map { _ in UInt8.random(in: 0...255) })
        try directory.file("home/Documents/a.bin", contents: contents)
        try directory.file("home/Documents/a copy.bin", contents: contents)
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let scan = try await DuplicateFinder(homeDirectory: home).scan(DuplicateScanOptions(folders: [home]))

        try await (command(["duplicates", "--remove", "--dry-run"]) as DuplicatesCommand)
            .clean(scan, using: try service(in: directory), recordingIn: logs.removals, refusals: logs.refusals)

        #expect(await moved(logs).isEmpty)
        #expect(FileManager.default.fileExists(atPath: directory.url.appending(path: "home/Documents/a copy.bin").path(percentEncoded: false)))
    }

    /// The plan says which copy of each group stays before it lists the copies that move: where the kept copy is
    /// is what the decision rests on.
    @Test func thePlanNamesTheCopyEachGroupKeeps() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let contents = Data((0..<4_000).map { _ in UInt8.random(in: 0...255) })
        try directory.file("home/Documents/a.bin", contents: contents)
        try directory.file("home/Documents/a copy.bin", contents: contents)
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let scan = try await DuplicateFinder(homeDirectory: home).scan(DuplicateScanOptions(folders: [home]))
        let kept = try #require(scan.groups.first?.files.first?.url)
        let collected = Output.Collected()

        try await Output.$collected.withValue(collected) {
            try await (command(["duplicates", "--remove", "--dry-run"]) as DuplicatesCommand)
                .clean(scan, using: try service(in: directory), recordingIn: logs.removals, refusals: logs.refusals)
        }

        let lines = collected.output.split(separator: "\n").map(String.init)
        let keptLine = try #require(lines.firstIndex { $0.hasPrefix("keep") && $0.hasSuffix(Output.path(kept)) })
        let movingLine = try #require(lines.firstIndex { !$0.hasPrefix("keep") && $0.hasSuffix("a copy.bin") })
        #expect(keptLine < movingLine)
    }

    // MARK: Orphaned files

    private func orphan(_ name: String, in directory: borrowing TemporaryDirectory, heldBack: HoldBack? = nil, requiresPrivileges: Bool = false) throws -> OrphanItem {
        OrphanItem(
            url: try directory.file("home/Library/Application Support/\(name)/blob", bytes: 10).deletingLastPathComponent(),
            kind: .applicationSupport,
            size: 10,
            modificationDate: .now,
            requiresPrivileges: requiresPrivileges,
            heldBack: heldBack
        )
    }

    private func scanner(in directory: borrowing TemporaryDirectory) -> OrphanScanner {
        OrphanScanner(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            ),
            isRegisteredApp: { _ in false }
        )
    }

    @Test func refusesAGroupItDoesNotHave() async throws {
        let directory = try TemporaryDirectory()
        let scan = OrphanScan(groups: [], unreadableLocations: [])

        await #expect(throws: CommandFailure.self) {
            try await (command(["orphans", "--remove", "com.example.gone", "-y"]) as OrphansCommand)
                .clean("com.example.gone", in: scan, apps: [], scanner: scanner(in: directory), using: try service(in: directory))
        }
    }

    /// Only the named group moves, and within it only what Peel does not leave alone.
    @Test func movesOneNamedGroupAndLeavesTheRest() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let wanted = OrphanGroup(identifier: "com.example.gone", items: [
            try orphan("com.example.gone", in: directory),
            try orphan("com.example.gone.documents", in: directory, heldBack: .holdsDocuments),
        ])
        let other = OrphanGroup(identifier: "com.example.other", items: [try orphan("com.example.other", in: directory)])
        let scan = OrphanScan(groups: [wanted, other], unreadableLocations: [])

        try await (command(["orphans", "--remove", "COM.EXAMPLE.GONE", "-y"]) as OrphansCommand)
            .clean("COM.EXAMPLE.GONE", in: scan, apps: [], scanner: scanner(in: directory), using: try service(in: directory), recordingIn: logs.removals, refusals: logs.refusals)

        #expect(await moved(logs) == ["com.example.gone"])
        #expect(FileManager.default.fileExists(atPath: wanted.items[1].url.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: other.items[0].url.path(percentEncoded: false)))
    }

    /// The command line never uses the helper, so what needs administrator access stays, is recorded as refused,
    /// and, since nothing else moved, the command exits 1.
    @Test func leavesWhatNeedsAdministratorAccessAndSaysSo() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let group = OrphanGroup(identifier: "com.example.gone", items: [
            try orphan("com.example.gone", in: directory, requiresPrivileges: true),
        ])
        let scan = OrphanScan(groups: [group], unreadableLocations: [])
        let service = try service(in: directory)

        await #expect(throws: ExitCode.failure) {
            try await (command(["orphans", "--remove", "com.example.gone", "-y"]) as OrphansCommand).clean(
                "com.example.gone", in: scan, apps: [], scanner: scanner(in: directory), using: service,
                recordingIn: logs.removals, refusals: logs.refusals
            )
        }

        #expect(await moved(logs).isEmpty)
        #expect(await logs.refusals.load().records.map(\.reason) == ["needs-helper"])
        #expect(FileManager.default.fileExists(atPath: group.items[0].url.path(percentEncoded: false)))
    }

    /// When Peel leaves every file of the group alone, there is nothing to ask about and nothing is recorded as
    /// refused.
    @Test func saysSoWhenTheWholeGroupIsLeftAlone() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let group = OrphanGroup(identifier: "com.example.gone", items: [
            try orphan("com.example.gone", in: directory, heldBack: .holdsALibrary),
        ])
        let scan = OrphanScan(groups: [group], unreadableLocations: [])
        let collected = Output.Collected()

        try await Output.$collected.withValue(collected) {
            try await (command(["orphans", "--remove", "com.example.gone", "-y"]) as OrphansCommand)
                .clean("com.example.gone", in: scan, apps: [], scanner: scanner(in: directory), using: try service(in: directory), recordingIn: logs.removals, refusals: logs.refusals)
        }

        #expect(await moved(logs).isEmpty)
        #expect(await logs.refusals.load().records.isEmpty)
        #expect(FileManager.default.fileExists(atPath: group.items[0].url.path(percentEncoded: false)))
        #expect(collected.notes == "\(Output.path(group.items[0].url)) stays: holds a photo, music, or video library\n")
    }

    /// A folder with a wallet or a repository inside is moved only when chosen by hand in the app, so naming its
    /// group moves the rest, says why it stays, and records no refusal, since nobody asked for it on its own.
    @Test func leavesWhatIsHeldBackAndSaysWhy() async throws {
        let directory = try TemporaryDirectory()
        let logs = logs(in: directory)
        let group = OrphanGroup(identifier: "com.example.gone", items: [
            try orphan("com.example.gone", in: directory),
            try orphan("com.example.gone.wallet", in: directory, heldBack: .holdsAWallet),
        ])
        let scan = OrphanScan(groups: [group], unreadableLocations: [])
        let collected = Output.Collected()

        try await Output.$collected.withValue(collected) {
            try await (command(["orphans", "--remove", "com.example.gone", "-y"]) as OrphansCommand)
                .clean("com.example.gone", in: scan, apps: [], scanner: scanner(in: directory), using: try service(in: directory), recordingIn: logs.removals, refusals: logs.refusals)
        }

        #expect(await moved(logs) == ["com.example.gone"])
        #expect(await logs.refusals.load().records.isEmpty)
        #expect(FileManager.default.fileExists(atPath: group.items[1].url.path(percentEncoded: false)))
        #expect(collected.notes == "\(Output.path(group.items[1].url)) stays: holds a wallet or a signing key\n")
    }

    // MARK: What the listings say

    /// The note is the other half of `isRecommended`: a folder that is kept must say why, and one that is
    /// suggested must not claim to be kept.
    @Test func everyKeptFolderSaysWhyAndEverySuggestedOneDoesNot() {
        let project = URL(filePath: "/Users/me/Developer/App", directoryHint: .isDirectory)
        func artifact(
            _ name: String,
            size: Int64? = 20,
            lastActivity: Date? = .now.addingTimeInterval(-ProjectArtifacts.recentlyActive * 2),
            certain: Bool = true,
            generic: Bool = false,
            environment: Bool = false,
            heldBack: HoldBack? = nil
        ) -> ProjectArtifact {
            var artifact = ProjectArtifact(
                url: project.appending(path: name),
                project: project,
                name: name,
                tool: "Xcode",
                size: size,
                lastActivity: lastActivity,
                hasGenericName: generic,
                isEnvironment: environment,
                heldBack: heldBack
            )
            artifact.lastActivityIsCertain = certain
            return artifact
        }
        let cases: [(ProjectArtifact, String)] = [
            (artifact("DerivedData"), "suggested"),
            (artifact("fresh", lastActivity: .now), "changed in the last 7 days, kept"),
            (artifact("huge", certain: false), "too large to tell when it last changed, kept"),
            (artifact("venv", environment: true), "installed packages, kept"),
            (artifact("build", generic: true), "name could mean anything, kept"),
            (artifact("slow", size: nil, heldBack: .notMeasured), "not measured in time, kept"),
            (artifact("Carthage", heldBack: .holdsRepository), "holds a repository, kept"),
        ]

        for (artifact, note) in cases {
            #expect(ProjectsCommand.note(for: artifact) == note)
            #expect(artifact.isRecommended == (note == "suggested"), "\(artifact.name) says \(note)")
        }
        #expect(ProjectsCommand.rows(for: cases.map(\.0)).map(\.count) == cases.map { _ in 4 })
        #expect(ProjectsCommand.rows(for: cases.map(\.0))[0] == ["20 bytes", "/Users/me/Developer/App/DerivedData", "Xcode", "suggested"])
    }

    /// The first copy is the one Peel suggests keeping, and it is the only row marked.
    @Test func marksOnlyTheCopyItSuggestsKeeping() async throws {
        let directory = try TemporaryDirectory()
        let contents = Data((0..<4_000).map { _ in UInt8.random(in: 0...255) })
        try directory.file("home/Documents/a.bin", contents: contents)
        try directory.file("home/Documents/a copy.bin", contents: contents)
        try directory.file("home/Pictures/a.bin", contents: contents)
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let scan = try await DuplicateFinder(homeDirectory: home).scan(DuplicateScanOptions(folders: [home]))
        let group = try #require(scan.groups.first)

        let rows = DuplicatesCommand.rows(for: group.files.map(\.url))

        #expect(rows.count == 3)
        #expect(rows.map(\.first) == ["keep", "", ""])
        #expect(rows[0][1] == Output.path(group.files[0].url))
        #expect(DuplicatesCommand.heading(for: group).hasPrefix("3 copies of 4 kB, "))
    }

    @Test func saysHowManyCopiesOfAFolderAndHowBigItIs() async throws {
        let directory = try TemporaryDirectory()
        let contents = Data((0..<4_000).map { _ in UInt8.random(in: 0...255) })
        for folder in ["home/Documents/Trip", "home/Pictures/Trip"] {
            try directory.file("\(folder)/photo.jpg", contents: contents)
        }
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let scan = try await DuplicateFinder(homeDirectory: home).scan(DuplicateScanOptions(folders: [home]))
        let group = try #require(scan.folderGroups.first)

        #expect(DuplicatesCommand.heading(for: group).hasPrefix("2 copies of a folder of 1 file, 4 kB, "))
        #expect(DuplicatesCommand.rows(for: group.folders.map(\.url)).map(\.first) == ["keep", ""])
    }

    /// An orphan group says what Peel makes of it, and never in a way that reads as a recommendation.
    @Test func saysWhatItMakesOfAnOrphanGroup() throws {
        let directory = try TemporaryDirectory()
        var group = OrphanGroup(identifier: "com.example.gone", items: [try orphan("com.example.gone", in: directory)])
        group.confidence = OrphanConfidence(level: .certain, reasons: [.nothingClaimsIt])

        #expect(OrphansCommand.heading(for: group).hasPrefix("com.example.gone  10 bytes  certain: "))
        #expect(OrphansCommand.rows(for: group) == [["10 bytes", Output.path(group.items[0].url)]])
    }

    /// The list says which files `--remove` leaves where they are, and why.
    @Test func saysWhichOrphanedFilesStayAndWhy() throws {
        let directory = try TemporaryDirectory()
        let group = OrphanGroup(identifier: "com.example.gone", items: [
            try orphan("com.example.gone", in: directory),
            try orphan("com.example.gone.wallet", in: directory, heldBack: .holdsAWallet),
            try orphan("com.example.gone.photos", in: directory, heldBack: .holdsALibrary),
        ])

        #expect(OrphansCommand.rows(for: group) == [
            ["10 bytes", Output.path(group.items[0].url)],
            ["10 bytes", Output.path(group.items[1].url), "stays: holds a wallet or a signing key"],
            ["10 bytes", Output.path(group.items[2].url), "stays: holds a photo, music, or video library"],
        ])
    }

    /// `peel orphans --json` says why `--remove` leaves each file it leaves, and which folders macOS kept Peel out of.
    @Test func theOrphansListSaysWhatStaysAndWhereItCouldNotLook() throws {
        let directory = try TemporaryDirectory()
        let group = OrphanGroup(identifier: "com.example.gone", items: [
            try orphan("com.example.gone", in: directory),
            try orphan("com.example.gone.wallet", in: directory, heldBack: .holdsAWallet),
        ])
        let unread = SearchLocation(kind: .containers, url: URL(filePath: "/Users/me/Library/Containers", directoryHint: .isDirectory))

        let json = try Output.jsonText(OrphansCommand.report(for: OrphanScan(groups: [group], unreadableLocations: [unread])))

        let report = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let files = try #require((report["groups"] as? [[String: Any]])?.first?["files"] as? [[String: Any]])
        #expect(files[0]["heldBack"] is NSNull)
        #expect(files[1]["heldBack"] as? String == "holdsAWallet")
        #expect(report["unreadableLocations"] as? [String] == ["/Users/me/Library/Containers"])
    }

    /// A chosen folder Peel didn't look in, such as a repository, is said, so an empty answer is not read as none.
    @Test func saysWhichFoldersItDidNotLookIn() {
        let skipped = URL(filePath: "/Users/me/Projects/app", directoryHint: .isDirectory)
        let scan = DuplicateScan(groups: [], unreadableLocations: [], skippedLocations: [skipped])

        let notes = DuplicatesCommand.notes(for: scan)

        #expect(notes.contains { $0.hasPrefix("Peel didn't look in /Users/me/Projects/app, so there may be duplicates there.") })
    }

    /// `peel duplicates --json` names the folders it couldn't read and the chosen folders it didn't look in.
    @Test func theDuplicatesReportSaysWhereItCouldNotLook() throws {
        let scan = DuplicateScan(
            groups: [],
            unreadableLocations: [URL(filePath: "/Users/me/Locked", directoryHint: .isDirectory)],
            skippedLocations: [URL(filePath: "/Users/me/Projects/app", directoryHint: .isDirectory)]
        )

        let json = try Output.jsonText(DuplicatesCommand.found(in: scan))

        let found = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(found["unreadableLocations"] as? [String] == ["/Users/me/Locked"])
        #expect(found["skippedLocations"] as? [String] == ["/Users/me/Projects/app"])
    }

    /// A chosen folder macOS kept Peel out of is said whatever the output, so an empty answer is not read as none.
    @Test func saysWhenItCouldNotLookInAChosenFolder() throws {
        let locked = URL(filePath: "/Users/me/Library/Safari", directoryHint: .isDirectory)
        let scan = ProjectArtifacts.Scan(artifacts: [], wasCutShort: true, unreadableLocations: [locked])

        #expect(ProjectsCommand.notes(for: scan) == [
            Output.fullDiskAccessNote,
            "There were more folders than Peel looks at in one go, so this list isn't all of them.",
        ])
        let json = try Output.jsonText(ProjectsCommand.report(for: scan))
        let report = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(report["unreadableLocations"] as? [String] == ["/Users/me/Library/Safari"])
    }

    /// `peel caches --json` says which folders `--remove` would take.
    @Test func theCachesListSaysWhatRemoveWouldTake() throws {
        let directory = try TemporaryDirectory()
        let tool = try environment("Rust", id: "rust", locations: [
            ("Library/Caches/cargo", .cache),
            ("Library/Models/llama", .models),
        ], in: directory)

        let json = try Output.jsonText(CachesCommand.records(for: [tool]))

        let records = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        let locations = try #require(records.first?["locations"] as? [[String: Any]])
        #expect(locations[0]["suggested"] as? Bool == true)
        #expect(locations[1]["suggested"] as? Bool == false)
    }

    /// A script reading `peel caches --json` gets, for each folder, where its tool documents it.
    @Test func tellsWhereEachCacheIsDocumented() throws {
        let directory = try TemporaryDirectory()
        let tool = try environment("Rust", id: "rust", locations: [("Library/Caches/cargo", .cache)], in: directory)

        let json = try Output.jsonText(CachesCommand.records(for: [tool]))

        #expect(json.contains("\"source\" : \"https://example.com/Library/Caches/cargo\""))
    }

    @Test func saysEveryCacheLocationWithItsKind() throws {
        let directory = try TemporaryDirectory()
        let tool = try environment("Rust", id: "rust", locations: [
            ("Library/Caches/cargo", .cache),
            ("Library/Models/llama", .models),
        ], in: directory)

        let rows = CachesCommand.rows(for: tool)

        #expect(rows.count == 2)
        #expect(rows[0] == ["30 bytes", Output.path(tool.locations[0].url), "cache"])
        #expect(rows[1][2] == "models, kept by default")
    }
}
