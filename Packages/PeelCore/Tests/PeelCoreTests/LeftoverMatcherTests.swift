import Foundation
@testable import PeelCore
import Testing

struct LeftoverMatcherTests {
    private func app(
        _ bundleIdentifier: String,
        name: String,
        team: String? = nil,
        groups: [String] = [],
        embedded: [String] = []
    ) -> InstalledApp {
        InstalledApp(
            url: URL(filePath: "/Applications/\(name).app"),
            bundleIdentifier: bundleIdentifier,
            name: name,
            teamIdentifier: team,
            applicationGroups: groups,
            embeddedBundleIdentifiers: embedded
        )
    }

    /// Uses `registered` in place of Launch Services, so the answers never depend on the machine running the tests.
    private func match(
        _ fileName: String,
        in kind: SearchLocation.Kind,
        for target: InstalledApp,
        with others: [InstalledApp] = [],
        registered: [String: URL] = [:]
    ) -> LeftoverMatch? {
        LeftoverMatcher(app: target, installedApps: [target] + others) { registered[$0.lowercased()] }
            .match(fileName: fileName, kind: kind)
    }

    /// The list of installed apps covers only `/Applications` and `~/Applications`. Chrome Canary kept on another
    /// disk is still installed, so Launch Services is asked about a longer identifier before it is taken for one
    /// of Chrome's own.
    @Test func aSiblingInstalledSomewhereElseStillSharesItsFiles() throws {
        let chrome = app("com.google.Chrome", name: "Google Chrome")
        let elsewhere = ["com.google.chrome.canary": URL(filePath: "/Volumes/Work/Apps/Google Chrome Canary.app")]

        let canarys = try #require(match("com.google.Chrome.canary.plist", in: .preferences, for: chrome, registered: elsewhere))
        #expect(canarys.sharedWith == ["com.google.Chrome.canary"])
        #expect(!canarys.isRecommended)
        let helpers = try #require(match("com.google.Chrome.canary.helper", in: .caches, for: chrome, registered: elsewhere))
        #expect(!helpers.isRecommended, "the helper of the app that is elsewhere")

        // Chrome's helpers are registered apps too, but they sit inside Chrome, so they are not rivals.
        let inside = ["com.google.chrome.helper": chrome.url.appending(path: "Contents/Frameworks/Google Chrome Helper.app")]
        #expect(try #require(match("com.google.Chrome.helper", in: .caches, for: chrome, registered: inside)).isRecommended)
        #expect(try #require(match("com.google.Chrome.helper", in: .caches, for: chrome)).isRecommended)
    }

    /// Another copy of the app uses the same files wherever it is, so a file both claim is shared with that copy,
    /// known by its place, since the identifier cannot tell the two apart. What only this copy embeds stays its own.
    @Test func anotherCopyOfTheAppSharesWhatItUsesAndNothingMore() throws {
        let sample = app("org.example.Sample", name: "Sample", embedded: ["org.example.Sample.Updater"])
        let older = InstalledApp(url: URL(filePath: "/Volumes/Disk/Sample.app"), bundleIdentifier: sample.bundleIdentifier, name: "Sample")

        let preferences = try #require(match("org.example.Sample.plist", in: .preferences, for: sample, with: [older]))
        #expect(preferences.sharedWith.isEmpty)
        #expect(preferences.otherCopies == [older.url])
        #expect(!preferences.isRecommended)
        let updater = try #require(match("org.example.Sample.Updater", in: .caches, for: sample, with: [older]))
        #expect(updater.otherCopies.isEmpty)
        #expect(updater.isRecommended)
    }

    /// An app that sits inside the item goes with it, so it keeps none of it: an agent or an update the app keeps in
    /// its own support folder does not make that folder shared. The same apps kept anywhere else do.
    @Test func anAppInsideTheItemKeepsNoneOfIt() throws {
        let sketchpad = app("org.example.Sketchpad", name: "Sketchpad")
        let folder = URL(filePath: "/Users/x/Library/Application Support/Sketchpad")
        func claim(besides rivals: [InstalledApp]) throws -> LeftoverMatch {
            try #require(LeftoverMatcher(app: sketchpad, installedApps: [sketchpad] + rivals).match(fileName: "Sketchpad", kind: .applicationSupport, at: folder))
        }
        func agent(at url: URL) -> InstalledApp {
            InstalledApp(url: url, bundleIdentifier: "org.example.agent", name: "SketchpadAgent")
        }
        func update(at url: URL) -> InstalledApp {
            InstalledApp(url: url, bundleIdentifier: sketchpad.bundleIdentifier, name: "Sketchpad")
        }

        #expect(try claim(besides: [agent(at: folder.appending(path: "SketchpadAgent.app")), update(at: folder.appending(path: "Updates/Sketchpad.app"))]).isRecommended)
        #expect(try claim(besides: [agent(at: URL(filePath: "/Volumes/Disk/SketchpadAgent.app"))]).sharedWith == ["org.example.agent"])
        #expect(try claim(besides: [update(at: URL(filePath: "/Users/x/Downloads/Sketchpad.app"))]).otherCopies.count == 1)
    }

    @Test(arguments: [
        ("com.spotify.client.plist", SearchLocation.Kind.preferences),
        ("COM.SPOTIFY.CLIENT", .caches),
        ("com.spotify.client.savedState", .savedApplicationState),
        ("com.spotify.client.binarycookies", .cookies),
        ("com.spotify.client.0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9.plist", .preferencesByHost),
    ])
    func exactBundleIdentifierIsCertain(fileName: String, kind: SearchLocation.Kind) throws {
        let result = try #require(match(fileName, in: kind, for: app("com.spotify.client", name: "Spotify")))
        #expect(result.reason == .bundleIdentifier)
        #expect(result.confidence == .certain)
        #expect(result.isRecommended)
    }

    @Test func embeddedIdentifierConfidenceDependsOnVendor() throws {
        let docker = app("com.docker.docker", name: "Docker", embedded: ["com.docker.helper", "com.github.Electron.helper"])

        let helper = try #require(match("com.docker.helper", in: .caches, for: docker))
        #expect(helper.reason == .embeddedBundleIdentifier)
        #expect(helper.confidence == .certain)

        let electron = try #require(match("com.github.Electron.helper", in: .caches, for: docker))
        #expect(electron.confidence == .likely)
    }

    @Test func applicationGroupSharedWithAnotherAppIsNotRecommended() throws {
        let word = app("com.microsoft.Word", name: "Microsoft Word", groups: ["UBF8T346G9.Office"])
        let excel = app("com.microsoft.Excel", name: "Microsoft Excel", groups: ["UBF8T346G9.Office"])

        let result = try #require(match("UBF8T346G9.Office", in: .groupContainers, for: word, with: [excel]))
        #expect(result.reason == .applicationGroup)
        #expect(result.sharedWith == ["com.microsoft.Excel"])
        #expect(!result.isRecommended)
    }

    @Test func longestBundleIdentifierPrefixWins() throws {
        let chrome = app("com.google.Chrome", name: "Google Chrome")
        let canary = app("com.google.Chrome.canary", name: "Google Chrome Canary")

        #expect(match("com.google.Chrome.canary", in: .caches, for: chrome, with: [canary]) == nil)
        #expect(match("com.google.Chrome.canary.helper", in: .caches, for: chrome, with: [canary]) == nil)

        let own = try #require(match("com.google.Chrome.helper", in: .caches, for: chrome, with: [canary]))
        #expect(own.reason == .bundleIdentifierPrefix)
        #expect(own.confidence == .likely)
        #expect(!own.isShared)
    }

    @Test func nameMatchIgnoresCaseAndSeparators() throws {
        let code = app("com.microsoft.VSCode", name: "Visual Studio Code")

        let result = try #require(match("visual-studio code", in: .applicationSupport, for: code))
        #expect(result.reason == .name)
        #expect(result.isRecommended)
    }

    @Test(arguments: ["Helper", "Go", "Microsoft"])
    func genericOrShortNamesNeverMatchByName(name: String) {
        #expect(match(name, in: .applicationSupport, for: app("com.example.app", name: name)) == nil)
    }

    @Test func exactNameOfAnotherAppBeatsNamePrefix() throws {
        let notion = app("notion.id", name: "Notion")
        let calendar = app("com.cron.electron", name: "Notion Calendar")

        #expect(match("Notion Calendar", in: .applicationSupport, for: notion, with: [calendar]) == nil)

        let prefix = try #require(match("Notion Calendar", in: .applicationSupport, for: notion))
        #expect(prefix.reason == .namePrefix)
        #expect(!prefix.isRecommended)
    }

    @Test func teamAndVendorMatchesAreOnlyPossible() throws {
        let word = app("com.microsoft.Word", name: "Microsoft Word", team: "UBF8T346G9")
        let excel = app("com.microsoft.Excel", name: "Microsoft Excel", team: "UBF8T346G9")

        let team = try #require(match("UBF8T346G9.ms", in: .groupContainers, for: word))
        #expect(team.reason == .teamIdentifier)
        #expect(team.confidence == .possible)

        let vendor = try #require(match("com.microsoft.autoupdate2.plist", in: .preferences, for: word, with: [excel]))
        #expect(vendor.reason == .vendorPrefix)
        #expect(vendor.sharedWith == ["com.microsoft.Excel"])
        #expect(!vendor.isRecommended)
    }

    @Test func hostingDomainsAreNotTreatedAsVendors() {
        let first = app("com.github.alice.Tool", name: "Tool One")
        #expect(match("com.github.bob.Other", in: .caches, for: first) == nil)
    }

    /// The answer must not depend on where the app sits in the list of installed apps, or on the order of its
    /// rivals: callers promise no particular order.
    @Test func saysTheSameWhateverTheOrderOfTheInstalledApps() throws {
        let word = app("com.microsoft.Word", name: "Microsoft Word", team: "UBF8T346G9", groups: ["UBF8T346G9.Office"])
        let excel = app("com.microsoft.Excel", name: "Microsoft Excel", team: "UBF8T346G9", groups: ["UBF8T346G9.Office"])
        let outlook = app("com.microsoft.Outlook", name: "Microsoft Outlook", team: "UBF8T346G9", groups: ["UBF8T346G9.Office"])
        let orders = [[word, excel, outlook], [outlook, excel, word], [excel, word, outlook]]

        for (fileName, kind) in [("UBF8T346G9.Office", SearchLocation.Kind.groupContainers), ("com.microsoft.Word.plist", .preferences), ("com.microsoft.autoupdate2.plist", .preferences)] {
            let answers = orders.map { LeftoverMatcher(app: word, installedApps: $0) { _ in nil }.match(fileName: fileName, kind: kind) }
            #expect(Set(answers).count == 1, "\(fileName) is judged differently depending on the order")
        }
    }

    /// The app being matched is also in the list of installed apps. Spelled in another case or reached through
    /// a link, it must still be recognized as itself, or every file would count as shared with itself and
    /// nothing would be selected.
    @Test func knowsItselfUnderAnotherSpelling() throws {
        let directory = try TemporaryDirectory()
        let bundle = try directory.directory("Applications/Example.app")
        let link = directory.url.appending(path: "Example Link.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: bundle)
        let installed = InstalledApp(url: bundle, bundleIdentifier: "com.example.app", name: "Example")

        for spelling in [link, directory.url.appending(path: "applications/example.app")] {
            let asked = InstalledApp(url: spelling, bundleIdentifier: "com.example.app", name: "Example")
            let match = try #require(LeftoverMatcher(app: asked, installedApps: [installed]) { _ in nil }
                .match(fileName: "com.example.app.plist", kind: .preferences))
            #expect(match.sharedWith.isEmpty, "\(spelling.lastPathComponent) was taken for another app")
        }
    }

    /// `uk.co`, `jp.co`, and `au.com` are where countries register companies, not companies themselves. Two
    /// apps under one of them are no more likely to share a developer than two apps under `com`.
    @Test func publicSuffixesAreNotTreatedAsVendors() {
        #expect(Identifier.vendor(of: "uk.co.alpha.app") == "uk.co.alpha")
        #expect(Identifier.vendor(of: "uk.co.alpha.app") != Identifier.vendor(of: "uk.co.beta.app"))
        #expect(Identifier.vendor(of: "jp.co.canon") == nil)
        #expect(Identifier.vendor(of: "com.example.app") == "com.example")

        let canon = app("jp.co.canon.utility", name: "Utility")
        #expect(match("jp.co.other.Thing", in: .caches, for: canon) == nil)
    }

    @Test func appleItemsOnlyMatchExactIdentifiers() throws {
        let xcode = app("com.apple.dt.Xcode", name: "Xcode", team: "59GAB85EFG")

        let preferences = try #require(match("com.apple.dt.Xcode.plist", in: .preferences, for: xcode))
        #expect(preferences.confidence == .certain)
        #expect(match("com.apple.dt.Xcode.sourcecontrol", in: .caches, for: xcode) == nil)
        #expect(match("com.apple.Safari", in: .caches, for: xcode) == nil)
    }

    /// Anyone can put a bundle in `~/Applications` with any identifier in its Info.plist. Claiming to be one of
    /// Apple's apps must not give it that app's mail, messages, or settings.
    @Test func anAppThatClaimsToBeApplesGetsNothingOfApples() {
        let pretender = app("com.apple.Music", name: "Music")
        let pretendingByGroup = app("com.example.player", name: "Player", groups: ["group.com.apple.Music"])
        let pretendingByEmbedding = app("com.example.player", name: "Player", embedded: ["com.apple.Music"])

        #expect(match("com.apple.Music.plist", in: .preferences, for: pretender) == nil)
        #expect(match("com.apple.Music", in: .containers, for: pretender) == nil)
        #expect(match("group.com.apple.Music", in: .groupContainers, for: pretendingByGroup) == nil)
        #expect(match("com.apple.Music", in: .caches, for: pretendingByEmbedding) == nil)
    }


    @Test func unrelatedItemsDoNotMatch() {
        let spotify = app("com.spotify.client", name: "Spotify")
        #expect(match("com.example.other", in: .caches, for: spotify) == nil)
        #expect(match("Notes", in: .applicationSupport, for: spotify) == nil)
    }

    @Test func sharesMozillaFilesWithTheOtherChannels() {
        let firefox = app("org.mozilla.firefox", name: "Firefox", team: "43AQ936H96")
        let nightly = app("org.mozilla.nightly", name: "Firefox Nightly", team: "43AQ936H96")
        let developerEdition = app("org.mozilla.firefoxdeveloperedition", name: "Firefox Developer Edition", team: "43AQ936H96")
        let thunderbird = app("org.mozilla.thunderbird", name: "Thunderbird", team: "43AQ936H96")

        let shared = match("Firefox", in: .applicationSupport, for: firefox, with: [nightly, developerEdition, thunderbird])
        #expect(shared?.isShared == true)
        #expect(shared?.sharedWith == ["org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"])

        let mail = match("Thunderbird", in: .applicationSupport, for: thunderbird, with: [firefox, nightly])
        #expect(mail?.isShared == false)
    }

    @Test func sharesOfficeGroupContainersBetweenApps() {
        let word = app("com.microsoft.Word", name: "Microsoft Word", team: "UBF8T346G9", groups: ["UBF8T346G9.Office"])
        let excel = app("com.microsoft.Excel", name: "Microsoft Excel", team: "UBF8T346G9", groups: ["UBF8T346G9.Office"])

        let group = match("UBF8T346G9.Office", in: .groupContainers, for: word, with: [excel])
        #expect(group?.sharedWith == ["com.microsoft.Excel"])
        #expect(group?.isShared == true)
    }

    @Test func leavesApplesOwnFilesAlone() {
        let chrome = app("com.google.Chrome", name: "Google Chrome", team: "EQHXZ8M8AV")

        #expect(match("com.apple.passwordmanager.json", in: .applicationSupport, for: chrome) == nil)
        #expect(match("com.apple.passwordmanager", in: .applicationSupport, for: chrome) == nil)
    }

    @Test func findsRecentDocumentLists() {
        let code = app("com.microsoft.VSCode", name: "Visual Studio Code")

        let match = match("com.microsoft.VSCode.sfl3", in: .recentDocuments, for: code)
        #expect(match?.reason == .bundleIdentifier)
        #expect(match?.confidence == .certain)
    }
    /// "MuseScore 4" keeps its version in the app's name but not in its folders.
    @Test func matchesAnAppWhoseNameCarriesItsVersion() {
        let museScore = InstalledApp(
            url: URL(filePath: "/Applications/MuseScore 4.app"),
            bundleIdentifier: "org.musescore.MuseScore",
            name: "MuseScore 4"
        )
        let matcher = LeftoverMatcher(app: museScore, installedApps: [museScore])

        #expect(matcher.match(fileName: "MuseScore", kind: .applicationSupport)?.reason == .name)
        #expect(matcher.match(fileName: "MuseScore 4", kind: .caches)?.reason == .name)
        #expect(matcher.match(fileName: "Muse", kind: .applicationSupport) == nil)
    }

    /// Only a trailing number counts as a version, so a name that ends in a word is kept whole.
    @Test func keepsTheWholeNameWhenTheLastWordIsNotAVersion() {
        #expect(Naming.withoutTrailingVersion("MuseScore 4") == "MuseScore")
        #expect(Naming.withoutTrailingVersion("Python 3.12") == "Python")
        #expect(Naming.withoutTrailingVersion("Hidden Bar") == nil)
        #expect(Naming.withoutTrailingVersion("Adobe 2021") == nil, "what is left has to name the app")
        #expect(Naming.withoutTrailingVersion("Numi") == nil)
    }

    /// The matcher only reports evidence. `LeftoverScanner.heldBack` decides that `~/.jotter` is shown but never
    /// selected, after `nested(in:)` has used the same evidence to decide whether to list the item at all. See
    /// `aHiddenHomeEntryOnANameIsShownAndNeverSelected`.
    @Test func aHiddenHomeFolderStillCarriesItsFullEvidence() {
        let app = InstalledApp(
            url: URL(filePath: "/Applications/Jotter.app"),
            bundleIdentifier: "com.example.jotter",
            name: "Jotter"
        )
        let matcher = LeftoverMatcher(app: app, installedApps: [app])

        let hidden = matcher.match(fileName: ".jotter", kind: .hiddenHomeFiles)
        #expect(hidden?.reason == MatchReason.name)
        #expect(hidden?.confidence == MatchConfidence.likely, "the nested walk takes an item only on this")

        #expect(matcher.match(fileName: "Jotter", kind: .applicationSupport)?.isRecommended == true)
        #expect(matcher.match(fileName: ".com.example.jotter", kind: .hiddenHomeFiles)?.isRecommended == true)
    }

    /// A bundle writes its own identifier, so one that is a single word counts for no more than a name. An app
    /// that really has that name then shares the item, rather than losing it to the claimant.
    @Test func aOneWordIdentifierIsWorthNoMoreThanAName() throws {
        let signal = app("org.whispersystems.signal-desktop", name: "Signal")
        let planted = app("Signal", name: "Free Game")
        let carrier = app("com.example.game", name: "Free Game", embedded: ["Signal"])

        for thief in [planted, carrier] {
            let taken = try #require(match("Signal", in: .applicationSupport, for: thief, with: [signal]))
            #expect(!taken.isRecommended, "ATTACK SUCCEEDED: \(thief.bundleIdentifier) takes Signal's folder")
            #expect(taken.sharedWith == [signal.bundleIdentifier])

            let owned = try #require(match("Signal", in: .applicationSupport, for: signal, with: [thief]), "the real owner no longer sees its own folder")
            #expect(owned.sharedWith == [thief.bundleIdentifier])
        }
        #expect(match("Signal", in: .applicationSupport, for: planted)?.confidence == .likely)
        #expect(match("com.example.game", in: .caches, for: carrier)?.confidence == .certain)
    }

    /// A one word identifier is held to the rule a name is: a word any folder could be called claims nothing. A job's
    /// label is free text, and one called "updater" is not a claim on every folder of that name.
    @Test func aOneWordIdentifierTooCommonForANameClaimsNothing() {
        let tool = app("com.example.tool", name: "Example Tool", embedded: ["updater", "Helper", "tl"])

        #expect(match("updater", in: .applicationSupport, for: tool) == nil)
        #expect(match("Helper", in: .caches, for: tool) == nil)
        #expect(match("tl", in: .preferences, for: tool) == nil)
        #expect(match("com.example.tool", in: .caches, for: tool)?.confidence == .certain)
    }

    /// A real identifier can have two components or a first one longer than a country or a company's short domain:
    /// Arc is `company.thebrowser.Browser`, Obsidian `md.obsidian`, Notion `notion.id`. A file named exactly by one is
    /// that app's, as certain as any, and so is one named by an identifier it embeds.
    @Test func anIdentifierOfAnyValidShapeProvesItsOwnFiles() throws {
        for (identifier, name) in [("company.thebrowser.Browser", "Arc"), ("md.obsidian", "Obsidian"), ("notion.id", "Notion")] {
            let owned = try #require(match("\(identifier).plist", in: .preferences, for: app(identifier, name: name)))
            #expect(owned.reason == .bundleIdentifier, "\(identifier)")
            #expect(owned.confidence == .certain, "\(identifier)")
        }
        let arc = app("company.thebrowser.Browser", name: "Arc", embedded: ["company.thebrowser.browser.helper"])
        let helper = try #require(match("company.thebrowser.browser.helper", in: .caches, for: arc))
        #expect(helper.reason == .embeddedBundleIdentifier)
        #expect(helper.confidence == .certain)
    }

    /// When one app claims an item by name and another by identifier, neither claim wins, whatever their ranks.
    @Test func aNameAndAnIdentifierThatBothClaimAnItemShareIt() throws {
        let target = app("com.example.notes", name: "Notes Pro")
        let namesake = app("org.other.thing", name: "Com Example Notes")

        let claimed = try #require(match("com.example.notes", in: .caches, for: target, with: [namesake]))
        #expect(claimed.sharedWith == [namesake.bundleIdentifier])
        #expect(try #require(match("com.example.notes", in: .caches, for: namesake, with: [target])).sharedWith == [target.bundleIdentifier])
    }

    /// Any developer can write one of Apple's groups into an app's entitlements. macOS would not grant it, and
    /// Peel does not believe it: only an app Apple signed matches Apple's groups, in any of their spellings.
    @Test func applesGroupsAreNotForAnotherAppToClaim() {
        let groups = ["243LU875E5.groups.com.apple.podcasts", "group.com.apple.notes", "systemgroup.com.apple.configurationprofiles"]
        let claimant = app("com.example.tool", name: "Tool", team: "ABCDE12345", groups: groups)

        for group in groups {
            #expect(match(group, in: .groupContainers, for: claimant) == nil, "\(group) was given to an app that is not Apple's")
        }
        #expect(match("ABCDE12345.com.example.tool", in: .groupContainers, for: app("com.example.tool", name: "Tool", team: "ABCDE12345", groups: ["ABCDE12345.com.example.tool"]))?.confidence == .certain)
    }

    /// A hidden file outside the home folder is the system's own: `.GlobalPreferences.plist` is the global domain.
    @Test func neverMatchesAHiddenFileOutsideTheHomeFolder() {
        let named = app("com.example.tool", name: "Global Preferences")
        let identified = app(".GlobalPreferences", name: "Tool")

        for target in [named, identified] {
            #expect(match(".GlobalPreferences.plist", in: .preferences, for: target) == nil)
            #expect(match(".GlobalPreferences.0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9.plist", in: .preferencesByHost, for: target) == nil)
            #expect(match(".GlobalPreferences", in: .applicationSupport, for: target) == nil)
        }
        #expect(match(".globalpreferences", in: .hiddenHomeFiles, for: named) != nil)
    }

    @Test func aPlugInIsMatchedWithoutTheExtensionThatSaysItsKind() throws {
        let serum = app("com.xferrecords.serum", name: "Serum")
        for name in [
            "Serum.vst3", "Serum.vst", "Serum.component", "Serum.clap", "Serum.saver", "Serum.aaxplugin", "Serum.action",
            "Serum.dictionary", "Serum.appex", "Serum.prefPane", "Serum.colorPicker", "Serum.kext", "Serum.fs",
        ] {
            let found = try #require(match(name, in: .plugIns, for: serum), "\(name)")
            #expect(found.reason == .name, "\(name)")
            #expect(found.confidence == .likely, "\(name)")
        }
        #expect(match("com.xferrecords.serum.qlgenerator", in: .plugIns, for: serum)?.confidence == .certain)
    }

    @Test func aFrameworkIsMatchedWithoutItsExtension() throws {
        let serum = app("com.xferrecords.serum", name: "Serum")
        #expect(match("Serum.framework", in: .frameworks, for: serum)?.reason == .name)
        #expect(match("com.xferrecords.serum.framework", in: .frameworks, for: serum)?.confidence == .certain)
    }

    /// An extension missing from the table stays in the key, and its dot reads as a separator. The plug-in is
    /// then only a name prefix match: shown as a guess, never selected as the app's own.
    @Test func anUnknownPlugInKindIsNeverTakenForTheAppsOwn() throws {
        let serum = app("com.xferrecords.serum", name: "Serum")
        let found = try #require(match("Serum.rtas", in: .plugIns, for: serum))
        #expect(found.reason == .namePrefix)
        #expect(found.confidence == .possible)
    }

    /// A workflow in `~/Library/Services` whose name merely begins with the app's name is only a guess.
    @Test func aServiceNamedAfterTheAppIsOnlyEverPossible() throws {
        let jotter = app("com.example.jotter", name: "Jotter")
        let found = try #require(match("Jotter - New Note.workflow", in: .plugIns, for: jotter))
        #expect(found.reason == .namePrefix)
        #expect(found.confidence == .possible)
    }

    @Test func aPlugInOfAnotherAppIsNotThisAppsToTake() {
        let serum = app("com.xferrecords.serum", name: "Serum")
        let massive = app("com.native-instruments.massive", name: "Massive")
        #expect(match("Massive.vst3", in: .plugIns, for: serum, with: [massive]) == nil)
    }
}
