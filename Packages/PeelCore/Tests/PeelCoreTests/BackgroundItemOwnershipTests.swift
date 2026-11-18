import Foundation
@testable import PeelCore
import PeelPrivileged
import Synchronization
import Testing

struct BackgroundItemOwnershipTests {
    private func app(_ identifier: String, _ name: String, team: String? = nil) -> InstalledApp {
        InstalledApp(url: URL(filePath: "/Applications/\(name).app"), bundleIdentifier: identifier, name: name, teamIdentifier: team)
    }

    /// Who signed each program, given here so that no test depends on what is signed on the Mac it runs on.
    private static let teams = ["/usr/local/bin/example-helper": "ABCDE12345", "/usr/local/bin/impostor": "ZZZZZ99999"]

    private var ownership: BackgroundItemOwnership {
        BackgroundItemOwnership(
            installedApps: [app("com.example.app", "Example", team: "ABCDE12345"), app("com.other.tool", "Tool")],
            teamOfProgram: { Self.teams[$0] }
        )
    }

    @Test func readsAJobsSignatureOnlyWhenItsProgramIsGone() throws {
        final class Reads: Sendable { let programs = Mutex<[String]>([]) }
        let reads = Reads()
        let ownership = BackgroundItemOwnership(installedApps: []) { program in
            reads.programs.withLock { $0.append(program) }
            return nil
        }
        let live = try #require(JobDefinition(["Label": "org.example.live", "Program": "/bin/sh"]))
        let gone = try #require(JobDefinition(["Label": "org.example.gone", "Program": "/opt/org.example/gone"]))

        #expect(!ownership.isOrphan(live))
        #expect(ownership.isOrphan(gone))
        #expect(reads.programs.withLock { $0 } == ["/opt/org.example/gone"])
    }

    @Test func knowsTheAppThatLeftAJobByItsProgramsTeam() throws {
        let directory = try TemporaryDirectory()
        let program = try directory.file("Library/PrivilegedHelperTools/org.example.helper").path(percentEncoded: false)
        func gone(_ identifier: String, _ name: String, team: String = "EXAMPLE123", left: Date) -> RememberedApp {
            var app = RememberedApp(
                bundleIdentifier: identifier, name: name, teamIdentifier: team, lastSeen: left,
                lastPath: directory.url.appending(path: "Applications/\(name).app").path(percentEncoded: false)
            )
            app.goneSince = left
            return app
        }
        let older = gone("org.example.writer", "Writer", left: .now.addingTimeInterval(-86_400))
        let newer = gone("org.example.sheets", "Sheets", left: .now)
        func ownership(
            installed: [InstalledApp] = [], remembered: [RememberedApp]? = nil
        ) -> BackgroundItemOwnership {
            BackgroundItemOwnership(
                installedApps: installed, remembered: remembered ?? [older, newer],
                teamOfProgram: { $0 == program ? "EXAMPLE123" : nil }
            )
        }
        let helper = try #require(JobDefinition(["Label": "org.example.helper", "Program": program]))
        let writers = try #require(JobDefinition(["Label": "org.example.writer.helper", "Program": program]))
        let named = try #require(JobDefinition([
            "Label": "org.example.helper", "Program": program, "AssociatedBundleIdentifiers": ["org.example.writer"],
        ]))
        let missing = try #require(JobDefinition(["Label": "org.example.helper", "Program": program + "-gone"]))
        let apples = try #require(JobDefinition(["Label": "com.apple.example", "Program": program]))
        let trashed = try directory.file(".Trash/Writer.app/Contents/MacOS/helper").path(percentEncoded: false)
        let fromTheTrash = try #require(JobDefinition(["Label": "org.example.helper", "Program": trashed]))

        #expect(ownership().appThatLeft(running: helper) == newer)
        #expect(ownership().appThatLeft(running: writers) == older)
        #expect(ownership().appThatLeft(running: named) == older)
        #expect(ownership(installed: [app("org.example.other", "Other", team: "EXAMPLE123")]).appThatLeft(running: helper) == nil)
        #expect(ownership(installed: [app("org.example.helper", "Helper", team: "ABCDE12345")]).appThatLeft(running: helper) == nil)
        #expect(ownership(remembered: [gone("org.example.writer", "Writer", team: "OTHER12345", left: .now)]).appThatLeft(running: helper) == nil)
        #expect(ownership().appThatLeft(running: missing) == nil)
        #expect(ownership().appThatLeft(running: apples) == nil)
        #expect(ownership().appThatLeft(running: fromTheTrash) == nil)
    }

    @Test func aJobsRowNamesTheAppThatLeftIt() throws {
        let directory = try TemporaryDirectory()
        let program = try directory.file("root/Library/PrivilegedHelperTools/org.example.sync.agent").path(percentEncoded: false)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["Label": "org.example.sync.agent", "ProgramArguments": [program]], format: .xml, options: 0
        )
        try directory.file("root/Library/LaunchAgents/org.example.sync.agent.plist", contents: plist)
        let gone = RememberedApp(
            bundleIdentifier: "org.example.sync", name: "Sync", teamIdentifier: "EXAMPLE123", lastSeen: .now,
            lastPath: directory.url.appending(path: "Applications/Sync.app").path(percentEncoded: false)
        )
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        func row(remembering remembered: [RememberedApp]) -> BackgroundItem? {
            let ownership = BackgroundItemOwnership(
                installedApps: [], remembered: remembered, teamOfProgram: { $0 == program ? "EXAMPLE123" : nil }
            )
            return BackgroundItems.declared(in: environment, ownership: ownership).first
        }

        #expect(row(remembering: [gone])?.appThatLeft == gone)
        #expect(row(remembering: [gone])?.isOrphan == false)
        #expect(row(remembering: [])?.appThatLeft == nil)
    }

    @Test func aJobOfAMakersProductNamesTheMakersStep() throws {
        let directory = try TemporaryDirectory()
        let program = try directory.file("root/Library/Application Support/Example/engine").path(percentEncoded: false)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["Label": "com.crashplan.service", "ProgramArguments": [program]], format: .xml, options: 0
        )
        try directory.file("root/Library/LaunchDaemons/com.crashplan.service.plist", contents: plist)
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        func row(team: String, installed: [InstalledApp] = []) -> BackgroundItem? {
            let ownership = BackgroundItemOwnership(
                installedApps: installed, teamOfProgram: { $0 == program ? team : nil }
            )
            return BackgroundItems.declared(in: environment, ownership: ownership).first
        }
        let crashPlan = app("com.crashplan.desktop", "CrashPlan", team: "UGHXR79U6M")
        let another = app("org.example.other", "Other", team: "UGHXR79U6M")

        #expect(row(team: "UGHXR79U6M")?.makersUninstallerForWhatIsLeft?.maker == "CrashPlan")
        #expect(row(team: "ABCDE12345")?.makersUninstallerForWhatIsLeft == nil)
        let besideItsApp = try #require(row(team: "UGHXR79U6M", installed: [crashPlan, another]))
        #expect(besideItsApp.ownerBundleIdentifier == nil)
        #expect(besideItsApp.makersUninstallerForWhatIsLeft == nil)
        let more = app("org.example.more", "More", team: "UGHXR79U6M")
        #expect(row(team: "UGHXR79U6M", installed: [another, more])?.makersUninstallerForWhatIsLeft != nil)
    }

    @Test func neverCallsGoneAProgramWhosePathHoldsANul() throws {
        let ownership = BackgroundItemOwnership(installedApps: []) { _ in nil }
        let job = try #require(JobDefinition(["Label": "org.example.cut", "Program": "/bin/sh\u{0}gone"]))

        #expect(!ownership.isOrphan(job))
        #expect(!ownership.isOrphan(label: "org.example.cut", program: "/bin/sh\u{0}gone", owner: nil))
    }

    @Test(.permissionsHold) func neverCallsGoneAProgramInAFolderItCannotSearch() throws {
        let directory = try TemporaryDirectory()
        let program = try directory.file("Vendor/bin/agent").path(percentEncoded: false)
        try directory.setPermissions(0, of: "Vendor")
        defer { try? directory.setPermissions(0o755, of: "Vendor") }
        let ownership = BackgroundItemOwnership(installedApps: []) { _ in nil }
        let job = try #require(JobDefinition(["Label": "org.example.agent", "Program": program]))

        #expect(!ownership.isOrphan(job))
        #expect(!ownership.isOrphan(label: "org.example.agent", program: program, owner: nil))
    }

    @Test func neverCallsGoneAProgramOnADiskThatIsNotConnected() throws {
        let program = "/Volumes/org.example.NotConnected-\(UUID().uuidString)/copy.sh"
        let ownership = BackgroundItemOwnership(installedApps: []) { _ in nil }
        let job = try #require(JobDefinition(["Label": "org.example.copy", "Program": program]))

        #expect(!ownership.isOrphan(job))
        #expect(!ownership.isOrphan(label: "org.example.copy", program: program, owner: nil))
    }

    /// What the helper refuses, the page must not offer: both read the same label.
    @Test func knowsTheJobTheHelperWillNotActOn() {
        func item(_ label: String, _ kind: BackgroundItem.Kind) -> BackgroundItem {
            BackgroundItem(
                label: label,
                kind: kind,
                source: .app,
                plistURL: nil,
                program: nil,
                runsAtLoad: false,
                keepsAlive: false,
                ownerBundleIdentifier: nil,
                ownerName: nil,
                ownerURL: nil,
                isOrphan: false,
                state: .loaded,
                isDisabled: false
            )
        }
        let helper = item(HelperIdentity.helperIdentifier, .daemon)
        #expect(helper.isPeelsHelper)
        #expect(!PrivilegedPathPolicy.allowsDaemon(helper.label))
        #expect(!item(HelperIdentity.helperIdentifier, .agent).isPeelsHelper, "an agent never reaches the helper")
        #expect(!item("com.example.helper", .daemon).isPeelsHelper)
        var copy = helper
        copy.anotherFileIsLoaded = true
        #expect(!copy.isPeelsHelper, "a copy of its file beside the one launchd loaded is not the helper")
    }

    @Test func prefersTheBundleTheJobNames() {
        let owner = ownership.owner(
            label: "org.unrelated.label",
            associated: ["com.example.app"],
            program: "/usr/local/bin/example-helper"
        )
        #expect(owner?.bundleIdentifier == "com.example.app")
        #expect(owner?.name == "Example")
        #expect(owner?.isInstalled == true)
    }

    /// `AssociatedBundleIdentifiers` is written by whoever wrote the plist. macOS believes it only when the
    /// program is signed by the team of the app it names, and so does Peel. Otherwise a persistence agent that
    /// names Chrome would be shown as Chrome's, and could never be called orphaned.
    @Test func believesAnAssociationOnlyFromTheSameTeam() {
        let impostor = ownership.owner(label: "org.unrelated.label", associated: ["com.example.app"], program: "/usr/local/bin/impostor")
        #expect(impostor == nil)

        let unsigned = ownership.owner(label: "org.unrelated.label", associated: ["com.example.app"], program: "/usr/local/bin/unsigned")
        #expect(unsigned == nil)

        // The chain goes on past an association it does not believe, and every name in the list is tried.
        let byLabel = ownership.owner(label: "com.other.tool.helper", associated: ["com.example.app"], program: "/usr/local/bin/impostor")
        #expect(byLabel?.bundleIdentifier == "com.other.tool")
        let second = ownership.owner(label: "org.unrelated.label", associated: ["com.nobody.app", "com.example.app"], program: "/usr/local/bin/example-helper")
        #expect(second?.bundleIdentifier == "com.example.app")
    }

    /// What macOS itself says registered a job is not a claim a plist makes, and is believed as it is.
    @Test func believesWhatMacOSSaysRegisteredTheJob() {
        let owner = ownership.owner(label: "org.unrelated.label", registeredBy: "com.other.tool", associated: [], program: nil)
        #expect(owner?.bundleIdentifier == "com.other.tool")
    }

    /// A label, or the bundle a program sits in, is a name anyone can give, so it proves an app's job only when the
    /// program is signed by that app's team or sits inside that very app. Otherwise the owner is a name alone, and
    /// the page says so.
    @Test func saysHowSureItIsOfAnOwner() throws {
        let directory = try TemporaryDirectory()
        let installed = try directory.directory("Applications/Example.app")
        try directory.file("Applications/Example.app/Contents/Info.plist", contents: PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "com.example.app"], format: .xml, options: 0))
        try directory.file("tmp/Fake.app/Contents/Info.plist", contents: PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "com.example.app"], format: .xml, options: 0))
        let ownership = BackgroundItemOwnership(
            installedApps: [InstalledApp(url: installed, bundleIdentifier: "com.example.app", name: "Example", teamIdentifier: "ABCDE12345"), app("com.other.tool", "Tool")],
            teamOfProgram: { Self.teams[$0] }
        )
        func owner(
            _ label: String,
            registeredBy: String? = nil,
            associated: [String] = [],
            program: String?
        ) -> BackgroundItemOwnership.Owner? {
            ownership.owner(label: label, registeredBy: registeredBy, associated: associated, program: program)
        }

        #expect(owner("org.unrelated.label", registeredBy: "com.other.tool", program: nil)?.isConfirmed == true)
        #expect(owner("org.unrelated.label", associated: ["com.example.app"], program: "/usr/local/bin/example-helper")?.isConfirmed == true)
        #expect(owner("com.example.app.updater", program: "/usr/local/bin/example-helper")?.isConfirmed == true)
        let sameMaker = try #require(owner("org.unrelated.label", program: "/usr/local/bin/example-helper"))
        #expect(sameMaker.bundleIdentifier == "com.example.app")
        #expect(sameMaker.isOnlyItsMaker)
        #expect(owner("com.example.app.updater", program: "/usr/local/bin/example-helper")?.isOnlyItsMaker == false)
        #expect(owner("org.unrelated.label", associated: ["com.example.app"], program: "/usr/local/bin/example-helper")?.isOnlyItsMaker == false)
        #expect(owner("org.unrelated.label", program: installed.appending(path: "Contents/MacOS/helper").path(percentEncoded: false))?.isConfirmed == true)

        let impostor = try #require(owner("com.example.app.updater", program: "/usr/local/bin/impostor"))
        #expect(impostor.bundleIdentifier == "com.example.app")
        #expect(!impostor.isConfirmed)
        #expect(owner("com.other.tool.helper", program: nil)?.isConfirmed == false)
        let planted = try #require(owner("org.unrelated.label", program: directory.url.appending(path: "tmp/Fake.app/Contents/MacOS/x").path(percentEncoded: false)))
        #expect(planted.bundleIdentifier == "com.example.app")
        #expect(!planted.isConfirmed)
    }

    @Test func ownsAJobByTheBundleItsProgramSitsIn() throws {
        let directory = try TemporaryDirectory()
        for folder in ["Vendor", ".Trash"] {
            try directory.file("\(folder)/Updater.app/Contents/Info.plist", contents: PropertyListSerialization.data(
                fromPropertyList: ["CFBundleIdentifier": "org.example.updater"], format: .xml, options: 0))
        }
        let bundle = directory.url.appending(path: "Vendor/Updater.app").path(percentEncoded: false)
        let program = bundle + "/Contents/MacOS/Updater"
        func owner(_ teams: [String: String], program: String = program) -> BackgroundItemOwnership.Owner? {
            BackgroundItemOwnership(installedApps: [], teamOfProgram: { teams[$0] })
                .owner(label: "org.example.updater.agent", associated: [], program: program)
        }

        let signed = try #require(owner([program: "ABCDE12345", bundle: "ABCDE12345"]))
        #expect(signed.bundleIdentifier == "org.example.updater")
        #expect(signed.name == "Updater")
        #expect(signed.url == URL(filePath: bundle, directoryHint: .isDirectory))
        #expect(signed.isConfirmed)

        let unsigned = try #require(owner([:]))
        #expect(unsigned.url == URL(filePath: bundle, directoryHint: .isDirectory))
        #expect(!unsigned.isConfirmed, "a bundle anyone can make proves nothing")
        #expect(owner([program: "ABCDE12345", bundle: "ZZZZZ99999"])?.isConfirmed == false)
        #expect(owner([program: "ABCDE12345"])?.isConfirmed == false)

        let trashed = directory.url.appending(path: ".Trash/Updater.app/Contents/MacOS/Updater").path(percentEncoded: false)
        #expect(owner([:], program: trashed)?.url == nil, "a copy in a Trash isn't installed")
    }

    @Test func knowsWhereTheOwnerIs() {
        #expect(ownership.owner(label: "com.other.tool.helper", associated: [], program: nil)?.url == URL(filePath: "/Applications/Tool.app"))
        let associated = ownership.owner(label: "org.unrelated.label", associated: ["com.example.app"], program: "/usr/local/bin/example-helper")
        #expect(associated?.url == URL(filePath: "/Applications/Example.app"))
        let elsewhere = ownership.owner(label: "org.unrelated.label", registeredBy: "com.apple.CharacterPaletteIM", associated: [], program: nil)
        #expect(elsewhere?.url?.lastPathComponent == "CharacterPalette.app")
        #expect(elsewhere?.isInstalled == true)
        #expect(ownership.owner(label: "com.missing.app.agent", registeredBy: "com.missing.app", associated: [], program: nil)?.url == nil)
    }

    @Test func fallsBackToTheLabelWhenNothingElseMatches() {
        let owner = ownership.owner(label: "com.other.tool.helper", associated: [], program: nil)
        #expect(owner?.bundleIdentifier == "com.other.tool")
        #expect(owner?.isInstalled == true)
    }

    @Test func reportsAnOwnerThatIsGone() {
        let owner = ownership.owner(label: "com.missing.app.agent", registeredBy: "com.missing.app", associated: [], program: nil)
        #expect(owner?.bundleIdentifier == "com.missing.app")
        #expect(owner?.name == nil)
        #expect(owner?.isInstalled == false)

        // An app the plist names that is gone is still named. It is not installed, so the job can still be called
        // orphaned.
        let named = ownership.owner(label: "org.unrelated.label", associated: ["com.missing.app"], program: nil)
        #expect(named?.bundleIdentifier == "com.missing.app")
        #expect(named?.isInstalled == false)
    }

    @Test func callsItOrphanedOnlyWhenNothingIsLeft() throws {
        let directory = try TemporaryDirectory()
        let program = try directory.file("bin/tool").path(percentEncoded: false)
        let installed = ownership.owner(label: "com.example.app.updater", associated: [], program: nil)
        let missing = ownership.owner(label: "com.missing.app.agent", registeredBy: "com.missing.app", associated: [], program: nil)

        #expect(!ownership.isOrphan(label: "com.example.app.updater", program: program, owner: installed))
        #expect(!ownership.isOrphan(label: "com.missing.app.agent", program: program, owner: missing))
        #expect(ownership.isOrphan(label: "com.missing.app.agent", program: "/nowhere/gone", owner: missing))
        #expect(ownership.isOrphan(label: "com.missing.app.agent", program: nil, owner: nil))
        #expect(!ownership.isOrphan(label: "com.apple.something", program: "/nowhere/gone", owner: nil))
        // A job that names no program of its own is orphaned once the app it belongs to is gone, just as when
        // nothing claims it at all.
        #expect(ownership.isOrphan(label: "com.missing.app.agent", program: nil, owner: missing))
        #expect(!ownership.isOrphan(label: "com.example.app.updater", program: nil, owner: installed))
    }

    /// `man launchd.plist`: without `Program`, the first of `ProgramArguments` "may be either an absolute path,
    /// or a relative path which is resolved using _PATH_STDPATH". So a hand-written agent that runs `sh` every
    /// night still has a program, and is not orphaned.
    @Test func findsAProgramLaunchdLooksUpByName() {
        #expect(!ownership.isOrphan(label: "local.nightly", program: "sh", owner: nil))
        #expect(!ownership.isOrphan(label: "local.nightly", program: "osascript", owner: nil))
        #expect(ownership.isOrphan(label: "local.nightly", program: "no-such-tool-anywhere", owner: nil))

        let job = JobDefinition(["Label": "local.nightly", "ProgramArguments": ["sh", "-c", 1]])
        #expect(job?.program == "sh", "one argument that is not text cost the whole list")
        #expect(JobDefinition(["Label": "x", "AssociatedBundleIdentifiers": ["a.b.c", "d.e.f"]])?.associated == ["a.b.c", "d.e.f"])
        #expect(JobDefinition(["Label": "x", "AssociatedBundleIdentifiers": "a.b.c"])?.associated == ["a.b.c"])
    }

    @Test func readsEveryShapeOfJobPlist() {
        let withProgram = JobDefinition(["Label": "com.example.a", "Program": "/Applications/Example.app/Contents/MacOS/Helper", "RunAtLoad": true])
        #expect(withProgram?.program == "/Applications/Example.app/Contents/MacOS/Helper")
        #expect(withProgram?.runsAtLoad == true)

        let withArguments = JobDefinition(["Label": "com.example.b", "ProgramArguments": ["/usr/local/bin/tool", "--daemon"]])
        #expect(withArguments?.program == "/usr/local/bin/tool")

        // `man launchd.plist`: BundleProgram is "an app-bundle relative path", so it names no program here.
        #expect(JobDefinition(["Label": "com.example.c", "BundleProgram": "Contents/MacOS/Helper"])?.program == nil)

        let withAssociations = JobDefinition(["Label": "com.example.d", "AssociatedBundleIdentifiers": ["com.example.app", "com.example.other"]])
        #expect(withAssociations?.associated.first == "com.example.app")

        let keepAliveDictionary = JobDefinition(["Label": "com.example.e", "KeepAlive": ["SuccessfulExit": false]])
        #expect(keepAliveDictionary?.keepsAlive == true)
        #expect(keepAliveDictionary?.runsAtLoad == true, "launchd starts a job it keeps alive as soon as it is loaded")

        #expect(JobDefinition(["Program": "/usr/local/bin/tool"]) == nil)
    }

    @Test func readsAProgramsTeamOnceWhileTheFileStaysTheSame() throws {
        let directory = try TemporaryDirectory()
        let program = try directory.file("agent", bytes: 16).path(percentEncoded: false)
        let reads = Mutex(0)
        let teams = BackgroundItemOwnership.ProgramTeams { _ in
            reads.withLock { $0 += 1 }
            return "ORGEXAMPLE"
        }

        let first = teams.team(of: program)
        let second = teams.team(of: program)
        let readsOfTheSameFile = reads.withLock { $0 }
        try Data(count: 32).write(to: URL(filePath: program))
        let third = teams.team(of: program)
        let readsOnceWritten = reads.withLock { $0 }

        #expect([first, second, third] == ["ORGEXAMPLE", "ORGEXAMPLE", "ORGEXAMPLE"])
        #expect(readsOfTheSameFile == 1)
        #expect(readsOnceWritten == 2)
    }

    @Test func readsTheTeamOfAProgramItCanNotIdentifyEveryTime() {
        let reads = Mutex(0)
        let teams = BackgroundItemOwnership.ProgramTeams { _ in
            reads.withLock { $0 += 1 }
            return nil
        }

        _ = teams.team(of: "/org.example/gone")
        _ = teams.team(of: "/org.example/gone")

        let timesRead = reads.withLock { $0 }
        #expect(timesRead == 2)
    }
}
