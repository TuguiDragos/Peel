import ArgumentParser
import Foundation
@testable import PeelCommandLine
@testable import PeelCore
import Testing

struct CommandLineTests {
    /// A Brewfile is written from Homebrew's own list, and Homebrew is not asked when it has no copy of its
    /// definitions on this Mac. Telling someone without Homebrew to run `brew update` names a command they
    /// can't run.
    @Test func saysWhyHomebrewHasNoListInTheWayThatFits() {
        #expect(InventoryCommand.noDefinitions(isInstalled: false) == "Homebrew isn't installed.")
        #expect(InventoryCommand.noDefinitions(isInstalled: true) == "Homebrew has no list of packages on this Mac. Run `brew update` first.")
    }

    @Test func parsesByteSizes() {
        #expect(ByteSize(argument: "2048")?.bytes == 2_048)
        #expect(ByteSize(argument: "500KB")?.bytes == 500_000)
        #expect(ByteSize(argument: "1.5gb")?.bytes == 1_500_000_000)
        #expect(ByteSize(argument: "10 M")?.bytes == 10_000_000)
        #expect(ByteSize(argument: "3T")?.bytes == 3_000_000_000_000)
        #expect(ByteSize(argument: "-1MB") == nil)
        #expect(ByteSize(argument: "big") == nil)
        #expect(ByteSize(argument: "MB") == nil)
    }

    /// A terminal gives an emoji and a wide East Asian character two cells, and a combining mark none.
    @Test func alignsColumnsByTerminalCells() {
        #expect(Output.paddedCells([["📷 Photos", "1 kB", "x"], ["Café", "10 kB", "y"]]) == ["📷 Photos  1 kB   x", "Café       10 kB  y"])
        #expect(Output.paddedCells([["日本語", "a"], ["abc", "b"], ["e\u{301}", "c"], ["🇷🇴❤️", "d"]]) == [
            "日本語  a", "abc     b", "e\u{301}       c", "🇷🇴❤️    d",
        ])
    }

    /// The app ships `Support/peel.1`, which `Scripts/generate_manual.py` writes from the tool. A command added to
    /// the tool without the page being written again would be missing from `man peel`.
    @Test func theManualPageNamesEveryCommand() throws {
        let page = try String(contentsOf: StringCatalogTests.repository.appending(path: "Support/peel.1"), encoding: .utf8)
        func names(of command: any ParsableCommand.Type) -> [String] {
            command.configuration.subcommands.flatMap { [$0.configuration.commandName ?? ""] + names(of: $0) }
        }

        let missing = names(of: PeelCommand.self).filter { !page.contains(".It Em \($0)\n") }

        #expect(missing.isEmpty, "Missing from Support/peel.1: \(missing). Run Scripts/generate_manual.py after a Debug build.")
    }

    /// A table is written at once, rather than a row at a time: a search lists up to 2,000 rows.
    @Test func writesATableAtOnce() {
        let collected = Output.Collected()
        Output.$collected.withValue(collected) {
            Output.table([["1 kB", "/a"], ["2 kB", "/b"], ["3 kB", "/c"]], indent: "  ")
        }

        #expect(collected.writes == 1)
        #expect(collected.output == "  1 kB  /a\n  2 kB  /b\n  3 kB  /c\n")
    }

    /// `peel uninstall /applications/example.app`, or a link to the app, finds the installed app itself: never
    /// the link, and never a second record of the same bundle, which would share every file with the first.
    @Test func findsAnInstalledAppUnderAnotherSpelling() throws {
        let directory = try TemporaryDirectory()
        let bundle = try directory.directory("Applications/Example.app")
        let link = directory.url.appending(path: "Example Link.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: bundle)
        let installed = InstalledApp(url: bundle, bundleIdentifier: "com.example.app", name: "Example")

        #expect(try AppLookup.app(matching: link.path(percentEncoded: false), in: [installed]) == installed)
        #expect(try AppLookup.app(matching: directory.url.appending(path: "applications/example.app").path(percentEncoded: false), in: [installed]) == installed)
    }

    /// `peel` runs with the user's locale, and under Turkish rules `iina` does not match `IINA`. App names are
    /// compared without the locale's rules.
    @Test func findsAnAppByNameWhateverTheLocalesRules() throws {
        #expect("IINA".compare("iina", options: .caseInsensitive, range: nil, locale: Locale(identifier: "tr_TR")) != .orderedSame)
        let iina = InstalledApp(url: URL(filePath: "/Applications/IINA.app", directoryHint: .isDirectory), bundleIdentifier: "com.colliderli.iina", name: "IINA")
        let firefox = InstalledApp(url: URL(filePath: "/Applications/Firefox.app", directoryHint: .isDirectory), bundleIdentifier: "org.mozilla.firefox", name: "Firefox")
        #expect(try AppLookup.app(matching: "iina", in: [iina, firefox]) == iina)
        #expect(try AppLookup.app(matching: "FIREFOX", in: [iina, firefox]) == firefox)
    }

    @Test func findsAppsByPathIdentifierAndName() throws {
        let notes = InstalledApp(url: URL(filePath: "/Applications/Notes Pro.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.NotesPro", name: "Notes Pro")
        let editor = InstalledApp(url: URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.editor", name: "Editor")
        let otherEditor = InstalledApp(url: URL(filePath: "/Users/me/Applications/Editor.app", directoryHint: .isDirectory), bundleIdentifier: "org.example.editor", name: "Editor")
        let apps = [notes, editor, otherEditor]

        #expect(try AppLookup.app(matching: "/Applications/Notes Pro.app/", in: apps) == notes)
        #expect(try AppLookup.app(matching: "COM.EXAMPLE.NOTESPRO", in: apps) == notes)
        #expect(try AppLookup.app(matching: "notes pro", in: apps) == notes)
        #expect(try AppLookup.app(matching: "com.example.editor", in: apps) == editor)
        #expect(throws: AppLookup.Failure.ambiguous("editor", ["/Applications/Editor.app", "/Users/me/Applications/Editor.app"])) {
            try AppLookup.app(matching: "editor", in: apps)
        }
        #expect(throws: AppLookup.Failure.notFound("Missing")) {
            try AppLookup.app(matching: "Missing", in: apps)
        }

        // One identifier on two bundles, such as a copy kept beside the one in use. The lookup refuses to guess:
        // whichever sorts first may be the app the user wants to keep.
        let copy = InstalledApp(
            url: URL(filePath: "/Users/me/Applications/Editor copy.app", directoryHint: .isDirectory),
            bundleIdentifier: "com.example.editor",
            name: "Editor copy"
        )
        #expect(throws: AppLookup.Failure.ambiguous("com.example.editor", ["/Applications/Editor.app", "/Users/me/Applications/Editor copy.app"])) {
            try AppLookup.app(matching: "com.example.editor", in: apps + [copy])
        }
    }

    @Test func refusesAnAppExcludedInSettings() throws {
        let editor = InstalledApp(url: URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.editor", name: "Editor")

        try AppLookup.refuseIfExcluded(editor, by: .none)
        for exclusions in [Exclusions(bundleIdentifiers: ["com.example.editor"]), Exclusions(paths: [editor.url])] {
            #expect(throws: AppLookup.Failure.excluded("Editor")) {
                try AppLookup.refuseIfExcluded(editor, by: exclusions)
            }
        }
        #expect(throws: AppLookup.Failure.exclusionsUnreadable("/tmp/exclusions.json")) {
            try AppLookup.refuseIfExcluded(editor, by: .unreadable, savedAt: URL(filePath: "/tmp/exclusions.json"))
        }
    }

    /// A listing still runs while the exclusions can't be read, since nothing moves meanwhile, but it warns
    /// that it may show what the user excluded.
    @Test func aListingSaysWhenTheExclusionsCannotBeRead() throws {
        #expect(UnreadableExclusions.note(for: .none) == nil)
        #expect(UnreadableExclusions.note(for: Exclusions(bundleIdentifiers: ["com.example.editor"])) == nil)
        let note = try #require(UnreadableExclusions.note(for: .unreadable, savedAt: URL(filePath: "/tmp/exclusions.json")))
        #expect(note.contains("/tmp/exclusions.json"))
    }

    @Test func findsAppsByTheirBundleName() throws {
        let notes = InstalledApp(url: URL(filePath: "/Applications/Notes Pro.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.NotesPro", name: "Notes Pro")
        let code = InstalledApp(url: URL(filePath: "/Applications/Visual Studio Code.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.code", name: "Code")
        let editor = InstalledApp(url: URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.editor", name: "Editor")
        let otherEditor = InstalledApp(url: URL(filePath: "/Users/me/Applications/Editor.app", directoryHint: .isDirectory), bundleIdentifier: "org.example.editor", name: "Editor")
        let apps = [notes, code, editor, otherEditor]

        // Nothing is read from the disk, so a `Missing.app` in the folder the tests run from cannot change the result.
        func lookUp(_ query: String) throws(AppLookup.Failure) -> InstalledApp {
            try AppLookup.app(matching: query, in: apps, inspect: { _ in nil })
        }

        #expect(try lookUp("Notes Pro.app") == notes)
        #expect(try lookUp("NOTES PRO.APP") == notes)
        #expect(try lookUp("Visual Studio Code.app") == code)
        #expect(try lookUp("Visual Studio Code") == code)
        #expect(try lookUp("Code") == code)
        #expect(throws: AppLookup.Failure.ambiguous("Editor.app", ["/Applications/Editor.app", "/Users/me/Applications/Editor.app"])) {
            try lookUp("Editor.app")
        }
        #expect(throws: AppLookup.Failure.notFound("Missing.app")) {
            try lookUp("Missing.app")
        }
    }

    @Test func spellsAPathTheSameWayAsTheInventory() {
        let app = InstalledApp(url: URL(filePath: NSHomeDirectory() + "/Applications/Editor.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.editor", name: "Editor")
        let inventoried = Inventory.build(apps: [app]).entries[0].path

        #expect(Output.path(app.url) == inventoried)
        #expect(AppRecord(app).path == inventoried)
        #expect(Output.path(URL(filePath: "/Applications/Editor.app/", directoryHint: .isDirectory)) == "/Applications/Editor.app")
    }

    @Test func writesEveryKeyOfEveryRecord() throws {
        let known = InstalledApp(url: URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.editor", name: "Editor", version: "1.0")
        let unknown = InstalledApp(url: URL(filePath: "/Applications/Widget.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.widget", name: "Widget")
        let json = try Output.jsonText([AppRecord(known), AppRecord(unknown)])
        let records = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])

        #expect(records.count == 2)
        #expect(Set(records[0].keys) == Set(records[1].keys))
        #expect(records[1]["version"] is NSNull)
    }

    /// What `peel uninstall` moves is in the same History the app shows, as one batch that can be put back.
    @Test func recordsWhatItMovedInTheAppsHistory() async throws {
        let directory = try TemporaryDirectory()
        let log = RemovalLog(url: directory.url.appending(path: "Peel/removals.json"))
        let app = URL(filePath: "/Applications/Editor.app")
        let cache = URL(filePath: "/Users/me/Library/Caches/com.example.editor")
        let result = TrashResult(trashed: [
            TrashedItem(originalURL: cache, trashedURL: URL(filePath: "/Users/me/.Trash/com.example.editor"), date: .now),
            TrashedItem(originalURL: app, trashedURL: URL(filePath: "/Users/me/.Trash/Editor.app"), date: .now),
        ])

        #expect(await Removals.record(result, from: "Editor", sizes: [app: 9_000, cache: 100], tool: "applications", in: log))

        let records = try #require(await RemovalLog(url: log.url).load().records)
        #expect(records.count == 2)
        #expect(Set(records.map(\.batch)).count == 1)
        #expect(records.allSatisfy { $0.source == "Editor" && $0.tool == "applications" })
        #expect(Set(records.map(\.size)) == [9_000, 100])
        #expect(await Removals.record(TrashResult(), from: "Editor", sizes: [:], tool: "applications", in: log))
    }

    /// A folder that did not answer in time has no known size, so it is written as `null`. A script would add up
    /// a zero as if it were real.
    @Test func writesAnUnknownSizeAsNull() throws {
        let match = LeftoverMatch(reason: .bundleIdentifier, confidence: .certain, sharedWith: [])
        let folder = URL(filePath: "/Users/me/Library/Application Support/Editor")
        let measured = Leftover(url: folder, kind: .applicationSupport, match: match, size: 4_096, isMeasured: true, requiresPrivileges: false)
        let unmeasured = Leftover(url: folder, kind: .applicationSupport, match: match.forReview(.notMeasured), size: 0, isMeasured: false, requiresPrivileges: false)

        let json = try Output.jsonText([LeftoverRecord(measured), LeftoverRecord(unmeasured)])
        let records = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        #expect(records[0]["size"] as? Int == 4_096)
        #expect(records[1]["size"] is NSNull)
        #expect(Set(records[0].keys) == Set(records[1].keys))
    }

    /// `peel leftovers --json` names the folders macOS kept Peel out of, where the app may have left more.
    @Test func theLeftoversReportSaysWhereItCouldNotLook() throws {
        let app = InstalledApp(url: URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.editor", name: "Editor")
        let unread = SearchLocation(kind: .containers, url: URL(filePath: "/Users/me/Library/Containers", directoryHint: .isDirectory))

        let report = LeftoversCommand.Report(app: app, appSize: nil, leftovers: [], unreadableLocations: [unread])

        let json = try #require(JSONSerialization.jsonObject(with: Data(try Output.jsonText(report).utf8)) as? [String: Any])
        #expect(json["unreadableLocations"] as? [String] == ["/Users/me/Library/Containers"])
        #expect(json["appSize"] is NSNull)
    }

    /// `peel uninstall --json` says, once it is done, what was to move and what stayed and why, what moved, and
    /// what failed and why, with every key in every record.
    @Test func theUninstallReportSaysWhatMovedWhatStayedAndWhy() throws {
        let app = URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory)
        let support = URL(filePath: "/Users/me/Library/Application Support/Editor", directoryHint: .isDirectory)
        let caches = URL(filePath: "/Users/me/Library/Caches/com.example.editor", directoryHint: .isDirectory)
        let plan = UninstallPlan(app: app, items: [
            UninstallPlan.Item(url: app, size: 4_096, refusal: nil),
            UninstallPlan.Item(url: support, size: nil, refusal: nil),
            UninstallPlan.Item(url: caches, size: 10, refusal: .protectedLocation),
        ], needsAdministrator: 1, needsReview: 2)
        let result = TrashResult(trashed: [], failures: [TrashFailure(url: support, reason: .failed("disk full"))])
        let editor = InstalledApp(url: app, bundleIdentifier: "com.example.editor", name: "Editor")

        let json = try Output.jsonText(UninstallCommand.report(app: editor, plan: plan, result: result, privacy: .reset, unreadable: []))

        let report = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let items = try #require(report["items"] as? [[String: Any]])
        #expect(items.map { $0["stays"] as? String } == [nil, nil, "protected-location"])
        #expect(items[0]["stays"] is NSNull)
        #expect(items[1]["size"] is NSNull)
        let failed = try #require(report["failed"] as? [[String: Any]])
        #expect(failed.first?["reason"] as? String == "failed")
        #expect(failed.first?["detail"] as? String == "disk full")
        #expect(report["dryRun"] as? Bool == false)
        #expect(report["privacyReset"] as? Bool == true)
        #expect(report["needsAdministrator"] as? Int == 1)
        #expect(report["needsReview"] as? Int == 2)
        #expect(report["unreadableLocations"] as? [String] == [])

        let dryRun = try Output.jsonText(UninstallCommand.report(app: editor, plan: plan, result: nil, privacy: nil, unreadable: []))
        let planned = try #require(JSONSerialization.jsonObject(with: Data(dryRun.utf8)) as? [String: Any])
        #expect(planned["dryRun"] as? Bool == true)
        #expect(planned["moved"] as? [String] == [])
        #expect(planned["privacyReset"] is NSNull)
    }

    /// A script adds sizes up, so an unknown size is `null` under the same key: never zero, and never a missing
    /// key. In JSON a total with an unknown part is `null` too, and in text it reads "over" the known part.
    @Test func writesASizeNobodyKnowsAsNull() throws {
        struct Row: Encodable {
            let size: MeasuredSize
        }
        let rows = [Row(size: MeasuredSize(4_096)), Row(size: MeasuredSize(nil)), Row(size: MeasuredSize(SizeTotal([10, nil])))]
        let records = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(rows)) as? [[String: Any]])

        #expect(records[0]["size"] as? Int == 4_096)
        #expect(records[1]["size"] is NSNull)
        #expect(records[2]["size"] is NSNull)
        #expect(Output.size(Int64?.none) == "unknown")
        #expect(Output.size(SizeTotal([13_400_000, nil])) == "over 13.4 MB")
        #expect(Output.size(SizeTotal([nil])) == "unknown")
        #expect(Output.size(SizeTotal([13_400_000])) == "13.4 MB")
    }

    @Test func writesNumbersAndDaysTheSameWayInEveryRegion() {
        #expect(Output.size(13_400_000) == "13.4 MB")
        #expect(Output.number(2_000) == "2000")
        #expect(Output.count(1_500, "file", "files") == "1500 files")
        // The time zone is passed in, since the same moment falls on different days in UTC and in New Zealand.
        let noon = Date(timeIntervalSince1970: 1_789_646_400)
        #expect(Output.day(noon, timeZone: TimeZone(identifier: "UTC")!) == "2026-09-17")
        #expect(Output.day(noon, timeZone: TimeZone(identifier: "Pacific/Auckland")!) == "2026-09-18")
        #expect(Output.day(noon, timeZone: .current) == Inventory.day(noon))
        // Zero is written as a number: with `spellsOutZero` on, its default, it would read "Zero kB".
        #expect(Output.size(0) == "0 bytes")
    }

    /// Names and paths come from other developers' bundles. A newline would split a row into two for a script
    /// reading it, and an escape sequence could rewrite the line above the list the user is asked to confirm.
    @Test func printsNamesWithoutTheControlCharactersInThem() {
        #expect(Output.plain("Editor\u{1B}[2K\nPro\u{7F}\u{9B}") == "Editor?[2K?Pro??")
        #expect(Output.plain("Café 📷") == "Café 📷")
        #expect(Output.quoted("Notes Pro") == "'Notes Pro'")
        #expect(Output.quoted("Editor") == "Editor")
        #expect(Output.quoted("Sam's Apps") == "'Sam'\\''s Apps'")
    }

    // MARK: peel uninstall

    private func uninstallation(
        app: InstalledApp,
        leftovers: [Leftover],
        appSize: Int64 = 12_000,
        isAppMeasured: Bool = true
    ) -> Uninstallation {
        Uninstallation(
            app: app,
            appSize: appSize,
            appRequiresPrivileges: false,
            scan: LeftoverScan(leftovers: leftovers, unreadableLocations: []),
            isAppMeasured: isAppMeasured
        )
    }

    private func leftover(
        _ url: URL,
        confidence: MatchConfidence = .certain,
        sharedWith: [String] = [],
        heldBack: HoldBack? = nil,
        size: Int64 = 400,
        requiresPrivileges: Bool = false
    ) -> Leftover {
        var match = LeftoverMatch(reason: .bundleIdentifier, confidence: confidence, sharedWith: sharedWith)
        if let heldBack { match = match.forReview(heldBack) }
        return Leftover(url: url, kind: .caches, match: match, size: size, isMeasured: true, requiresPrivileges: requiresPrivileges)
    }

    /// The notes shown before the user agrees to a removal. Each one names something that will still be on
    /// the disk afterwards, so leaving one out would promise more than the removal does.
    @Test func saysWhatWillStayBeforeItAsks() {
        let app = InstalledApp(url: URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.editor", name: "Editor")
        let cache = URL(filePath: "/Users/me/Library/Caches/com.example.editor")
        let caches = SearchLocation(kind: .caches, url: URL(filePath: "/Users/me/Library/Caches", directoryHint: .isDirectory))
        let plan = UninstallPlan.make(
            uninstallation(app: app, leftovers: [
                leftover(cache, requiresPrivileges: true),
                leftover(URL(filePath: "/Users/me/Library/Caches/review"), heldBack: .namedLikeTheApp),
            ]),
            keepLeftovers: false,
            refusal: { _ in nil }
        )
        let scan = LeftoverScan(leftovers: [], unreadableLocations: [caches], cutShortLocations: [caches])

        let notes = UninstallCommand.whatStays(plan, app: app, homebrew: CaskLookup.Answer(failure: "brew is not installed"), scan: scan)

        #expect(notes.count == 5)
        #expect(notes[0].hasPrefix("Homebrew didn't answer, so what only its casks know is missing."))
        #expect(notes[1] == Output.fullDiskAccessNote)
        #expect(notes[2].hasPrefix("There are more folders in /Users/me/Library/Caches than Peel looks inside"))
        #expect(notes[3] == "1 item needs administrator access and will stay. Remove it with the Peel app.")
        #expect(notes[4] == "1 file needs review and will stay. See it with `peel leftovers Editor --all`.")
    }

    @Test func saysNothingWhenNothingWillStay() {
        let app = InstalledApp(url: URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.editor", name: "Editor")
        let plan = UninstallPlan.make(
            uninstallation(app: app, leftovers: [leftover(URL(filePath: "/Users/me/Library/Caches/com.example.editor"))]),
            keepLeftovers: false,
            refusal: { _ in nil }
        )

        let notes = UninstallCommand.whatStays(plan, app: app, homebrew: CaskLookup.Answer(), scan: LeftoverScan(leftovers: [], unreadableLocations: []))

        #expect(notes.isEmpty)
    }

    /// When the app itself stays, the message says its files stayed too. Every refusal is named.
    @Test func saysWhyARemovalDidNotFinish() {
        let app = InstalledApp(url: URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.editor", name: "Editor")
        let cache = URL(filePath: "/Users/me/Library/Caches/com.example.editor")
        let plan = UninstallPlan.make(
            uninstallation(app: app, leftovers: [leftover(cache)]),
            keepLeftovers: false,
            refusal: { _ in nil }
        )
        let refused = TrashResult(failures: [TrashFailure(url: app.url, reason: .notPermitted)])
        let partly = TrashResult(
            trashed: [TrashedItem(originalURL: app.url, trashedURL: URL(filePath: "/Users/me/.Trash/Editor.app"), date: .now)],
            failures: [TrashFailure(url: cache, reason: .changedSinceScan)]
        )

        let nothingMoved = UninstallCommand.whatFailed(refused, plan: plan, app: app)
        let appWentAndOneFileStayed = UninstallCommand.whatFailed(partly, plan: plan, app: app)

        #expect(nothingMoved[0] == "Couldn't move /Applications/Editor.app: not permitted")
        #expect(nothingMoved.contains("Editor stayed, so its files were left where they are."))
        // The app did move, so the only thing to say is which file did not.
        #expect(appWentAndOneFileStayed == ["Couldn't move /Users/me/Library/Caches/com.example.editor: changed since the scan"])
    }

    /// The app bundle moves first. macOS refuses to move another developer's app without App Management, and if
    /// that refusal came last, the app would stay installed with its settings already in the Trash.
    @Test func movesTheBundleBeforeAnythingOfItsOwn() {
        let app = InstalledApp(url: URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.editor", name: "Editor")
        let cache = URL(filePath: "/Users/me/Library/Caches/com.example.editor")
        let support = URL(filePath: "/Users/me/Library/Application Support/Editor")
        let plan = UninstallPlan.make(
            uninstallation(app: app, leftovers: [leftover(cache), leftover(support, size: 600)]),
            keepLeftovers: false,
            refusal: { _ in nil }
        )

        #expect(plan.items.map(\.url) == [app.url, cache, support])
        #expect(plan.total == SizeTotal(known: 13_000, isComplete: true))
        #expect(plan.staying.isEmpty)

        let alone = UninstallPlan.make(uninstallation(app: app, leftovers: [leftover(cache)]), keepLeftovers: true, refusal: { _ in nil })
        #expect(alone.items.map(\.url) == [app.url])
        #expect(alone.needsReview == 0)
    }

    /// The list is drawn from the guard's own answer, so `--dry-run` can't promise what the real run refuses.
    @Test func saysWhatWouldStayInsteadOfListingItAsMoving() {
        let app = InstalledApp(url: URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.editor", name: "Editor")
        let cache = URL(filePath: "/Users/me/Library/Caches/com.example.editor")
        let plan = UninstallPlan.make(
            uninstallation(app: app, leftovers: [leftover(cache)]),
            keepLeftovers: false,
            refusal: { $0 == cache ? .protectedLocation : nil }
        )

        #expect(plan.moving.map(\.url) == [app.url])
        #expect(plan.staying.map(\.url) == [cache])
        #expect(plan.total == SizeTotal(known: 12_000, isComplete: true))
        #expect(plan.appStays == nil)

        let refused = UninstallPlan.make(
            uninstallation(app: app, leftovers: [leftover(cache)]),
            keepLeftovers: false,
            refusal: { $0 == app.url ? .protectedLocation : nil }
        )
        #expect(refused.appStays == .protectedLocation)
    }

    /// What stays is counted where the user can see it, and a size nobody knows is never added up as zero.
    @Test func countsWhatItKeepsForReviewAndWhatItCouldNotMeasure() {
        let app = InstalledApp(url: URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.editor", name: "Editor")
        let cache = URL(filePath: "/Users/me/Library/Caches/com.example.editor")
        let shared = URL(filePath: "/Users/me/Library/Application Support/Acme")
        let unmeasured = URL(filePath: "/Users/me/Library/Containers/com.example.editor")
        let admin = URL(filePath: "/Library/Application Support/Editor")
        let plan = UninstallPlan.make(
            uninstallation(
                app: app,
                leftovers: [
                    leftover(cache),
                    leftover(shared, sharedWith: ["com.acme.other"]),
                    leftover(unmeasured, heldBack: .notMeasured, size: 0),
                    leftover(admin, requiresPrivileges: true),
                ],
                isAppMeasured: false
            ),
            keepLeftovers: false,
            refusal: { _ in nil }
        )

        #expect(plan.items.map(\.url) == [app.url, cache])
        #expect(plan.items[0].size == nil)
        #expect(!plan.total.isComplete)
        #expect(plan.needsAdministrator == 1)
        #expect(plan.needsReview == 2)
    }

    /// When the bundle is refused, nothing else of the app moves: the files of an app that is still installed
    /// are not leftovers.
    @Test func leavesTheLeftoversWhereTheyAreWhenTheAppItselfCannotMove() async throws {
        let directory = try TemporaryDirectory()
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        let bundle = try directory.directory("Applications/Editor.app")
        let cache = try directory.file("home/Library/Caches/com.example.editor/data.bin")
        let trash = try directory.directory("FakeTrash")
        let app = InstalledApp(url: bundle, bundleIdentifier: "com.example.editor", name: "Editor")

        let service = TrashService(environment: environment) { url in
            // What macOS answers without App Management for another developer's app.
            guard url.pathExtension != "app" else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
            }
            let destination = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
        let plan = UninstallPlan.make(
            uninstallation(app: app, leftovers: [leftover(cache.deletingLastPathComponent())]),
            keepLeftovers: false,
            refusal: service.refusal(of:)
        )
        let result = await plan.move(using: service)

        #expect(result.trashed.isEmpty)
        #expect(result.failures.map(\.url) == [bundle])
        #expect(result.failures.map(\.reason) == [.notPermitted])
        #expect(FileManager.default.fileExists(atPath: cache.path(percentEncoded: false)), "a leftover moved although the app stayed")
        #expect(AppManagement.state(after: result, appBundles: [bundle]) == .missing)
    }

    /// Peel's own removal unregisters the helper and the login item first, which only the app does.
    @Test func refusesToUninstallPeelItself() throws {
        let peel = InstalledApp(url: URL(filePath: "/Applications/Peel.app", directoryHint: .isDirectory), bundleIdentifier: "com.tuguidragos.Peel", name: "Peel")
        let other = InstalledApp(url: URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.editor", name: "Editor")

        #expect(peel.isPeelItself)
        #expect(!other.isPeelItself)
        #expect(throws: CommandFailure.self) { try UninstallCommand.refuseIfItIsPeel(peel) }
        try UninstallCommand.refuseIfItIsPeel(other)
    }

    /// A privacy reset that was asked for but can never happen is refused before anything is listed. If it were
    /// skipped quietly, the app would go while its privacy permissions stayed on record.
    @Test func refusesAPrivacyResetItCannotDoBeforeAnythingMoves() throws {
        let signal = InstalledApp(url: URL(filePath: "/Applications/Signal.app", directoryHint: .isDirectory), bundleIdentifier: "Signal", name: "Signal")
        let editor = InstalledApp(url: URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.editor", name: "Editor")

        #expect(throws: CommandFailure.self) { try UninstallCommand.refuseIfPrivacyCannotBeReset(signal) }
        try UninstallCommand.refuseIfPrivacyCannotBeReset(editor)
        let command = try #require(try PeelCommand.parseAsRoot(["uninstall", "Editor", "--reset-privacy", "--yes"]) as? UninstallCommand)
        #expect(command.resetPrivacy)
    }

    /// The line printed about the privacy reset after the move, and whether it makes the command fail.
    @Test func saysWhatCameOfThePrivacyReset() {
        let editor = InstalledApp(url: URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.editor", name: "Editor")

        #expect(UninstallCommand.privacyOutcome(.reset, app: editor) == ("Reset Editor's privacy permissions.", false))
        #expect(UninstallCommand.privacyOutcome(.notKnownToTheSystem, app: editor) == ("Editor's privacy permissions weren't reset: macOS couldn't find the app.", true))
        #expect(UninstallCommand.privacyOutcome(.failed(""), app: editor) == ("Editor's privacy permissions weren't reset: macOS didn't say why.", true))
        #expect(UninstallCommand.privacyOutcome(.failed("Failed to reset All"), app: editor) == ("Editor's privacy permissions weren't reset: macOS reported: Failed to reset All.", true))
        #expect(UninstallCommand.privacyOutcome(.couldNotAsk("tccutil didn't answer in time"), app: editor) == ("Editor's privacy permissions weren't reset: tccutil didn't answer in time.", true))
    }

    /// Nothing moves without an answer. Where `peel` cannot ask, it needs `--yes` or `--dry-run`, which leave
    /// nothing to ask.
    @Test func asksBeforeMovingAnythingUnlessItIsToldNotTo() throws {
        // ArgumentParser runs `validate()` while it parses, which is where the rule has to live: only there
        // does it know which subcommand to print the usage of.
        if Output.canAsk {
            #expect(throws: Never.self) { try PeelCommand.parseAsRoot(["uninstall", "Editor"]) }
        } else {
            #expect(throws: (any Error).self) { try PeelCommand.parseAsRoot(["uninstall", "Editor"]) }
        }
        _ = try #require(try PeelCommand.parseAsRoot(["uninstall", "Editor", "--yes"]) as? UninstallCommand)
        _ = try #require(try PeelCommand.parseAsRoot(["uninstall", "Editor", "--dry-run"]) as? UninstallCommand)
        // Answering no is not success: with `CleanExit`, `peel uninstall Foo && next-step` would run `next-step`.
        #expect(Output.declined != ExitCode.success)
    }

    // MARK: peel updates

    /// When every check fails, as with no network, the report must not read as "every app is up to date": a
    /// script checking the result would take it as the all clear.
    @Test func doesNotCallAFailedCheckAnAllClear() {
        let editor = InstalledApp(url: URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.editor", name: "Editor", version: "1.0")
        let notes = InstalledApp(url: URL(filePath: "/Applications/Notes.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.notes", name: "Notes", version: "2.0")
        let widget = InstalledApp(url: URL(filePath: "/Applications/Widget.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.widget", name: "Widget")
        let apps = [editor, notes, widget]

        let nothing = UpdatesCommand.report(
            apps: apps,
            statuses: [editor.id: .failed, notes.id: .failed, widget.id: .unsupported],
            preferences: UpdatePreferences(),
            all: false
        )
        #expect(nothing.rows.isEmpty)
        #expect(nothing.failed == 2)
        #expect(nothing.withAFeed == 2)
        #expect(nothing.nothingAnswered)

        let some = UpdatesCommand.report(
            apps: apps,
            statuses: [editor.id: .failed, notes.id: .upToDate, widget.id: .unsupported],
            preferences: UpdatePreferences(),
            all: false
        )
        #expect(some.rows.isEmpty)
        #expect(some.failed == 1)
        #expect(!some.nothingAnswered)
    }

    /// The same rule the app follows: an app the user told Peel to leave alone is not checked, and a skipped
    /// version is not an update waiting.
    @Test func readsTheSameUpdateSettingsTheAppDoes() {
        let editor = InstalledApp(url: URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.editor", name: "Editor", version: "1.0")
        let notes = InstalledApp(url: URL(filePath: "/Applications/Notes.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.notes", name: "Notes", version: "2.0")
        let waiting = UpdateStatus.updateAvailable(version: "3.0", source: .developer, releaseNotes: nil)
        let preferences = UpdatePreferences(
            source: .homebrew,
            ignoredIdentifiers: ["com.example.notes"],
            skippedVersions: ["com.example.editor": "3.0"]
        )

        let report = UpdatesCommand.report(
            apps: [editor, notes],
            statuses: [editor.id: waiting, notes.id: waiting],
            preferences: preferences,
            all: false
        )
        #expect(report.rows.isEmpty, "a skipped version or an ignored app was listed as an update waiting")
        #expect(report.ignored == 1)
        #expect(report.withAFeed == 1)

        #expect(!preferences.isWaiting(waiting, for: editor))
        #expect(!preferences.isWaiting(waiting, for: notes))
        #expect(preferences.isWaiting(.updateAvailable(version: "4.0", source: .developer, releaseNotes: nil), for: editor))
        #expect(UpdatesCommand.report(apps: [editor, notes], statuses: [:], preferences: preferences, all: true).rows.count == 1)
    }

    @Test func readsTheUpdateSettingsFromTheAppsOwnKeys() throws {
        // The values are registered, which keeps them in memory only. A value set in a suite leaves a file in the
        // real `~/Library/Preferences`, even if it is removed afterwards.
        let defaults = try #require(UserDefaults(suiteName: "com.tuguidragos.Peel.CommandLineTests"))
        defaults.register(defaults: [
            UpdatePreferences.Key.source: "homebrew",
            UpdatePreferences.Key.ignoredApps: ["com.example.notes"],
            UpdatePreferences.Key.skippedVersions: ["com.example.editor": "3.0"],
        ])

        let preferences = UpdatePreferences.read(from: defaults)
        #expect(preferences.source == .homebrew)
        #expect(preferences.ignoredIdentifiers == ["com.example.notes"])
        #expect(preferences.skippedVersions == ["com.example.editor": "3.0"])
    }

    /// A row that is not selected says why: the reason it was held back, who else claims the file, or that the
    /// match is only possible.
    @Test func saysWhyARowIsOnlyShown() {
        let folder = URL(filePath: "/Users/me/Library/Application Support/Editor")
        func row(_ confidence: MatchConfidence, sharedWith: [String] = [], heldBack: HoldBack? = nil) -> String {
            var match = LeftoverMatch(reason: .bundleIdentifier, confidence: confidence, sharedWith: sharedWith)
            if let heldBack { match = match.forReview(heldBack) }
            return LeftoversCommand.summary(of: Leftover(url: folder, kind: .applicationSupport, match: match, size: 1, isMeasured: true, requiresPrivileges: false))
        }

        #expect(row(.certain) == "bundle identifier")
        #expect(row(.certain, heldBack: .holdsRepository) == "bundle identifier, review: holds a repository")
        #expect(row(.certain, sharedWith: ["com.acme.other"]) == "bundle identifier, review: shared with com.acme.other")
        #expect(row(.possible) == "bundle identifier, review: possible match")
    }

    @Test func showsTheUsageOfTheSubcommandThatFailed() throws {
        let error = #expect(throws: (any Error).self) { try PeelCommand.parseAsRoot(["inventory", "--format", "bogus"]) }
        let message = PeelCommand.fullMessage(for: try #require(error), columns: 200)

        // The format is an enum, so ArgumentParser writes this message itself and lists the four values it takes.
        #expect(message.contains("'bogus' is invalid for '--format <format>'"))
        #expect(message.contains("text, json, csv, brewfile"))
        #expect(message.contains("Usage: peel inventory"))
        #expect(message.contains("See 'peel inventory --help'"))
    }

    @Test func parsesCommandsAndRejectsUnboundedSearches() throws {
        let duplicates = try PeelCommand.parseAsRoot(["duplicates", "~/Pictures", "--kind", "disk-images", "--min-size", "1.5GB", "--json"])
        let parsed = try #require(duplicates as? DuplicatesCommand)
        #expect(parsed.folders == ["~/Pictures"])
        #expect(parsed.kind == .diskImages)
        #expect(parsed.minimumSize == ByteSize(bytes: 1_500_000_000))
        #expect(parsed.output.json)

        let search = try #require(try PeelCommand.parseAsRoot(["search", "--name", "invoice", "--older-than", "30", "--everywhere"]) as? SearchCommand)
        #expect(search.criteria.name == "invoice")
        #expect(search.criteria.unmodifiedDays == 30)
        #expect(search.criteria.scope == .computer)

        #expect(throws: (any Error).self) { try PeelCommand.parseAsRoot(["search", "--older-than", "30"]) }
        #expect(throws: (any Error).self) { try PeelCommand.parseAsRoot(["uninstall"]) }
        let uninstall = try #require(try PeelCommand.parseAsRoot(["uninstall", "Editor", "--json", "--dry-run"]) as? UninstallCommand)
        #expect(uninstall.output.json)
    }

    private func record(_ batch: UUID, _ path: String, at date: Date) -> RemovalRecord {
        RemovalRecord(
            batch: batch,
            item: TrashedItem(originalURL: URL(filePath: path), trashedURL: URL(filePath: "/Users/me/.Trash/x"), date: date),
            size: 10,
            source: "Example",
            tool: "applications"
        )
    }

    /// Everything removed in one go is one entry, newest first, and its size is what the whole batch took.
    @Test func groupsHistoryIntoRemovalsNewestFirst() {
        let old = UUID(), recent = UUID()
        let records = [
            record(old, "/Applications/Old.app", at: Date(timeIntervalSince1970: 1_000)),
            record(recent, "/Applications/New.app", at: Date(timeIntervalSince1970: 9_000)),
            record(old, "/Users/me/Library/Caches/old", at: Date(timeIntervalSince1970: 1_100)),
        ]

        let batches = Batch.all(in: records)

        #expect(batches.map(\.id) == [recent, old])
        #expect(batches[1].records.count == 2)
        #expect(batches[1].size == SizeTotal(known: 20, isComplete: true))
        #expect(batches[0].shortID == String(recent.uuidString.prefix(8)).lowercased())
    }

    /// The first characters are enough, and an ID that fits two removals is refused rather than guessed at.
    @Test func findsARemovalByTheStartOfItsIdentifier() throws {
        let first = try #require(UUID(uuidString: "A955E2E4-0000-4000-8000-000000000001"))
        let second = try #require(UUID(uuidString: "A955E2E4-0000-4000-8000-000000000002"))
        let other = try #require(UUID(uuidString: "0B0B0B0B-0000-4000-8000-000000000003"))
        let batches = Batch.all(in: [
            record(first, "/Applications/One.app", at: .distantPast),
            record(second, "/Applications/Two.app", at: .distantPast),
            record(other, "/Applications/Three.app", at: .distantPast),
        ])

        #expect(try RestoreCommand.batch(matching: "0b0b", in: batches).id == other)
        #expect(try RestoreCommand.batch(matching: "0B0B0B0B", in: batches).id == other)
        #expect(throws: (any Error).self) { try RestoreCommand.batch(matching: "a955", in: batches) }
        #expect(throws: (any Error).self) { try RestoreCommand.batch(matching: "nothing", in: batches) }
    }

    /// A flag that only makes sense with `--remove` is refused without it, rather than quietly ignored.
    /// `--json` only lists, so it is refused with `--remove`.
    @Test func removalFlagsOnlyGoWithARemoval() throws {
        #expect(try (PeelCommand.parseAsRoot(["caches", "--remove", "--dry-run"]) as? CachesCommand)?.removal.remove == true)
        for arguments in [["caches", "--dry-run"], ["caches", "-y"], ["projects", "~/x", "--dry-run"], ["duplicates", "--yes"]] {
            #expect(throws: (any Error).self) { try PeelCommand.parseAsRoot(arguments) }
        }
        #expect(throws: (any Error).self) { try PeelCommand.parseAsRoot(["caches", "--remove", "--json"]) }
    }

    /// Nothing in Orphaned Files is ever suggested, so `peel orphans --remove` has to name one group.
    @Test func removingOrphansNamesOneGroup() throws {
        let named = try #require(try PeelCommand.parseAsRoot(["orphans", "--remove", "com.example.app", "-y"]) as? OrphansCommand)

        #expect(named.group == "com.example.app")
        #expect(throws: (any Error).self) { try PeelCommand.parseAsRoot(["orphans", "--remove", "-y"]) }
        #expect(throws: (any Error).self) { try PeelCommand.parseAsRoot(["orphans", "com.example.app"]) }
    }

    /// `--clear` only forgets the refusals. What moved is forgotten from History in the Peel app.
    @Test func forgettingOnlyGoesWithTheRefusals() throws {
        let refused = try #require(try PeelCommand.parseAsRoot(["history", "--refused", "--clear"]) as? HistoryCommand)

        #expect(refused.refused && refused.clear)
        #expect(throws: (any Error).self) { try PeelCommand.parseAsRoot(["history", "--clear"]) }
        #expect(throws: (any Error).self) { try PeelCommand.parseAsRoot(["history", "--refused", "--limit", "0"]) }
    }
}
