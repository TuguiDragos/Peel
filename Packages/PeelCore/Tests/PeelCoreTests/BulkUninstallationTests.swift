import Foundation
@testable import PeelCore
import Testing

struct BulkUninstallationTests {
    private func app(_ identifier: String, _ name: String) -> InstalledApp {
        InstalledApp(url: URL(filePath: "/Applications/\(name).app"), bundleIdentifier: identifier, name: name)
    }

    private func leftover(_ path: String, size: Int64, sharedWith: [String] = [], confidence: MatchConfidence = .certain) -> Leftover {
        Leftover(
            url: URL(filePath: path),
            kind: .applicationSupport,
            match: LeftoverMatch(reason: .bundleIdentifier, confidence: confidence, sharedWith: sharedWith),
            size: size,
            isMeasured: true,
            requiresPrivileges: false
        )
    }

    private func uninstallation(_ app: InstalledApp, _ leftovers: [Leftover], appSize: Int64 = 1000) -> Uninstallation {
        Uninstallation(
            app: app,
            appSize: appSize,
            appRequiresPrivileges: false,
            scan: LeftoverScan(leftovers: leftovers, unreadableLocations: [])
        )
    }

    /// A checkbox can select what a row lets the person choose, by the rule of an app's own page: nothing Peel
    /// leaves alone or with something excluded inside, nothing that needs the helper while it cannot act, no app
    /// macOS keeps or the helper may not move, and nothing of an excluded app or of Peel. Everything Peel suggests
    /// is among it.
    @Test func selectsOnlyWhatARowLetsThePersonChoose() {
        let notes = app("com.example.notes", "Notes")
        let own = leftover("/Users/x/Library/Caches/com.example.notes", size: 100)
        let keys = leftover("/Users/x/Library/Application Support/Notes Keys", size: 100).heldBack(.holdsKeys)
        let excluded = leftover("/Users/x/Library/Application Support/Notes Excluded", size: 100).heldBack(.holdsAnExclusion)
        let needsHelper = Uninstallation(
            app: notes, appSize: 1000, appRequiresPrivileges: true,
            scan: LeftoverScan(leftovers: [own, keys, excluded], unreadableLocations: [])
        )
        let chess = InstalledApp(url: URL(filePath: "/System/Applications/Chess.app"), bundleIdentifier: "com.apple.Chess", name: "Chess", isSystemProtected: true)
        let chessData = leftover("/Users/x/Library/Containers/com.apple.Chess", size: 100)
        var beyond = uninstallation(app("com.example.scribbler", "Scribbler"), [])
        beyond.isAppBeyondTheHelper = true
        var excludedApp = uninstallation(app("com.example.excluded", "Excluded"), [])
        excludedApp.isExcluded = true
        let peel = uninstallation(app("com.tuguidragos.Peel", "Peel"), [leftover("/Users/x/Library/Caches/com.tuguidragos.Peel", size: 100)])
        let bulk = BulkUninstallation(uninstallations: [needsHelper, uninstallation(chess, [chessData]), beyond, excludedApp, peel])

        #expect(bulk.selectable(canUseHelper: false) == [own.url, chessData.url])
        #expect(bulk.selectable(canUseHelper: true) == [notes.url, own.url, chessData.url])
        for canUseHelper in [false, true] {
            #expect(bulk.suggestedSelection(canUseHelper: canUseHelper).isSubset(of: bulk.selectable(canUseHelper: canUseHelper)))
        }
    }

    /// An app stays when a copy of it is not selected. Two copies share their files, and neither bundle is one of
    /// them.
    @Test func namesTheAppsThatStayAndTheirFiles() {
        let notes = app("com.example.notes", "Notes")
        let copy = InstalledApp(url: URL(filePath: "/Users/x/Applications/Notes.app"), bundleIdentifier: notes.bundleIdentifier, name: notes.name)
        let mail = app("com.example.mail", "Mail")
        let own = leftover("/Users/x/Library/Caches/com.example.notes", size: 100)
        let shared = leftover("/Users/x/Library/Group Containers/group.com.example", size: 100)
        let bulk = BulkUninstallation(uninstallations: [uninstallation(notes, [own, shared]), uninstallation(copy, [own]), uninstallation(mail, [shared])])

        #expect(bulk.staying(selected: [notes.url, copy.url, mail.url]).isEmpty)
        #expect(bulk.staying(selected: [notes.url, mail.url]) == [notes.bundleIdentifier])
        #expect(bulk.staying(selected: [notes.url, copy.url]) == [mail.bundleIdentifier])
        #expect(bulk.files(of: notes.bundleIdentifier) == [own.url, shared.url])
        #expect(bulk.files(of: mail.bundleIdentifier) == [shared.url])
    }

    /// A batch keeps the order an app's own page keeps: what could not be measured first among the leftovers, since
    /// it is most likely the biggest, then the largest. The apps come after their leftovers.
    @Test func listsWhatCouldNotBeMeasuredFirst() {
        let notes = app("com.example.notes", "Notes")
        var slow = leftover("/Users/x/Library/Application Support/Notes", size: 0)
        slow = Leftover(url: slow.url, kind: slow.kind, match: slow.match, size: 0, isMeasured: false, requiresPrivileges: false)
        let bulk = BulkUninstallation(uninstallations: [
            uninstallation(notes, [leftover("/Users/x/Library/Caches/com.example.notes", size: 900), slow]),
        ])

        #expect(bulk.items.map(\.url.lastPathComponent) == ["Notes", "com.example.notes", "Notes.app"])
    }

    @Test func listsAFileSharedByTwoChosenAppsOnce() throws {
        let word = app("com.microsoft.Word", "Word")
        let excel = app("com.microsoft.Excel", "Excel")
        let shared = "/Users/x/Library/Group Containers/UBF8T346G9.Office"

        let bulk = BulkUninstallation(uninstallations: [
            uninstallation(word, [leftover(shared, size: 500, sharedWith: ["com.microsoft.Excel"])]),
            uninstallation(excel, [leftover(shared, size: 500, sharedWith: ["com.microsoft.Word"])]),
        ])

        let item = try #require(bulk.items.first { $0.url.path(percentEncoded: false) == shared })
        #expect(bulk.items.filter { $0.url.path(percentEncoded: false) == shared }.count == 1)
        #expect(item.apps.sorted() == ["com.microsoft.Excel", "com.microsoft.Word"])
        #expect(item.sharedWithOthers.isEmpty)
        #expect(item.isRecommended)
    }

    /// One folder claimed by two chosen apps: a cask names it outright for one, and for the other the scanner
    /// found a repository in it and took the checkmark away. The checkmark stays away whichever app comes first.
    @Test func aCheckmarkOneAppTookAwayStaysAwayWhateverTheOrder() throws {
        let tool = app("com.example.tool", "Tool")
        let editor = app("com.example.editor", "Editor")
        let folder = "/Users/x/Library/Application Support/Shared Work"
        let named = Leftover(
            url: URL(filePath: folder), kind: .applicationSupport,
            match: LeftoverMatch(reason: .homebrewCask, confidence: .certain, sharedWith: []), size: 100, isMeasured: true, requiresPrivileges: false
        )
        let held = Leftover(
            url: URL(filePath: folder), kind: .applicationSupport,
            match: LeftoverMatch(reason: .name, confidence: .likely, sharedWith: [], heldBack: .holdsRepository), size: 100, isMeasured: true, requiresPrivileges: false
        )

        for uninstallations in [[uninstallation(tool, [named]), uninstallation(editor, [held])], [uninstallation(editor, [held]), uninstallation(tool, [named])]] {
            let item = try #require(BulkUninstallation(uninstallations: uninstallations).items.first { $0.url.path(percentEncoded: false) == folder })
            #expect(!item.isRecommended, "selected with \(uninstallations[0].app.name) first")
            #expect(item.match?.heldBack == .holdsRepository)
            #expect(item.match?.confidence == .likely)
        }
    }

    @Test func leavesFilesSharedWithAppsThatStayBehind() {
        let firefox = app("org.mozilla.firefox", "Firefox")
        let profiles = "/Users/x/Library/Application Support/Firefox"

        let bulk = BulkUninstallation(uninstallations: [
            uninstallation(firefox, [leftover(profiles, size: 800, sharedWith: ["org.mozilla.nightly"])]),
        ])

        let item = bulk.items.first { $0.url.path(percentEncoded: false) == profiles }
        #expect(item?.sharedWithOthers == ["org.mozilla.nightly"])
        #expect(item?.isRecommended == false)
        #expect(!bulk.suggestedSelection(canUseHelper: true).contains(URL(filePath: profiles)))
    }

    /// An excluded app chosen along with others stays: never selected, and not moved even when selected by hand.
    @Test func leavesAnExcludedAppOutOfTheBatch() {
        let kept = app("com.example.kept", "Kept")
        let gone = app("com.example.gone", "Gone")
        var excluded = uninstallation(kept, [])
        excluded.isExcluded = true
        let bulk = BulkUninstallation(uninstallations: [
            excluded,
            uninstallation(gone, [leftover("/Users/x/Library/Caches/com.example.gone", size: 10)]),
        ])

        let keptItem = bulk.items.first { $0.url == kept.url }
        #expect(keptItem?.isExcluded == true)
        #expect(keptItem?.isRecommended == false)
        #expect(!bulk.suggestedSelection(canUseHelper: true).contains(kept.url))
        #expect(!bulk.removalOrder(of: [kept.url, gone.url]).contains(kept.url))
        #expect(bulk.removalOrder(of: [kept.url, gone.url]) == [gone.url])
        #expect(bulk.total == SizeTotal(known: 1010, isComplete: true))
    }

    /// An app macOS keeps, chosen along with others: neither it nor what it holds is selected, shared or not.
    @Test func ticksNothingOfAnAppMacOSKeeps() {
        let notes = InstalledApp(url: URL(filePath: "/System/Applications/Notes.app"), bundleIdentifier: "com.apple.Notes", name: "Notes", isSystemProtected: true)
        let gone = app("com.example.gone", "Gone")
        let store = leftover("/Users/x/Library/Group Containers/group.com.apple.notes", size: 50)
        let shared = leftover("/Users/x/Library/Caches/shared", size: 5)
        let bulk = BulkUninstallation(uninstallations: [
            uninstallation(notes, [store, shared]),
            uninstallation(gone, [shared, leftover("/Users/x/Library/Caches/com.example.gone", size: 10)]),
        ])

        #expect(bulk.suggestedSelection(canUseHelper: true) == [gone.url, URL(filePath: "/Users/x/Library/Caches/com.example.gone")])
        // The app macOS keeps is not part of what could go: the guard refuses it.
        #expect(bulk.total == SizeTotal(known: 1_000 + 50 + 5 + 10, isComplete: true))
    }

    /// The total counts only what can be moved. A container whose documents the guard refuses is left out, and a
    /// folder that was not measured makes the total incomplete ("Over"), as on an app's own page.
    @Test func countsWhatCanGoAndDoesNotReadAnUnknownSizeAsZero() {
        let gone = app("com.example.gone", "Gone")
        let refused = Leftover(
            url: URL(filePath: "/Users/x/Library/Containers/com.example.gone"),
            kind: .containers,
            match: LeftoverMatch(reason: .bundleIdentifier, confidence: .certain, sharedWith: []).forReview(.holdsDocuments),
            size: 700,
            isMeasured: true,
            requiresPrivileges: false
        )
        let unmeasured = Leftover(
            url: URL(filePath: "/Users/x/Library/Application Support/com.example.gone"),
            kind: .applicationSupport,
            match: LeftoverMatch(reason: .bundleIdentifier, confidence: .certain, sharedWith: []).forReview(.notMeasured),
            size: 0,
            isMeasured: false,
            requiresPrivileges: false
        )
        let bulk = BulkUninstallation(uninstallations: [
            uninstallation(gone, [refused, unmeasured, leftover("/Users/x/Library/Caches/com.example.gone", size: 10)]),
        ])

        #expect(bulk.total == SizeTotal(known: 1_000 + 10, isComplete: false))
    }

    @Test func removesLeftoversBeforeTheAppsThemselves() {
        let first = app("com.example.one", "One")
        let second = app("com.example.two", "Two")
        let bulk = BulkUninstallation(uninstallations: [
            uninstallation(first, [leftover("/Users/x/Library/Caches/com.example.one", size: 10)]),
            uninstallation(second, [leftover("/Users/x/Library/Caches/com.example.two", size: 20)]),
        ])

        let selection = bulk.suggestedSelection(canUseHelper: true)
        #expect(selection.count == 4)
        let order = bulk.removalOrder(of: selection).map { $0.lastPathComponent }
        #expect(order == ["com.example.two", "com.example.one", "One.app", "Two.app"])
        #expect(bulk.total == SizeTotal(known: 2030, isComplete: true))
    }
}
