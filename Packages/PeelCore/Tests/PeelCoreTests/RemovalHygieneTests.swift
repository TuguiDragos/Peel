import Foundation
@testable import PeelCore
import Synchronization
import Testing

struct RemovalHygieneTests {
    /// A service for the saves and restores below, which move nothing of their own: one that did would be refused.
    private static let service = TrashService(
        environment: SearchEnvironment(homeDirectory: URL(filePath: "/nonexistent/home"), rootDirectory: URL(filePath: "/nonexistent/root"))
    ) { _ in throw CocoaError(.fileWriteNoPermission) }

    private let home = URL(filePath: "/Users/x", directoryHint: .isDirectory)
    /// The host UUID of the Mac these tests pretend to run on, as its ByHost file names carry it.
    private let host = "0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9"

    private func launchdPlist(
        _ path: String,
        label: String?,
        in directory: borrowing TemporaryDirectory
    ) throws -> URL {
        let contents = try PropertyListSerialization.data(
            fromPropertyList: label.map { ["Label": $0] } ?? [:],
            format: .xml,
            options: 0
        )
        return try directory.file(path, contents: contents)
    }

    /// launchd knows a job by the `Label` inside its file, which the file name only usually repeats.
    @Test func findsTheJobsBehindLaunchdPlists() throws {
        let directory = try TemporaryDirectory()
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home"),
            rootDirectory: directory.url.appending(path: "root")
        )
        let agent = try launchdPlist("home/Library/LaunchAgents/updater.plist", label: "com.example.agent", in: directory)
        let shared = try launchdPlist("root/Library/LaunchAgents/com.example.shared.plist", label: "com.example.shared", in: directory)
        let daemon = try launchdPlist("root/Library/LaunchDaemons/com.example.helper.plist", label: "com.example.helper", in: directory)
        let others = [
            try launchdPlist("home/Library/Application Support/com.example.app/config.plist", label: "com.example.config", in: directory),
            try launchdPlist("root/Library/LaunchDaemons/something.plist", label: "com.apple.something", in: directory),
            try launchdPlist("home/Library/LaunchAgents/com.example.unnamed.plist", label: nil, in: directory),
            try directory.file("home/Library/LaunchAgents/com.example.broken.plist"),
            try directory.file("home/Library/LaunchAgents/notes.txt"),
            URL(filePath: "/Library/LaunchDaemons/com.example.elsewhere.plist"),
        ]

        // Kept in a repository and linked into place: the job is the one the link leads to.
        let linked = directory.url.appending(path: "home/Library/LaunchAgents/linked.plist")
        try FileManager.default.createSymbolicLink(
            at: linked,
            withDestinationURL: try launchdPlist("home/dotfiles/agent.plist", label: "com.example.linked", in: directory)
        )

        let jobs = LaunchdCleanup.jobs(for: [linked, agent, shared, daemon] + others, environment: environment)
        #expect(jobs == [
            LaunchdCleanup.Job(label: "com.example.linked", isDaemon: false, plist: linked),
            LaunchdCleanup.Job(label: "com.example.agent", isDaemon: false, plist: agent),
            LaunchdCleanup.Job(label: "com.example.shared", isDaemon: false, plist: shared),
            LaunchdCleanup.Job(label: "com.example.helper", isDaemon: true, plist: daemon),
        ])
    }

    @Test func findsThePreferenceDomainsToForget() {
        let urls = [
            URL(filePath: "/Users/x/Library/Preferences/com.example.app.plist"),
            URL(filePath: "/Users/x/Library/Preferences/ByHost/com.example.app.0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9.plist"),
            URL(filePath: "/Users/x/Library/Preferences/com.apple.finder.plist"),
            URL(filePath: "/Users/x/Library/Application Support/com.example.app"),
        ]

        let domains = PreferenceCleanup.domains(for: urls, home: home, host: host)
        #expect(domains == [
            PreferenceCleanup.Domain(name: "com.example.app", isByHost: false),
            PreferenceCleanup.Domain(name: "com.example.app", isByHost: true),
        ])
    }

    /// `-currentHost` means the Mac Peel runs on, so a ByHost file another Mac left names no domain.
    @Test func forgetsNothingForAByHostFileFromAnotherMac() {
        let urls = [
            URL(filePath: "/Users/x/Library/Preferences/ByHost/com.example.app.FFFFFFFF-0000-1111-2222-333333333333.plist"),
            URL(filePath: "/Users/x/Library/Preferences/ByHost/com.example.app.001122334455.plist"),
            URL(filePath: "/Users/x/Library/Preferences/ByHost/com.example.app.plist"),
        ]
        let ours = URL(filePath: "/Users/x/Library/Preferences/ByHost/com.example.app.\(host.lowercased()).plist")

        #expect(PreferenceCleanup.domains(for: urls, home: home, host: host).isEmpty)
        #expect(PreferenceCleanup.domains(for: urls + [ours], home: home, host: host) == [
            PreferenceCleanup.Domain(name: "com.example.app", isByHost: true),
        ])
        #expect(PreferenceCleanup.domains(for: urls + [ours], home: home, host: "").isEmpty)
        #expect(UUID(uuidString: PreferenceCleanup.hostIdentifier) != nil)
    }

    /// `defaults` reads a bare name as the user's domain, never the file in `/Library/Preferences` all users share.
    @Test func forgetsNothingForAPreferenceFileSharedByAllUsers() {
        let urls = [URL(filePath: "/Library/Preferences/com.example.app.plist")]

        #expect(PreferenceCleanup.domains(for: urls, home: home).isEmpty)
    }

    /// After the verb, `defaults` would read `-currentHost` as the domain and the domain as a key.
    @Test func putsCurrentHostBeforeTheVerb() {
        let byHost = PreferenceCleanup.Domain(name: "com.example.app", isByHost: true)
        let plain = PreferenceCleanup.Domain(name: "com.example.app", isByHost: false)

        #expect(byHost.command("delete") == ["-currentHost", "delete", "com.example.app"])
        #expect(byHost.command("export", "/tmp/saved.plist") == ["-currentHost", "export", "com.example.app", "/tmp/saved.plist"])
        #expect(plain.command("delete") == ["delete", "com.example.app"])
    }

    /// The first five names all belong to the global preferences, and Apple gives its own agents one-word domains.
    @Test func neverForgetsTheGlobalDomainOrAnAgentsDomain() {
        let names = [
            ".GlobalPreferences", ".GlobalPreferences_m", "NSGlobalDomain", "Apple Global Domain",
            "kCFPreferencesAnyApplication", "loginwindow", "pbs",
        ]
        let urls = names.map { URL(filePath: "/Users/x/Library/Preferences/\($0).plist") } + [
            URL(filePath: "/Users/x/Library/Preferences/ByHost/.GlobalPreferences.0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9.plist"),
            URL(filePath: "/Users/x/Library/Preferences/COM.APPLE.DOCK.plist"),
        ]

        #expect(PreferenceCleanup.domains(for: urls, home: home, host: host).isEmpty)
        for name in names {
            #expect(PreferenceBackup.domain(from: name + ".plist") == nil)
            #expect(PreferenceBackup.domain(from: name + ".ByHost.plist") == nil)
        }
    }

    /// When an app has a container, `defaults` reads its domain from there, so the domain is forgotten only
    /// when the container's own file is going too.
    @Test func keepsTheDomainOfAContainerThatStays() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let stray = try directory.file("home/Library/Preferences/com.example.app.plist")
        let strayByHost = try directory.file("home/Library/Preferences/ByHost/com.example.app.0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9.plist")
        let contained = try directory.file("home/Library/Containers/com.example.app/Data/Library/Preferences/com.example.app.plist")
        let containedByHost = try directory.file("home/Library/Containers/com.example.app/Data/Library/Preferences/ByHost/com.example.app.0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9.plist")

        #expect(PreferenceCleanup.domains(for: [stray, strayByHost], home: home, host: host).isEmpty)
        #expect(PreferenceCleanup.domains(for: [stray, strayByHost, contained], home: home, host: host) == [
            PreferenceCleanup.Domain(name: "com.example.app", isByHost: false),
        ])
        #expect(
            PreferenceCleanup.domains(for: [stray, strayByHost, contained, containedByHost], home: home, host: host)
                == [
            PreferenceCleanup.Domain(name: "com.example.app", isByHost: false),
            PreferenceCleanup.Domain(name: "com.example.app", isByHost: true),
        ])
    }

    /// A sandboxed app's settings live in its container, where `defaults` finds its domain. That domain is
    /// exported and forgotten only for the app being reset, and only for the file named after its container.
    @Test func forgetsTheDomainOfASandboxedAppBeingReset() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let own = try directory.file("home/Library/Containers/com.example.app/Data/Library/Preferences/com.example.app.plist")
        let extra = try directory.file("home/Library/Containers/com.example.app/Data/Library/Preferences/com.example.app.extra.plist")
        let foreign = try directory.file("home/Library/Containers/com.other.app/Data/Library/Preferences/com.example.app.plist")

        #expect(PreferenceCleanup.domains(for: [own, extra, foreign], ownedBy: "com.example.app", home: home) == [
            PreferenceCleanup.Domain(name: "com.example.app", isByHost: false),
        ])
        #expect(PreferenceCleanup.domains(for: [own], home: home).isEmpty, "an uninstall has no owner to answer for the container")
        #expect(PreferenceCleanup.domains(for: [own], ownedBy: "com.someone.else", home: home).isEmpty)
    }

    /// A sandboxed app whose identifier has two components owns the settings file in its container just the same.
    @Test func forgetsTheDomainOfASandboxedAppWithATwoPartIdentifier() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let own = try directory.file("home/Library/Containers/md.example/Data/Library/Preferences/md.example.plist")

        #expect(PreferenceCleanup.domains(for: [own], ownedBy: "md.example", home: home) == [
            PreferenceCleanup.Domain(name: "md.example", isByHost: false),
        ])
    }

    /// A container that cannot be read may hold the settings, so the domain is left alone.
    @Test(.permissionsHold) func keepsTheDomainOfAContainerItCannotRead() throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let stray = try directory.file("home/Library/Preferences/com.example.app.plist")
        let preferences = "home/Library/Containers/com.example.app/Data/Library/Preferences"
        try directory.directory(preferences)
        #expect(PreferenceCleanup.domains(for: [stray], home: home).map(\.name) == ["com.example.app"])

        try directory.setPermissions(0o000, of: preferences)
        defer { try? directory.setPermissions(0o755, of: preferences) }
        #expect(PreferenceCleanup.domains(for: [stray], home: home).isEmpty)
    }

    /// A reset of an Apple app must be able to clear that app's own domain, and nothing else Apple owns.
    @Test func forgetsAnAppsOwnAppleDomainOnly() {
        let urls = [
            URL(filePath: "/Users/x/Library/Preferences/com.apple.Notes.plist"),
            URL(filePath: "/Users/x/Library/Preferences/com.apple.Notes.extra.plist"),
            URL(filePath: "/Users/x/Library/Preferences/com.apple.finder.plist"),
        ]

        #expect(PreferenceCleanup.domains(for: urls, home: home).isEmpty)
        #expect(PreferenceCleanup.domains(for: urls, ownedBy: "com.apple.Notes", home: home) == [
            PreferenceCleanup.Domain(name: "com.apple.Notes", isByHost: false),
            PreferenceCleanup.Domain(name: "com.apple.Notes.extra", isByHost: false),
        ])
        #expect(PreferenceCleanup.domains(for: urls, ownedBy: "", home: home).isEmpty)
        #expect(PreferenceCleanup.domains(for: urls, ownedBy: "com.apple").isEmpty)
    }

    @Test func forgetsNoAppleDomainBehindAGroupOrTeamPrefix() {
        let urls = [
            URL(filePath: "/Users/x/Library/Preferences/group.com.apple.notes.plist"),
            URL(filePath: "/Users/x/Library/Preferences/systemgroup.com.apple.example.plist"),
            URL(filePath: "/Users/x/Library/Preferences/ABCDE12345.com.apple.example.plist"),
            URL(filePath: "/Users/x/Library/Preferences/group.org.example.app.plist"),
        ]

        #expect(PreferenceCleanup.domains(for: urls, home: home) == [
            PreferenceCleanup.Domain(name: "group.org.example.app", isByHost: false),
        ])
    }

    @Test func namesBackupFilesSoTheDomainReadsBack() {
        let plain = PreferenceCleanup.Domain(name: "com.example.app", isByHost: false)
        let byHost = PreferenceCleanup.Domain(name: "com.example.app", isByHost: true)

        #expect(PreferenceBackup.fileName(for: plain) == "com.example.app.plist")
        #expect(PreferenceBackup.fileName(for: byHost) == "com.example.app.ByHost.plist")
        #expect(PreferenceBackup.domain(from: PreferenceBackup.fileName(for: plain)) == plain)
        #expect(PreferenceBackup.domain(from: PreferenceBackup.fileName(for: byHost)) == byHost)
        #expect(PreferenceBackup.domain(from: "notes.txt") == nil)
        #expect(PreferenceBackup.domain(from: ".plist") == nil)
    }

    /// `defaults export` writes an empty plist and succeeds for a domain that was never there, so a backup is
    /// only kept when the domain really exists and nothing is left behind when it doesn't.
    @Test func keepsNoBackupWhenThereIsNoDomainToSave() async throws {
        let directory = try TemporaryDirectory()
        let backups = try directory.directory("Backups")
        let app = InstalledApp(url: URL(filePath: "/Applications/Example.app"), bundleIdentifier: "com.example.app", name: "Example")

        // Only a file in the real user's Preferences names a domain, since `save` looks at the real home folder.
        // The stand-in for `defaults read` then says the domain is not there.
        let plist = URL.homeDirectory.appending(path: "Library/Preferences/com.example.app.plist")
        let asked = Mutex<[[String]]>([])
        let notThere: PreferenceBackup.Run = { arguments in
            asked.withLock { $0.append(arguments) }
            return .no
        }

        #expect(
            await PreferenceBackup.save(
                [URL.homeDirectory.appending(path: "Library/Caches/com.example.app")],
                for: app,
                in: backups,
                through: Self.service,
                run: notThere
            ) == .nothingToSave
        )
        #expect(asked.withLock { $0 }.isEmpty, "a folder that names no domain was asked about")
        #expect(
            await PreferenceBackup.save([plist], for: app, in: backups, through: Self.service, run: notThere)
                == .nothingToSave
        )
        #expect(asked.withLock { $0 } == [["read", "com.example.app"]])
        #expect(try FileManager.default.contentsOfDirectory(atPath: backups.path(percentEncoded: false)).isEmpty)
    }

    /// Putting settings back clears each domain first, because `defaults import` merges. A saved copy that is not
    /// a readable property list would put nothing back after the settings in use were cleared, so it is refused
    /// before anything is cleared.
    @Test func aCopyThatCannotBeReadClearsNothing() async throws {
        let directory = try TemporaryDirectory()
        let backups = try directory.directory("Backups")
        let folder = try directory.directory("Backups/com.example.app 2026-09-24 101500")
        let good = try PropertyListSerialization.data(fromPropertyList: ["key": "value"], format: .xml, options: 0)
        try good.write(to: folder.appending(path: "com.example.app.plist"))
        try Data("not a property list".utf8).write(to: folder.appending(path: "com.example.helper.plist"))
        let asked = Mutex<[[String]]>([])
        let run: PreferenceBackup.Run = { arguments in
            asked.withLock { $0.append(arguments) }
            return Self.exporting(arguments)
        }

        let restored = await PreferenceBackup.restore(
            from: folder,
            of: "com.example.app",
            in: backups,
            through: Self.service,
            run: run,
            isOpen: { false }
        )

        #expect(restored == .incomplete(clearedSome: false), "a copy that could not be read was reported as put back, or as cleared")
        let commands = asked.withLock { $0 }
        #expect(commands.contains(["delete", "com.example.app"]))
        #expect(!commands.contains { $0.contains("com.example.helper") }, "the settings in use were cleared for a copy that could not go back")

        // An import that fails after the delete has cleared that domain, and the result says so.
        let failingImport: PreferenceBackup.Run = { arguments in arguments.first == "import" ? .no : Self.exporting(arguments) }
        #expect(
            await PreferenceBackup.restore(
                from: folder,
                of: "com.example.app",
                in: backups,
                through: Self.service,
                run: failingImport,
                isOpen: { false }
            ) == .incomplete(clearedSome: true)
        )
    }

    /// Put Back replaces what the app set since the reset, which may be a license entered again, so those settings
    /// are saved first, as a copy of their own, and only then cleared.
    @Test func puttingBackSavesTheSettingsInUseFirst() async throws {
        let directory = try TemporaryDirectory()
        let backups = try directory.directory("Backups")
        let folder = try directory.directory("Backups/com.example.app 2026-09-24 101500")
        let good = try PropertyListSerialization.data(fromPropertyList: ["key": "value"], format: .xml, options: 0)
        try good.write(to: folder.appending(path: "com.example.app.plist"))
        let asked = Mutex<[[String]]>([])
        let run: PreferenceBackup.Run = { arguments in
            asked.withLock { $0.append(arguments) }
            return Self.exporting(arguments)
        }

        let restored = await PreferenceBackup.restore(
            from: folder,
            of: "com.example.app",
            in: backups,
            through: Self.service,
            run: run,
            isOpen: { false }
        )

        #expect(restored == .complete)
        let copies = PreferenceBackup.copies(in: backups)
        #expect(copies.count == 2, "the settings in use were not kept as a copy of their own")
        let previous = try #require(copies.first { $0.folder != folder })
        #expect(FileManager.default.fileExists(atPath: previous.folder.appending(path: "com.example.app.plist").path(percentEncoded: false)))
        let verbs = asked.withLock { $0 }.map(\.[0])
        #expect(verbs == ["read", "export", "delete", "import"], "cleared before the settings in use were saved")
    }

    /// An app that runs writes its own settings over what is put back, so nothing is cleared or put back while it is
    /// open. It is asked before anything and again once the settings in use are saved, since it can open meanwhile.
    @Test func putsNothingBackWhileTheAppIsOpen() async throws {
        let directory = try TemporaryDirectory()
        let backups = try directory.directory("Backups")
        let folder = try directory.directory("Backups/com.example.app 2026-09-24 101500")
        let good = try PropertyListSerialization.data(fromPropertyList: ["key": "value"], format: .xml, options: 0)
        try good.write(to: folder.appending(path: "com.example.app.plist"))
        let asked = Mutex<[[String]]>([])
        let run: PreferenceBackup.Run = { arguments in
            asked.withLock { $0.append(arguments) }
            return Self.exporting(arguments)
        }

        let open = await PreferenceBackup.restore(
            from: folder,
            of: "com.example.app",
            in: backups,
            through: Self.service,
            run: run,
            isOpen: { true }
        )
        #expect(open == .appIsOpen)
        #expect(asked.withLock { $0 }.isEmpty)

        let checks = Mutex(0)
        let opensMeanwhile = await PreferenceBackup.restore(
            from: folder,
            of: "com.example.app",
            in: backups,
            through: Self.service,
            run: run
        ) {
            checks.withLock { count in
                count += 1
                return count > 1
            }
        }
        #expect(opensMeanwhile == .appIsOpen)
        let commands = asked.withLock { $0 }
        #expect(commands.contains { $0.first == "export" }, "the settings in use were not saved first")
        #expect(!commands.contains { $0.first == "delete" || $0.first == "import" }, "settings were cleared while the app was open")
    }

    /// When the settings in use cannot be saved, nothing is cleared, and the saved copy is not put back.
    @Test func nothingIsClearedWhenTheSettingsInUseCannotBeSaved() async throws {
        let directory = try TemporaryDirectory()
        let backups = try directory.directory("Backups")
        let folder = try directory.directory("Backups/com.example.app 2026-09-24 101500")
        let good = try PropertyListSerialization.data(fromPropertyList: ["key": "value"], format: .xml, options: 0)
        try good.write(to: folder.appending(path: "com.example.app.plist"))
        let asked = Mutex<[[String]]>([])
        let run: PreferenceBackup.Run = { arguments in
            asked.withLock { $0.append(arguments) }
            return arguments.first == "export" ? .no : .yes
        }

        #expect(
            await PreferenceBackup.restore(
                from: folder,
                of: "com.example.app",
                in: backups,
                through: Self.service,
                run: run,
                isOpen: { false }
            ) == .notSaved
        )
        #expect(!asked.withLock { $0 }.contains { $0.first == "delete" || $0.first == "import" })
    }

    /// A stand-in for `defaults` that answers yes, and writes the file an `export` names, as the real one does.
    private static func exporting(_ arguments: [String]) -> PreferenceBackup.Answer {
        if arguments.first == "export", let file = arguments.last {
            FileManager.default.createFile(atPath: file, contents: Data())
        }
        return .yes
    }

    /// The copy is what makes `defaults delete` safe to run, so a copy that could not be made must stop the
    /// reset rather than read as "nothing to save".
    @Test func aCopyThatCouldNotBeMadeIsNotTheSameAsNothingToSave() async throws {
        let directory = try TemporaryDirectory()
        let backups = try directory.directory("Backups")
        let app = InstalledApp(url: URL(filePath: "/Applications/Example.app"), bundleIdentifier: "com.example.app", name: "Example")
        let plist = URL.homeDirectory.appending(path: "Library/Preferences/com.example.app.plist")

        let refused = await PreferenceBackup.save([plist], for: app, in: backups, through: Self.service) { arguments in
            arguments.contains("export") ? .no : .yes
        }
        #expect(refused == .failed)
        #expect(try FileManager.default.contentsOfDirectory(atPath: backups.path(percentEncoded: false)).isEmpty, "an empty copy was left behind")

        let nothing = await PreferenceBackup.save(
            [URL(filePath: "/Users/x/Library/Caches/com.example.app")],
            for: app,
            in: backups,
            through: Self.service
        ) { _ in .yes }
        #expect(nothing == .nothingToSave)
    }

    /// `defaults` that did not start or ran out of time said nothing about the domain, so the copy fails and the
    /// reset moves nothing, rather than reading it as a domain that is not there and clearing it with no copy.
    @Test func aReadThatGetsNoAnswerMakesTheCopyFail() async throws {
        let directory = try TemporaryDirectory()
        let backups = try directory.directory("Backups")
        let app = InstalledApp(url: URL(filePath: "/Applications/Example.app"), bundleIdentifier: "com.example.app", name: "Example")
        let plist = URL.homeDirectory.appending(path: "Library/Preferences/com.example.app.plist")

        let saved = await PreferenceBackup.save([plist], for: app, in: backups, through: Self.service) { arguments in
            arguments.first == "read" ? .noAnswer : .yes
        }

        #expect(saved == .failed)
        #expect(try FileManager.default.contentsOfDirectory(atPath: backups.path(percentEncoded: false)).isEmpty)
    }

    /// Two copies of one app's settings made within a second are both kept: the second gets a number after the
    /// time instead of failing, or being written into the first.
    @Test func twoCopiesMadeInTheSameSecondAreBothKept() async throws {
        let directory = try TemporaryDirectory()
        let backups = try directory.directory("Backups")
        let app = InstalledApp(url: URL(filePath: "/Applications/Example.app"), bundleIdentifier: "com.example.app", name: "Example")
        let plist = URL.homeDirectory.appending(path: "Library/Preferences/com.example.app.plist")
        let exporting: PreferenceBackup.Run = { arguments in
            if arguments.first == "export", let file = arguments.last {
                FileManager.default.createFile(atPath: file, contents: Data())
            }
            return .yes
        }

        let first = await PreferenceBackup.save([plist], for: app, in: backups, through: Self.service, run: exporting)
        let second = await PreferenceBackup.save([plist], for: app, in: backups, through: Self.service, run: exporting)

        guard case .saved(let one) = first, case .saved(let two) = second else {
            Issue.record("a copy was not made: \(first), \(second)")
            return
        }
        #expect(one != two)
        #expect(PreferenceBackup.copies(in: backups).map(\.folder.lastPathComponent).count == 2)
    }

    /// Arc's identifier is `company.thebrowser.Browser` and Obsidian's `md.obsidian`. A copy of their settings is
    /// made, and read back, like any other app's: without it a reset clears nothing.
    @Test func savesTheSettingsOfAnyAppWithAValidIdentifier() async throws {
        let directory = try TemporaryDirectory()
        let backups = try directory.directory("Backups")
        let exporting: PreferenceBackup.Run = { arguments in
            if arguments.first == "export", let file = arguments.last {
                FileManager.default.createFile(atPath: file, contents: Data())
            }
            return .yes
        }
        for identifier in ["company.thebrowser.Browser", "md.obsidian"] {
            let app = InstalledApp(url: URL(filePath: "/Applications/\(identifier).app"), bundleIdentifier: identifier, name: identifier)
            let plist = URL.homeDirectory.appending(path: "Library/Preferences/\(identifier).plist")
            let saved = await PreferenceBackup.save(
                [plist],
                for: app,
                in: backups,
                through: Self.service,
                run: exporting
            )
            guard case .saved = saved else {
                Issue.record("no copy of \(identifier)'s settings: \(saved)")
                continue
            }
        }
        #expect(Set(PreferenceBackup.copies(in: backups).map(\.bundleIdentifier)) == ["company.thebrowser.Browser", "md.obsidian"])
    }

    /// Settings lists the saved copies, newest first, to put back or clear. A copy may hold a license key.
    @Test func listsTheCopiesThatWereSaved() throws {
        let directory = try TemporaryDirectory()
        let backups = try directory.directory("Backups")
        try directory.file("Backups/com.example.app 2026-09-18 101500/com.example.app.plist")
        try directory.file("Backups/com.example.app 2026-09-20 093000/com.example.app.plist")
        try directory.file("Backups/com.example.app 2026-09-20 093000 2/com.example.app.plist")
        try directory.file("Backups/com.other.tool 2026-09-19 120000/com.other.tool.plist")
        try directory.file("Backups/notes.txt")
        try directory.directory("Backups/somebody else's folder")
        try directory.directory("Backups/com.example.app 2026-09-20 093000 x")

        let copies = PreferenceBackup.copies(in: backups)

        #expect(copies.map(\.bundleIdentifier) == ["com.example.app", "com.example.app", "com.other.tool", "com.example.app"])
        #expect(copies.map(\.folder.lastPathComponent).prefix(2) == ["com.example.app 2026-09-20 093000 2", "com.example.app 2026-09-20 093000"])
        #expect(
            copies.first?.date == DateComponents(
                calendar: .current, year: 2026, month: 9, day: 20, hour: 9, minute: 30, second: 0
            ).date
        )
    }

    /// A saved copy can hold a license key or an account, and once the Trash is emptied it may be the only way
    /// back to those settings, so copies stay until the person clears them in Settings: a new one takes none away.
    @Test func savedCopiesStayUntilTheyAreCleared() async throws {
        let directory = try TemporaryDirectory()
        let backups = try directory.directory("home/Library/Application Support/Peel/Preference Backups")
        for index in 0..<22 {
            try directory.directory("home/Library/Application Support/Peel/Preference Backups/com.example.app \(index)")
        }
        let moved = Mutex<[String]>([])
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home"),
                rootDirectory: directory.url.appending(path: "root")
            ),
            moveToTrash: { url in
                moved.withLock { $0.append(url.lastPathComponent) }
                return url
            }
        )
        let app = InstalledApp(url: URL(filePath: "/Applications/Example.app"), bundleIdentifier: "com.example.app", name: "Example")
        let plist = URL.homeDirectory.appending(path: "Library/Preferences/com.example.app.plist")

        let saved = await PreferenceBackup.save([plist], for: app, in: backups, through: service) { arguments in
            if arguments.contains("export"), let file = arguments.last {
                FileManager.default.createFile(atPath: file, contents: Data())
            }
            return .yes
        }

        guard case .saved = saved else { Issue.record("the copy was not made: \(saved)"); return }
        #expect(moved.withLock { $0 }.isEmpty, "a saved copy was taken away")
        #expect(try FileManager.default.contentsOfDirectory(atPath: backups.path(percentEncoded: false)).count == 23)
    }

    @Test func leavesSensitiveFilesOutOfOrphans() {
        #expect(OrphanScanner.isSensitive(fileName: "com.example.app.license"))
        #expect(OrphanScanner.isSensitive(fileName: "Little Snitch Licence"))
        #expect(OrphanScanner.isSensitive(fileName: "Steam"))
        #expect(OrphanScanner.isSensitive(fileName: "steam.plist"))
        #expect(!OrphanScanner.isSensitive(fileName: "com.example.app"))
        #expect(!OrphanScanner.isSensitive(fileName: "Steamer"))
    }
}

struct PrivacyResetTests {
    /// The reset can't be undone, so it is only for an app the move will take: one a program is running from stays,
    /// and keeps its permissions.
    @Test func resetsOnlyAnAppThatIsGoing() throws {
        let directory = try TemporaryDirectory()
        let held = InstalledApp(url: try directory.directory("Applications/Held.app"), bundleIdentifier: "org.example.held", name: "Held")
        let free = InstalledApp(url: try directory.directory("Applications/Free.app"), bundleIdentifier: "org.example.free", name: "Free")
        let process = try directory.runningProgram("Applications/Held.app/Contents/MacOS/held")
        defer { process.terminate() }

        #expect(PrivacyReset.goingNow([held, free], with: service(in: directory)).map(\.bundleIdentifier) == ["org.example.free"])
    }

    private func service(in directory: borrowing TemporaryDirectory) -> TrashService {
        TrashService(environment: SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )) { _ in throw CocoaError(.fileWriteNoPermission) }
    }

    @Test func refusesIdentifiersItShouldNeverTouch() {
        #expect(PrivacyReset.isAllowed(bundleIdentifier: "com.example.app"))
        // Two components name one app as well as three do: Obsidian ships as `md.obsidian`.
        #expect(PrivacyReset.isAllowed(bundleIdentifier: "md.obsidian"))
        for refused in [
            "com.apple.Safari", "COM.APPLE.Safari",
            "com.tuguidragos.Peel", "com.tuguidragos.Peel.Helper", "com.tuguidragos.peel.FinderExtension",
            "", "Signal", "not an identifier", "com.example.app; rm -rf /",
            "-com.example", ".com.example", "com..app", "com.example.", "com.exämple.app",
        ] {
            #expect(!PrivacyReset.isAllowed(bundleIdentifier: refused), "\(refused) was allowed")
        }
    }

    /// `tccutil` is not run here. The output follows its format string, `No such bundle identifier "%s": %s`.
    @Test func saysWhenTheSystemHasNeverHeardOfTheApp() {
        let unknown = "tccutil: No such bundle identifier \"com.example.app\": The operation couldn’t be completed. (OSStatus error -10814.)"
        #expect(PrivacyReset.result(status: 64, output: unknown) == .notKnownToTheSystem)
        #expect(PrivacyReset.result(status: 0, output: "Successfully reset All approval status for com.example.app") == .reset)
        #expect(PrivacyReset.result(status: 1, output: "Failed to reset All") == .failed("Failed to reset All"))
        #expect(PrivacyReset.result(status: 1, output: "") == .failed(""))
    }

    /// Peel's own refusal is reported apart from macOS's answers, and `tccutil` is not run for it.
    @Test func refusesInItsOwnName() async {
        #expect(await PrivacyReset.reset(bundleIdentifier: "com.apple.Safari") == .refused)
        #expect(await PrivacyReset.reset(bundleIdentifier: "") == .refused)
    }

    /// A removal resets only the apps it moves. An app whose leftovers alone are selected stays installed, and
    /// the user did not ask to reset it. The same rule applies to one app and to several.
    @Test func resetsOnlyTheAppsThatAreThemselvesSelected() {
        let editor = InstalledApp(url: URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.editor", name: "Editor")
        let notes = InstalledApp(url: URL(filePath: "/Applications/Notes.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.notes", name: "Notes")
        let safari = InstalledApp(url: URL(filePath: "/Applications/Safari.app", directoryHint: .isDirectory), bundleIdentifier: "com.apple.Safari", name: "Safari")
        let selected: Set<URL> = [editor.url, safari.url, URL(filePath: "/Users/me/Library/Caches/com.example.notes")]

        #expect(PrivacyReset.apps(among: [editor, notes, safari], moving: selected).map(\.bundleIdentifier) == ["com.example.editor"])
    }

    /// Each app of a batch gets one answer, in order, and `tccutil` is never run for an app Peel refuses.
    @Test func answersForEachAppOfABatch() async throws {
        let directory = try TemporaryDirectory()
        let safari = InstalledApp(url: try directory.directory("Applications/Safari.app"), bundleIdentifier: "com.apple.Safari", name: "Safari")
        let signal = InstalledApp(url: try directory.directory("Applications/Signal.app"), bundleIdentifier: "Signal", name: "Signal")

        let resets = await PrivacyReset.reset([safari, signal], beforeMovingWith: service(in: directory))

        #expect(resets.map(\.app.name) == ["Safari", "Signal"])
        #expect(resets.map(\.result) == [.refused, .refused])
    }

    /// A reset that happened is reported only when its app stayed. One that did not happen is always reported.
    @Test func tellsAResetOnlyWhenItMatters() {
        let editor = InstalledApp(url: URL(filePath: "/Applications/Editor.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.editor", name: "Editor")
        let notes = InstalledApp(url: URL(filePath: "/Applications/Notes.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.notes", name: "Notes")
        let viewer = InstalledApp(url: URL(filePath: "/Applications/Viewer.app", directoryHint: .isDirectory), bundleIdentifier: "com.example.viewer", name: "Viewer")
        let removal = TrashResult(
            trashed: [TrashedItem(originalURL: editor.url, trashedURL: URL(filePath: "/Users/me/.Trash/Editor.app"), date: .now)],
            failures: [TrashFailure(url: notes.url, reason: .notPermitted)]
        )

        let told = PrivacyReset.worthTelling(
            [(editor, .reset), (notes, .reset), (viewer, .notKnownToTheSystem)],
            after: removal
        )

        #expect(told.map(\.app.name) == ["Notes", "Viewer"])
    }
}
