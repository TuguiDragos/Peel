import Foundation
@testable import PeelCore
import Testing

struct AppResetTests {
    private func home(_ directory: borrowing TemporaryDirectory) -> SearchEnvironment {
        SearchEnvironment(homeDirectory: directory.url, rootDirectory: directory.url.appending(path: "root"))
    }

    /// An installed app for the tests. Every scan counts the apps macOS ships as other installed apps, so a
    /// fixture for one of them sits where the real app does, or the real app would share every file with it.
    private func app(_ bundleIdentifier: String = "com.example.app", name: String = "Example", at path: String? = nil) -> InstalledApp {
        InstalledApp(
            url: URL(filePath: path ?? "/Applications/\(name).app"),
            bundleIdentifier: bundleIdentifier,
            name: name,
            // Only an app Apple signed can claim Apple's files, and these fixtures stand in for Apple's own apps.
            teamIdentifier: bundleIdentifier.hasPrefix("com.apple.") ? "59GAB85EFG" : nil
        )
    }

    @Test func sortsWhatItFindsIntoSettingsWebDataAndAppData() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Preferences/com.example.app.plist", bytes: 4096)
        try directory.file("Library/Saved Application State/com.example.app.savedState/data", bytes: 4096)
        try directory.file("Library/Caches/com.example.app/cache", bytes: 4096)
        try directory.file("Library/Cookies/com.example.app.binarycookies", bytes: 4096)
        try directory.file("Library/WebKit/com.example.app/site", bytes: 4096)
        try directory.file("Library/Application Support/com.example.app/notes.db", bytes: 4096)

        let reset = await AppReset.prepare(app(), installedApps: [app()], environment: home(directory))

        #expect(Set(reset.items(in: .settings).map(\.kind)) == [.preferences, .savedApplicationState, .caches])
        #expect(Set(reset.items(in: .webData).map(\.kind)) == [.cookies, .webKit])
        #expect(Set(reset.items(in: .appData).map(\.kind)) == [.applicationSupport])
        #expect(reset.suggestedSelection == Set(reset.items(in: .settings).map(\.url)))
        #expect(!reset.keepsAppData)
    }

    /// The confirmation names what a group costs only when something of that group is selected.
    @Test func tellsWhichGroupsASelectionReaches() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Preferences/com.example.app.plist", bytes: 4096)
        try directory.file("Library/Cookies/com.example.app.binarycookies", bytes: 4096)
        try directory.file("Library/Application Support/com.example.app/notes.db", bytes: 4096)

        let reset = await AppReset.prepare(app(), installedApps: [app()], environment: home(directory))
        let cookies = try #require(reset.items(in: .webData).first).url

        #expect(reset.groups(in: reset.suggestedSelection) == [.settings])
        #expect(reset.groups(in: reset.suggestedSelection.union([cookies])) == [.settings, .webData])
        #expect(reset.groups(in: []).isEmpty)
    }

    @Test func offersNothingForAnExcludedApp() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Preferences/com.example.app.plist", bytes: 4096)
        let exclusions = Exclusions(bundleIdentifiers: ["com.example.app"])

        let reset = await AppReset.prepare(
            app(),
            installedApps: [app()],
            exclusions: exclusions,
            environment: home(directory)
        )

        #expect(reset.items.isEmpty)
        #expect(reset.suggestedSelection.isEmpty)
    }

    /// A reset makes an app forget its settings. Removing its launch agents or helpers would break it instead.
    @Test func leavesLaunchAgentsAndHelpersAlone() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Preferences/com.example.app.plist", bytes: 4096)
        try directory.file("Library/LaunchAgents/com.example.app.plist", bytes: 4096)

        let reset = await AppReset.prepare(app(), installedApps: [app()], environment: home(directory))

        #expect(reset.items.map(\.kind) == [.preferences])
        #expect(AppReset.group(for: .launchAgents) == nil)
        #expect(AppReset.group(for: .launchDaemons) == nil)
        #expect(AppReset.group(for: .privilegedHelperTools) == nil)
    }

    @Test func neverOffersTheDataOfMailMessagesNotesOrPhotos() async throws {
        let apps = ["com.apple.mail": "Mail", "com.apple.MobileSMS": "Messages", "com.apple.Notes": "Notes", "com.apple.Photos": "Photos"]
        for (identifier, name) in apps {
            let directory = try TemporaryDirectory()
            try directory.file("Library/Preferences/\(identifier).plist", bytes: 4096)
            try directory.file("Library/Application Support/\(identifier)/store.db", bytes: 4096)
            try directory.file("Library/Containers/\(identifier)/Data/everything", bytes: 4096)
            let subject = app(identifier, name: name, at: "/System/Applications/\(name).app")

            let reset = await AppReset.prepare(subject, installedApps: [subject], environment: home(directory))

            #expect(reset.keepsAppData)
            #expect(reset.items(in: .appData).isEmpty, "\(identifier) offered its data")
            #expect(reset.items(in: .settings).map(\.kind) == [.preferences])
        }
    }

    /// A file shared with another installed app is never part of this app's reset.
    @Test func skipsAnythingSharedWithAnotherInstalledApp() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Application Support/Vendor/shared.db", bytes: 4096)
        let first = InstalledApp(
            url: URL(filePath: "/Applications/First.app"),
            bundleIdentifier: "com.vendor.first",
            name: "Vendor",
            teamIdentifier: "ABCDE12345"
        )
        let second = InstalledApp(
            url: URL(filePath: "/Applications/Second.app"),
            bundleIdentifier: "com.vendor.second",
            name: "Vendor",
            teamIdentifier: "ABCDE12345"
        )

        let reset = await AppReset.prepare(first, installedApps: [first, second], environment: home(directory))
        #expect(reset.items.isEmpty)
    }

    /// Every copy of an app writes the same settings, and a reset quits them all first, so another copy keeps
    /// nothing out of it. Another app's claim does.
    @Test func anotherCopyOfTheAppKeepsNothingOutOfAReset() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Preferences/com.example.app.plist", bytes: 4096)
        let copy = app(at: "/Users/x/Downloads/Example.app")

        let reset = await AppReset.prepare(app(), installedApps: [app(), copy], environment: home(directory))

        #expect(reset.items.map(\.kind) == [.preferences])
    }

    /// A container holds settings next to the user's documents, so it is opened up rather than offered whole.
    @Test func opensAContainerUpAndLeavesTheUsersWorkInsideItAlone() async throws {
        let directory = try TemporaryDirectory()
        let container = try directory.directory("Library/Containers/com.example.app")
        try directory.file("Library/Containers/com.example.app/Data/Library/Preferences/com.example.app.plist", bytes: 4096)
        try directory.file("Library/Containers/com.example.app/Data/Library/Caches/cache", bytes: 4096)
        try directory.file("Library/Containers/com.example.app/Data/Library/Cookies/jar", bytes: 4096)
        try directory.file("Library/Containers/com.example.app/Data/Library/Application Support/store.db", bytes: 4096)
        try directory.file("Library/Containers/com.example.app/Data/Library/Autosave Information/draft", bytes: 4096)
        try directory.file("Library/Containers/com.example.app/Data/Documents/report.pages", bytes: 4096)
        try directory.file("Library/Preferences/com.apple.security.plist", bytes: 4096)
        try FileManager.default.createSymbolicLink(
            at: container.appending(path: "Data/Library/Preferences/com.apple.security.plist"),
            withDestinationURL: directory.url.appending(path: "Library/Preferences/com.apple.security.plist")
        )
        // A folder `containerFolders` lists, as a link back out to the home folder, which is how a container holds
        // what it shares. It has to be a listed folder, or the test would pass without checking the link.
        try directory.directory("Library/Logs")
        try FileManager.default.createSymbolicLink(
            at: container.appending(path: "Data/Library/Logs"),
            withDestinationURL: directory.url.appending(path: "Library/Logs")
        )
        try directory.file("Library/Containers/com.example.app/Data/Library/Preferences/com.example.appother.plist", bytes: 4096)
        try directory.file("Library/Containers/com.example.app/Data/Library/SyncedPreferences/com.example.app.plist", bytes: 4096)

        let reset = await AppReset.prepare(app(), installedApps: [app()], environment: home(directory))
        let names = Set(reset.items.map(\.url.lastPathComponent))

        #expect(names.contains("com.example.app.plist"))
        #expect(names.contains("Caches"))
        #expect(names.contains("Cookies"))
        #expect(!names.contains("Application Support"), "the app's own store inside the container was offered")
        #expect(!names.contains("Documents"), "the user's documents were offered")
        #expect(!names.contains("Autosave Information"), "unsaved work was offered")
        #expect(!names.contains("Logs"), "a symlink out of the container was offered")
        #expect(!names.contains("com.example.appother.plist"), "a name that only starts the same was offered")
        #expect(!reset.items.contains { $0.url.path(percentEncoded: false).contains("SyncedPreferences") }, "the local side of iCloud's key-value store was offered")
        #expect(!names.contains("com.apple.security.plist"), "a shared system preference was offered")
        #expect(!names.contains("com.example.app"), "the whole container was offered")
        #expect(reset.items.allSatisfy { $0.kind != .containers })
        #expect(!reset.needsFullDiskAccess)
    }

    /// A wallet can keep its keys in its container's `Caches`, as BlueWallet does. A reset still clears the settings
    /// beside them, with documents in the container or without, and never offers the folder that holds the keys.
    @Test func neverOffersAFolderInAContainerThatHoldsAWallet() async throws {
        for hasDocuments in [false, true] {
            let directory = try TemporaryDirectory()
            let blueWallet = app("io.bluewallet.bluewallet", name: "BlueWallet")
            try directory.file("Library/Containers/io.bluewallet.bluewallet/Data/Library/Caches/keyvalue.realm", bytes: 4096)
            try directory.file("Library/Containers/io.bluewallet.bluewallet/Data/Library/Cookies/jar", bytes: 4096)
            if hasDocuments {
                try directory.file("Library/Containers/io.bluewallet.bluewallet/Data/Documents/export.pdf", bytes: 4096)
            }

            let reset = await AppReset.prepare(blueWallet, installedApps: [blueWallet], environment: home(directory))
            let names = Set(reset.items.map(\.url.lastPathComponent))

            #expect(names.contains("Cookies"), "the settings beside the wallet were not offered")
            #expect(!names.contains("Caches"), "the folder holding the wallet was offered")
        }
    }

    @Test func keepsTheDataInsideAContainerWhenTheAppIsOneOfTheFour() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Containers/com.apple.Notes/Data/Library/Preferences/com.apple.Notes.plist", bytes: 4096)
        try directory.file("Library/Containers/com.apple.Notes/Data/Library/Application Support/NoteStore.sqlite", bytes: 4096)
        let notes = app("com.apple.Notes", name: "Notes", at: "/System/Applications/Notes.app")

        let reset = await AppReset.prepare(notes, installedApps: [notes], environment: home(directory))

        #expect(reset.items(in: .appData).isEmpty)
        #expect(reset.items(in: .settings).map(\.url.lastPathComponent) == ["com.apple.Notes.plist"])
        #expect(reset.keepsAppData)
    }

    @Test func movesOnlyWhatIsSelected() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Caches/com.example.app/cache", bytes: 4096)
        try directory.file("Library/Preferences/com.example.app.plist", bytes: 4096)

        let reset = await AppReset.prepare(app(), installedApps: [app()], environment: home(directory))
        let settings = try #require(reset.items.first { $0.kind == .preferences }).url

        #expect(reset.selected(reset.suggestedSelection).count == 2)
        #expect(reset.selected([settings, URL(filePath: "/somewhere/else")]) == [settings])
        #expect(reset.size(of: reset.suggestedSelection) == reset.size(of: Set(reset.items.map(\.url))))
    }

    /// A reset ends in `defaults delete`, so it takes only what is certainly this app's. A name is not enough,
    /// since "Yarn" or "Pip" can also be a tool's, and neither is an identifier that only starts with the app's.
    @Test func aNameIsNotEnoughForAReset() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Preferences/com.example.app.plist", bytes: 4096)
        try directory.file("Library/Preferences/Example.plist", bytes: 4096)
        try directory.file("Library/Caches/Example/blob", bytes: 4096)
        try directory.file("Library/Caches/com.example.app.unlisted/blob", bytes: 4096)

        let reset = await AppReset.prepare(app(), installedApps: [app()], environment: home(directory))

        #expect(Set(reset.items.map(\.url.lastPathComponent)) == ["com.example.app.plist"])
    }

    /// A reset clears what the app makes again and nothing that may exist nowhere else: a folder in a container that
    /// holds a wallet or a repository is never offered, as the uninstall holds such a folder back. The container is
    /// looked into because it is held back only for the documents in it.
    @Test func aFolderInAContainerHoldingAWalletOrARepositoryIsNotOffered() async throws {
        let directory = try TemporaryDirectory()
        let library = "Library/Containers/com.example.app/Data/Library"
        try directory.file("Library/Containers/com.example.app/Data/Documents/letter.txt", bytes: 4096)
        try directory.file("\(library)/Caches/coin/wallet.dat", bytes: 4096)
        try directory.file("\(library)/Logs/mirror/.git/HEAD", bytes: 4096)
        try directory.file("\(library)/WebKit/site", bytes: 4096)

        let reset = await AppReset.prepare(app(), installedApps: [app()], environment: home(directory))

        #expect(reset.items.map(\.url.lastPathComponent) == ["WebKit"])
    }

    /// A folder in a container that did not answer in time is not known to hold only what the app makes again, so a
    /// reset does not offer it: it is not read as empty, and nothing unknown is selected.
    @Test func aFolderInAContainerThatDidNotAnswerInTimeIsNotOffered() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Containers/com.example.app/Data/Library/Caches/cache", bytes: 400_000)
        try directory.file("Library/Containers/com.example.app/Data/Library/Logs/app.log", bytes: 4096)

        let reset = await AppReset.prepare(
            app(),
            installedApps: [app()],
            exclusions: .none,
            environment: home(directory)
        ) { url in
            url.lastPathComponent == "Caches" ? nil : await FileSize.contents(of: url)
        }

        #expect(reset.items.map(\.url.lastPathComponent) == ["Logs"])
        #expect(reset.size(of: reset.suggestedSelection).isComplete)
        #expect(reset.size(of: reset.suggestedSelection).known >= 4096)
    }

    /// A reset never takes code macOS loads, even a plug-in that is certainly the app's.
    @Test func neverClearsAPlugIn() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("Library/Preferences/com.example.app.plist", bytes: 4096)
        try directory.file("Library/QuickLook/Example.qlgenerator/Contents/Info.plist", bytes: 4096)
        try directory.file("Library/Audio/Plug-Ins/VST3/Example.vst3/Contents/Info.plist", bytes: 4096)

        let reset = await AppReset.prepare(app(), installedApps: [app()], environment: home(directory))

        #expect(reset.items.map(\.url.lastPathComponent) == ["com.example.app.plist"])
        #expect(AppReset.group(for: .plugIns) == nil)
    }
}
