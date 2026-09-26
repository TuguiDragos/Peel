import Foundation
@testable import PeelCore
import Testing

struct CaskEvidenceTests {
    @Test func prefersWhatHomebrewInstalledOverWhatItMerelyKnows() {
        let installed = [
            HomebrewPackage(name: "adguard", kind: .cask, installedVersion: "2.19", leftoverPatterns: ["~/Library/Application Support/AdGuard"]),
            HomebrewPackage(name: "openssl@3", kind: .formula, installedVersion: "3.6.3"),
        ]
        let known = [
            HomebrewPackage(name: "adguard", kind: .cask),
            HomebrewPackage(name: "iterm2", kind: .cask, leftoverPatterns: ["~/Library/Preferences/com.googlecode.iterm2.plist"]),
        ]

        let combined = CaskEvidence.combined(installed: installed, known: known, receipts: [])

        #expect(combined.map(\.id) == ["cask/adguard", "cask/iterm2", "formula/openssl@3"])
        #expect(combined.first?.installedVersion == "2.19")
        #expect(combined.first?.leftoverPatterns == ["~/Library/Application Support/AdGuard"])
    }

    /// A cask shaped as `brew info --json=v2 --installed` writes one.
    private let caskJSON = """
    {
      "formulae": [],
      "casks": [
        {
          "token": "sample",
          "desc": "A sample app",
          "homepage": "https://example.org/sample",
          "installed": "2.1.0",
          "version": "2.1.0",
          "outdated": false,
          "artifacts": [
            {"uninstall": [{"launchctl": "org.example.SampleHelper*", "quit": "org.example.Sample", "login_item": "Sample"}]},
            {"app": ["Sample.app"], "target": "/Applications/Sample.app"},
            {"binary": ["/Applications/Sample.app/Contents/MacOS/Sample", {"target": "sample"}], "target": "/opt/homebrew/bin/sample"},
            {"zap": [{"trash": ["~/Library/Application Support/Sample", "~/Library/Caches/org.example.Sample", "~/Library/Containers/org.example.Sample*"]}]}
          ]
        }
      ]
    }
    """

    private func casks() throws -> [HomebrewPackage] {
        let packages = try #require(Homebrew.parseInstalled(Data(caskJSON.utf8)))
        return packages
    }

    /// An installed cask says where Homebrew linked each command it put on the path, which are the links
    /// `brew uninstall` removes. A cask that is not installed has linked nothing.
    @Test func readsWhereHomebrewLinkedACasksCommands() throws {
        let cask = try #require(try casks().first { $0.kind == .cask })
        #expect(cask.commandLinks == ["/opt/homebrew/bin/sample"])
        #expect(cask.appTargets == ["/Applications/Sample.app"], "a command's link was read as the app's place")

        let notInstalled = #"{"binary": ["$APPDIR/Sample.app/Contents/MacOS/Sample", {"target": "sample"}]}"#
        let known = try JSONDecoder().decode(CaskArtifact.self, from: Data(notInstalled.utf8))
        #expect(known.commandLinks.isEmpty)
    }

    @Test func readsAppsAndLeftoverPathsFromACask() throws {
        let cask = try #require(try casks().first { $0.kind == .cask })
        #expect(cask.name == "sample")
        #expect(cask.appNames == ["Sample.app"])
        #expect(cask.leftoverPatterns == [
            "~/Library/Application Support/Sample",
            "~/Library/Caches/org.example.Sample",
            "~/Library/Containers/org.example.Sample*",
        ])
    }

    /// The `zap` stanza `brew info --json=v2 --cask jetbrains-toolbox` reports.
    private let toolboxJSON = """
    {
      "formulae": [],
      "casks": [
        {
          "token": "jetbrains-toolbox",
          "installed": "2.6",
          "version": "2.6",
          "outdated": false,
          "artifacts": [
            {"app": ["JetBrains Toolbox.app"]},
            {"zap": [{
              "trash": ["~/Library/Application Support/JetBrains/Toolbox", "~/Library/Logs/JetBrains/Toolbox"],
              "rmdir": ["~/Library/Application Support/JetBrains", "~/Library/Caches/JetBrains", "~/Library/Logs/JetBrains"]
            }]}
          ]
        }
      ]
    }
    """

    /// Homebrew removes an `rmdir` folder only when it is empty, so one holding another app's files is no leftover.
    @Test func offersAFolderHomebrewRemovesWhenEmptyOnlyWhenItIsEmpty() throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Application Support/JetBrains/Toolbox/state.json")
        try directory.file("Library/Application Support/JetBrains/IntelliJIdea2026.2/options/ide.general.xml")
        try directory.directory("Library/Logs/JetBrains/Toolbox")
        try directory.file("Library/Logs/JetBrains/.DS_Store")
        let elsewhere = try directory.directory("Elsewhere")
        try directory.directory("Library/Caches")
        try FileManager.default.createSymbolicLink(
            at: directory.url.appending(path: "Library/Caches/JetBrains"),
            withDestinationURL: elsewhere
        )

        let cask = try #require(Homebrew.parseInstalled(Data(toolboxJSON.utf8))?.first)
        let app = InstalledApp(url: URL(filePath: "/Applications/JetBrains Toolbox.app"), bundleIdentifier: "com.jetbrains.toolbox", name: "JetBrains Toolbox")
        let evidence = try #require(CaskEvidence.evidence(for: app, casks: [cask], home: directory.url))
        let offered = Set(evidence.items.map { PathPattern.comparablePath(of: $0.url) })
        let library = PathPattern.comparablePath(of: directory.url) + "/Library/"

        #expect(offered == [
            library + "Application Support/JetBrains/Toolbox",
            library + "Logs/JetBrains/Toolbox",
            library + "Logs/JetBrains",
        ])
    }

    @Test func findsTheCaskBehindAnApp() throws {
        let packages = try casks()
        let app = InstalledApp(url: URL(filePath: "/Applications/Sample.app"), bundleIdentifier: "org.example.Sample", name: "Sample")
        let other = InstalledApp(url: URL(filePath: "/Applications/Something.app"), bundleIdentifier: "com.example.something", name: "Something")

        #expect(CaskEvidence.cask(for: app, in: packages)?.name == "sample")
        #expect(CaskEvidence.cask(for: other, in: packages) == nil)
    }

    @Test func expandsPathsAndGlobsThatReallyExist() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("Library/Application Support/Example")
        try directory.directory("Library/Containers/com.example.app.one")
        try directory.directory("Library/Containers/com.example.app.two")
        let home = directory.url

        #expect(CaskEvidence.expand("~/Library/Application Support/Example", home: home).count == 1)
        #expect(CaskEvidence.expand("~/Library/Application Support/Missing", home: home).isEmpty)
        #expect(CaskEvidence.expand("~/Library/Containers/com.example.app*", home: home).count == 2)
        #expect(CaskEvidence.expand("relative/path", home: home).isEmpty)
    }

    @Test func marksPathsOutsideLibraryAsNotRecommended() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url
        try directory.directory("Library/Caches/com.example.app")
        try directory.directory("Documents/Example Projects")
        let cask = HomebrewPackage(
            name: "example",
            kind: .cask,
            appNames: ["Example.app"],
            leftoverPatterns: ["~/Library/Caches/com.example.app", "~/Documents/Example Projects"]
        )
        let app = InstalledApp(url: URL(filePath: "/Applications/Example.app"), bundleIdentifier: "com.example.app", name: "Example")

        let evidence = try #require(CaskEvidence.evidence(for: app, casks: [cask], home: home))
        #expect(evidence.items.count == 2)
        #expect(evidence.items.filter(\.isInLibrary).count == 1)

        let matcher = LeftoverMatcher(app: app, installedApps: [app])
        let leftovers = await Uninstallation.caskLeftovers(evidence, app: app, exclusions: .none, matcher: matcher, environment: environment(home))
        #expect(leftovers.count == 2)
        #expect(leftovers.allSatisfy { $0.match.reason == .homebrewCask })
        #expect(leftovers.filter(\.match.isRecommended).count == 1)
    }

    private func environment(_ home: URL) -> SearchEnvironment {
        SearchEnvironment(homeDirectory: home, rootDirectory: home.appending(path: "root", directoryHint: .isDirectory))
    }

    /// Homebrew says it itself: `zap` may remove what other apps share. A folder only the cask names, with
    /// nothing of the app's own to back it up, is a vendor's folder as often as not, so it is shown and not selected.
    @Test func ticksACaskPathOnlyWhenTheAppItselfAnswersToIt() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url
        try directory.directory("Library/Application Support/Microsoft")
        try directory.file("Library/Preferences/com.electron.worddesktop.plist")
        try directory.directory("Library/Caches/com.microsoft.Word")
        try directory.directory("Documents/Word Templates")
        let cask = HomebrewPackage(name: "microsoft-word", kind: .cask, appNames: ["Microsoft Word.app"], leftoverPatterns: [
            "~/Library/Application Support/Microsoft", "~/Library/Preferences/com.electron.worddesktop.plist",
            "~/Library/Caches/com.microsoft.Word", "~/Documents/Word Templates",
        ])
        let word = InstalledApp(url: URL(filePath: "/Applications/Microsoft Word.app"), bundleIdentifier: "com.microsoft.Word", name: "Microsoft Word")

        let evidence = try #require(CaskEvidence.evidence(for: word, casks: [cask], home: home))
        let leftovers = await Uninstallation.caskLeftovers(
            evidence, app: word, exclusions: .none, matcher: LeftoverMatcher(app: word, installedApps: [word]), environment: environment(home)
        )
        let found = Dictionary(uniqueKeysWithValues: leftovers.map { ($0.url.lastPathComponent, $0) })

        #expect(found["Microsoft"]?.match.isRecommended == false, "a vendor's folder was selected on the cask's word alone")
        #expect(found["com.electron.worddesktop.plist"]?.match.isRecommended == false)
        #expect(found["com.microsoft.Word"]?.match.isRecommended == true)
        #expect(found["Word Templates"]?.match.isRecommended == false)
        #expect(found["Microsoft"]?.kind == .applicationSupport)
        #expect(found["com.electron.worddesktop.plist"]?.kind == .preferences)
        #expect(found["com.microsoft.Word"]?.kind == .caches)
        #expect(found["Word Templates"]?.kind == .elsewhere, "a folder in Documents was called something it is not")
    }

    /// What a cask names is a folder like any other: a repository inside takes the checkmark away here as well.
    @Test func aCaskPathGoesThroughTheSameHoldBacks() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url
        try directory.file("Library/Application Support/com.example.app/checkout/.git/HEAD")
        let cask = HomebrewPackage(name: "example", kind: .cask, appNames: ["Example.app"], leftoverPatterns: ["~/Library/Application Support/com.example.app"])
        let app = InstalledApp(url: URL(filePath: "/Applications/Example.app"), bundleIdentifier: "com.example.app", name: "Example")

        let evidence = try #require(CaskEvidence.evidence(for: app, casks: [cask], home: home))
        let leftovers = await Uninstallation.caskLeftovers(
            evidence, app: app, exclusions: .none, matcher: LeftoverMatcher(app: app, installedApps: [app]), environment: environment(home)
        )

        #expect(leftovers.first?.match.heldBack == .holdsRepository)
        #expect(leftovers.first?.match.isRecommended == false)
    }

    /// A cask names paths, and a path another installed app answers to is not this app's to select.
    @Test func doesNotSelectACaskPathAnotherInstalledAppAlsoClaims() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url
        try directory.directory("Library/Caches/com.vendor.shared")

        let cask = HomebrewPackage(
            name: "example", kind: .cask,
            appNames: ["Example.app"],
            leftoverPatterns: ["~/Library/Caches/com.vendor.shared"]
        )
        let app = InstalledApp(url: URL(filePath: "/Applications/Example.app"), bundleIdentifier: "com.example.app", name: "Example")
        let other = InstalledApp(url: URL(filePath: "/Applications/Other.app"), bundleIdentifier: "com.vendor.shared", name: "Other")

        let evidence = try #require(CaskEvidence.evidence(for: app, casks: [cask], home: home))
        let matcher = LeftoverMatcher(app: app, installedApps: [app, other])
        let leftovers = await Uninstallation.caskLeftovers(evidence, app: app, exclusions: .none, matcher: matcher, environment: environment(home))

        #expect(leftovers.first?.match.sharedWith == ["com.vendor.shared"])
        #expect(leftovers.first?.match.isRecommended == false)
    }
}
