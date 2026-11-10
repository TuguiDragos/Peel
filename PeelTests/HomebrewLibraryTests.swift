import Foundation
import Observation
@testable import Peel
@testable import PeelCore
import Testing

/// A `brew` that answers for a made-up Homebrew and notes what it was asked.
private struct StandInBrew {
    let folder = FileManager.default.temporaryDirectory.appending(
        path: "PeelTests-brew-\(UUID().uuidString)", directoryHint: .isDirectory
    )

    var url: URL { folder.appending(path: "bin/brew") }

    private var log: URL { folder.appending(path: "asked") }

    /// `cleanup` and `update` are what its `brew cleanup` and `brew update` run, in shell.
    init(hasDefinitions: Bool = true, cleanup: String = ":", update: String = ":") throws {
        let manager = FileManager.default
        let path = folder.path(percentEncoded: false)
        let script = """
        #!/bin/sh
        echo "$1" >> '\(log.path(percentEncoded: false))'
        case "$1" in
          --version) echo 'Homebrew 7.0.0' ;;
          --prefix|--repository) echo '\(path)' ;;
          --cellar) echo '\(path)Cellar' ;;
          --caskroom) echo '\(path)Caskroom' ;;
          --cache) echo '\(path)cache' ;;
          info) echo '{"formulae":[],"casks":[]}' ;;
          cleanup) \(cleanup) ;;
          update) \(update) ;;
        esac

        """
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(script.utf8).write(to: url)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path(percentEncoded: false))
        guard hasDefinitions else { return }
        let definitions = folder.appending(path: "cache/api/internal/packages.made_up.jws.json")
        try manager.createDirectory(at: definitions.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: definitions)
    }

    func asked() throws -> [String] {
        try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    func goAway() {
        try? FileManager.default.removeItem(at: folder)
    }
}

@Suite(.serialized) struct HomebrewLibraryTests {
    @Test func aReadingAsksOnceWhatBrewShAnswersOnItsOwn() async throws {
        let brew = try StandInBrew()
        defer { brew.goAway() }
        let homebrew = HomebrewLibrary()

        await Homebrew.$standIn.withValue(brew.url) { await homebrew.refresh(includingReclaimable: true) }

        #expect(homebrew.installation?.version == "7.0.0")
        #expect(homebrew.hasAnswered)
        let asked = try brew.asked()
        for question in ["--version", "--prefix", "--cellar", "--repository", "--cache", "--caskroom"] {
            #expect(asked.count { $0 == question } == 1, "\(question), in \(asked)")
        }
    }

    @Test func saysWhoseHomebrewItIsWhileItsDefinitionsAreMissing() async throws {
        let brew = try StandInBrew(hasDefinitions: false)
        let path = brew.folder.path(percentEncoded: false)
        defer {
            _ = chmod(path, 0o755)
            brew.goAway()
        }
        #expect(chmod(path, 0o555) == 0)
        let homebrew = HomebrewLibrary()

        await Homebrew.$standIn.withValue(brew.url) { await homebrew.refresh() }

        #expect(homebrew.needsDefinitions)
        #expect(homebrew.installation?.version == "7.0.0")
        #expect(!homebrew.mayChange)
        #expect(homebrew.whyItCantChange?.command == "chmod u+w '\(PathPattern.comparablePath(of: brew.folder))'")
    }

    @Test func oneBrewsFigureDoesNotOutliveTheChoiceOfAnother() async throws {
        let first = try StandInBrew(cleanup: "echo '==> This operation would free approximately 2GB of disk space.'")
        let second = try StandInBrew(cleanup: "exit 1")
        defer {
            first.goAway()
            second.goAway()
        }
        let homebrew = HomebrewLibrary()

        await Homebrew.$standIn.withValue(first.url) { await homebrew.refresh(includingReclaimable: true) }
        #expect(homebrew.reclaimable == 2_000_000_000)
        await Homebrew.$standIn.withValue(second.url) { await homebrew.readAnotherBrew() }

        #expect(homebrew.reclaimable == nil)
    }

    @Test func aCommandPeelNeverStartedSaysSo() async throws {
        let brew = try StandInBrew()
        defer { brew.goAway() }
        // Nothing is read yet, so Peel can't tell which formulae the exclusions cover and starts no cleanup.
        let homebrew = HomebrewLibrary()

        let result = await Homebrew.$standIn.withValue(brew.url) { await homebrew.run(.cleanup, showsResult: false) }

        #expect(result?.ending == .notRun)
    }

    @Test func namesInHistoryOnlyTheCasksWhoseRecordMoved() throws {
        let caskroom = URL(filePath: "/opt/homebrew/Caskroom", directoryHint: .isDirectory)
        let casks = ["alpha", "beta", "gamma"].map { HomebrewPackage(name: $0, kind: .cask).kept(inCaskroom: caskroom) }
        let folder = try #require(casks[0].caskroomFolder)
        let trashed = TrashedItem(originalURL: folder, trashedURL: URL(filePath: "/Users/me/.Trash/alpha"), date: .now)

        #expect(HomebrewLibrary.source(of: casks, after: TrashResult(trashed: [trashed])).source == "alpha")
        #expect(HomebrewLibrary.source(of: casks, after: TrashResult()).source == "alpha, beta, gamma")
    }

    @Test(.homebrewWithItsDefinitions) func readsHomebrewAgainOnceItCheckedForNewVersions() async {
        let homebrew = HomebrewLibrary()
        await homebrew.refresh()
        let read = homebrew.revision
        let checked = await homebrew.lastUpdateCheck()

        #expect(await !homebrew.readAgain(ifHomebrewCheckedAt: checked))
        #expect(homebrew.revision == read)
        #expect(await homebrew.readAgain(ifHomebrewCheckedAt: (checked ?? .now) + 1))
        #expect(homebrew.revision == read + 1)
    }

    @Test(.homebrewWithItsDefinitions) func homebrewsOwnWorkEndsBeforePeelReadsWhatItChanged() async {
        // Nothing is read yet, so Upgrade All finds nothing to upgrade and runs no `brew upgrade`.
        let homebrew = HomebrewLibrary()

        let seen = await shownWhenTheReadingStarts(of: homebrew) { await homebrew.run(.upgradeAll, showsResult: false) }

        #expect(seen?.progress == nil)
        #expect(seen?.command == nil)
        #expect(seen?.isReading == true)
        #expect(seen?.isBusy == true)
        #expect(homebrew.runningCommand == nil && !homebrew.isReadingWhatChanged && homebrew.progress == nil)
    }

    @Test(.homebrewWithItsDefinitions) func whatAnUpgradeQuitOpensAgainBeforeAQuitOfPeelCanEnd() async {
        // Nothing is read yet, so Upgrade All finds nothing to upgrade and runs no `brew upgrade`.
        let homebrew = HomebrewLibrary()
        var wasReading: Bool?

        await homebrew.run(.upgradeAll, showsResult: false, reopening: { wasReading = homebrew.isReadingWhatChanged })

        #expect(wasReading == false, "an answer to a quit goes out before Homebrew is read again")
    }

    @Test func aCommandThatReplacesPeelIsToldAboveEveryPage() async throws {
        let program = try madeUpProgram()
        defer { try? FileManager.default.removeItem(atPath: program) }
        let brew = try StandInBrew(update: "rm '\(program)'; echo new > '\(program)'")
        defer { brew.goAway() }
        let homebrew = HomebrewLibrary(ownProgram: { OwnProgram(path: program) })

        await Homebrew.$standIn.withValue(brew.url) { await homebrew.run(.update) }

        #expect(homebrew.replacedPeel != nil)
        #expect(homebrew.result == nil)
    }

    @Test func aPageThatShowsItsOwnResultStillLeavesAReplacedPeelToTheWindow() async throws {
        let program = try madeUpProgram()
        defer { try? FileManager.default.removeItem(atPath: program) }
        let brew = try StandInBrew(update: "rm '\(program)'; echo new > '\(program)'")
        defer { brew.goAway() }
        let homebrew = HomebrewLibrary(ownProgram: { OwnProgram(path: program) })

        await Homebrew.$standIn.withValue(brew.url) { await homebrew.run(.update, showsResult: false) }

        #expect(homebrew.replacedPeel != nil)
    }

    @Test func aCommandThatLeavesPeelAloneShowsItsResultOnItsPage() async throws {
        let program = try madeUpProgram()
        defer { try? FileManager.default.removeItem(atPath: program) }
        let brew = try StandInBrew()
        defer { brew.goAway() }
        let homebrew = HomebrewLibrary(ownProgram: { OwnProgram(path: program) })

        await Homebrew.$standIn.withValue(brew.url) { await homebrew.run(.update) }

        #expect(homebrew.replacedPeel == nil)
        #expect(homebrew.result != nil)
    }

    @Test func aProgramReplacedBeforeTheCommandIsNotTheCommandsDoing() async throws {
        let program = try madeUpProgram()
        defer { try? FileManager.default.removeItem(atPath: program) }
        let brew = try StandInBrew()
        defer { brew.goAway() }
        try FileManager.default.removeItem(atPath: program)
        try Data("rebuilt".utf8).write(to: URL(filePath: program))
        let homebrew = HomebrewLibrary(ownProgram: { OwnProgram(path: program) })

        await Homebrew.$standIn.withValue(brew.url) { await homebrew.run(.update) }

        #expect(homebrew.replacedPeel == nil)
    }

    private func madeUpProgram() throws -> String {
        let url = FileManager.default.temporaryDirectory.appending(path: "PeelTests-program-\(UUID().uuidString)")
        try Data("old".utf8).write(to: url)
        return url.path(percentEncoded: false)
    }

    @Test(.homebrewWithItsDefinitions) func aReadingIsLeftForTheEndOfWhatHomebrewIsDoing() async {
        let homebrew = HomebrewLibrary()
        homebrew.runningCommand = .upgradeAll
        let before = homebrew.revision

        await homebrew.refresh()

        #expect(homebrew.revision == before)
    }

    @Test(.homebrewWithItsDefinitions) func forgetsMovesEndBeforePeelReadsWhatChanged() async {
        let homebrew = HomebrewLibrary()
        // A made-up cask has no folder in the Caskroom, so nothing moves.
        let cask = HomebrewPackage(name: "org-example-gone", kind: .cask, installedVersion: "1.0")

        let seen = await shownWhenTheReadingStarts(of: homebrew) { _ = await homebrew.forget([cask]) { _ in } }

        #expect(seen?.forgetting.isEmpty == true)
        #expect(seen?.isReading == true)
        #expect(seen?.isBusy == true)
        #expect(!homebrew.isForgetting && !homebrew.isReadingWhatChanged)
    }

    private struct Shown {
        let progress: String?
        let command: HomebrewLibrary.Command?
        let forgetting: Set<HomebrewPackage.ID>
        let isReading: Bool
        let isBusy: Bool
    }

    @MainActor private final class Seen {
        var shown: Shown?
    }

    private func shownWhenTheReadingStarts(
        of homebrew: HomebrewLibrary,
        during work: () async -> Void
    ) async -> Shown? {
        let seen = Seen()
        withObservationTracking {
            _ = homebrew.isScanning
        } onChange: {
            MainActor.assumeIsolated {
                seen.shown = Shown(
                    progress: homebrew.progress, command: homebrew.commandHomebrewRuns,
                    forgetting: homebrew.casksBeingForgotten, isReading: homebrew.isReadingWhatChanged,
                    isBusy: homebrew.runningCommand != nil || homebrew.isForgetting
                )
            }
        }
        await work()
        return seen.shown
    }
}

extension Trait where Self == ConditionTrait {
    /// A test of this Mac's own Homebrew: a Mac without one, or without its definitions, reports it skipped.
    static var homebrewWithItsDefinitions: Self {
        .enabled("Homebrew is on this Mac with its own copy of its definitions") {
            guard Homebrew.executableURL != nil else { return false }
            return await Homebrew.hasLocalDefinitions()
        }
    }
}
