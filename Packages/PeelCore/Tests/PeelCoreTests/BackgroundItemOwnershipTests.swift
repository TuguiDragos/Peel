import Foundation
@testable import PeelCore
import PeelPrivileged
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

    /// What the helper refuses, the page must not offer: both read the same label.
    @Test func knowsTheJobTheHelperWillNotActOn() {
        func item(_ label: String, _ kind: BackgroundItem.Kind) -> BackgroundItem {
            BackgroundItem(
                label: label, kind: kind, source: .app, plistURL: nil, program: nil, runsAtLoad: false, keepsAlive: false,
                ownerBundleIdentifier: nil, ownerName: nil, isOwnerInstalled: false, isOrphan: false, state: .loaded, isDisabled: false
            )
        }
        let helper = item(HelperIdentity.helperIdentifier, .daemon)
        #expect(helper.isPeelsHelper)
        #expect(!PrivilegedPathPolicy.allowsDaemon(helper.label))
        #expect(!item(HelperIdentity.helperIdentifier, .agent).isPeelsHelper, "an agent never reaches the helper")
        #expect(!item("com.example.helper", .daemon).isPeelsHelper)
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
}
