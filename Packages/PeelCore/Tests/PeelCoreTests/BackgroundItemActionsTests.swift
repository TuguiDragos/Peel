import Foundation
@testable import PeelCore
import Synchronization
import PeelPrivileged
import Testing

struct BackgroundItemActionsTests {
    private func item(state: BackgroundItem.State, plist: URL?) -> BackgroundItem {
        BackgroundItem(
            label: "com.example.agent", kind: .agent, source: .userLibrary, plistURL: plist, program: nil,
            runsAtLoad: false, keepsAlive: false, ownerBundleIdentifier: nil, ownerName: nil,
            isOwnerInstalled: false, isOrphan: false, state: state, isDisabled: false
        )
    }

    /// On macOS 27 a job whose file carries a download's quarantine mark cannot be loaded. A job launchd already
    /// holds is still woken, marked or not.
    @Test func theMarkOfADownloadStopsALoadAndNothingElse() {
        let plist = URL(filePath: "/Users/x/Library/LaunchAgents/com.example.agent.plist")
        let marked = { (_: URL) in true }

        #expect(BackgroundItemActions.plan(toStart: item(state: .notLoaded, plist: plist), isRefusedByLaunchd: marked) == .blockedByQuarantine)
        #expect(BackgroundItemActions.plan(toStart: item(state: .loaded, plist: plist), isRefusedByLaunchd: marked) == .kickstart)
        #expect(BackgroundItemActions.plan(toStart: item(state: .running(pid: 42), plist: plist), isRefusedByLaunchd: marked) == .kickstart)
        #expect(BackgroundItemActions.plan(toStart: item(state: .notLoaded, plist: plist), isRefusedByLaunchd: { _ in false }) == .bootstrap(plist))
        // Nothing to load from: an app submitted this one, and launchctl is asked for it by name.
        #expect(BackgroundItemActions.plan(toStart: item(state: .notLoaded, plist: nil), isRefusedByLaunchd: marked) == .kickstart)
    }

    /// Starting, stopping and switching a job go by its label, so a label macOS itself uses would reach macOS's own
    /// job. The helper refuses one for a daemon; the same refusal holds for an agent, which `launchctl` runs
    /// without the helper. `com.openssh.ssh-agent` is an agent macOS ships whose label says nothing about Apple.
    @Test func neverActsOnALabelMacOSUses() {
        func agent(_ label: String) -> BackgroundItem {
            BackgroundItem(
                label: label, kind: .agent, source: .userLibrary, plistURL: nil, program: nil,
                runsAtLoad: false, keepsAlive: false, ownerBundleIdentifier: nil, ownerName: nil,
                isOwnerInstalled: false, isOrphan: false, state: .loaded, isDisabled: false
            )
        }
        let refused = BackgroundItemActions.Failure.launchctl(HelperRefusal.invalidRequest.rawValue)

        #expect(BackgroundItemActions.refusal(for: agent("com.apple.Finder.helper")) == refused)
        #expect(BackgroundItemActions.refusal(for: agent("com.openssh.ssh-agent")) == refused)
        #expect(BackgroundItemActions.refusal(for: agent("com.example.agent")) == nil)
    }

    private func item(_ source: BackgroundItem.Source, state: BackgroundItem.State, plist: URL?) -> BackgroundItem {
        BackgroundItem(
            label: "com.example.agent", kind: source == .systemLibrary ? .daemon : .agent, source: source,
            plistURL: plist, program: nil, runsAtLoad: false, keepsAlive: false, ownerBundleIdentifier: nil,
            ownerName: nil, isOwnerInstalled: false, isOrphan: false, state: state, isDisabled: false
        )
    }

    /// A job stopped before a move that is then refused would be left stopped with its file in place.
    @Test func movesTheFileFirstAndStopsTheJobOnlyOnceItHasGone() async throws {
        let plist = URL(filePath: "/Users/x/Library/LaunchAgents/com.example.agent.plist")
        let steps = Mutex<[String]>([])
        func service(refusing: Bool) -> TrashService {
            TrashService(environment: SearchEnvironment(homeDirectory: URL(filePath: "/Users/x"), rootDirectory: URL(filePath: "/"))) { url in
                steps.withLock { $0.append("move") }
                if refusing { throw TrashService.RefusedOnceHeld() }
                return url
            }
        }
        let stop: (BackgroundItem) async -> Void = { _ in steps.withLock { $0.append("stop") } }

        let result = try await BackgroundItemActions.moveToTrash(
            item(.userLibrary, state: .running(pid: 7), plist: plist), isHelperEnabled: false, trash: service(refusing: false), stop: stop
        )
        #expect(result.trashed.count == 1)
        #expect(steps.withLock { $0 } == ["move", "stop"])

        // Refused: nothing is stopped, and the reason is the one the guard gave.
        steps.withLock { $0 = [] }
        await #expect(throws: BackgroundItemActions.Failure.trash(.protectedLocation)) {
            try await BackgroundItemActions.moveToTrash(
                item(.userLibrary, state: .running(pid: 7), plist: plist), isHelperEnabled: false, trash: service(refusing: true), stop: stop
            )
        }
        #expect(steps.withLock { $0 } == ["move"])

        // A job launchd does not hold has nothing to stop.
        steps.withLock { $0 = [] }
        _ = try await BackgroundItemActions.moveToTrash(
            item(.userLibrary, state: .notLoaded, plist: plist), isHelperEnabled: false, trash: service(refusing: false), stop: stop
        )
        #expect(steps.withLock { $0 } == ["move"])
    }

    /// The helper moves what is in `/Library`, so without it nothing is touched and nothing is stopped.
    @Test func movesNothingFromTheSystemLibraryWithoutTheHelper() async {
        let plist = URL(filePath: "/Library/LaunchDaemons/com.example.agent.plist")
        let touched = Mutex(false)
        let trash = TrashService(environment: SearchEnvironment(homeDirectory: URL(filePath: "/Users/x"), rootDirectory: URL(filePath: "/"))) { url in
            touched.withLock { $0 = true }
            return url
        }

        await #expect(throws: BackgroundItemActions.Failure.requiresPrivileges) {
            try await BackgroundItemActions.moveToTrash(
                item(.systemLibrary, state: .running(pid: 7), plist: plist), isHelperEnabled: false, trash: trash, stop: { _ in }
            )
        }
        await #expect(throws: BackgroundItemActions.Failure.noFileToMove) {
            try await BackgroundItemActions.moveToTrash(
                item(.app, state: .running(pid: 7), plist: nil), isHelperEnabled: true, trash: trash, stop: { _ in }
            )
        }
        #expect(!touched.withLock { $0 })
    }
}

/// The jobs declared in the three folders launchd reads, read without asking `launchctl`.
struct DeclaredBackgroundItemsTests {
    private func job(_ label: String, program: String? = nil, disabled: Bool = false) throws -> Data {
        var plist: [String: Any] = ["Label": label, "Disabled": disabled]
        if let program { plist["ProgramArguments"] = [program] }
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    private func environment(_ directory: borrowing TemporaryDirectory) -> SearchEnvironment {
        SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
    }

    @Test func readsTheJobEachFileDeclaresAndLeavesApplesOwnToMacOS() throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/LaunchAgents/updater.plist", contents: job("com.example.agent", program: "/bin/sh"))
        try directory.file("root/Library/LaunchDaemons/com.example.helper.plist", contents: job("com.example.helper"))
        // A label nobody but Apple should use, on a file macOS did not install: shown, and nothing acts on it.
        try directory.file("root/Library/LaunchDaemons/apple.plist", contents: job("com.apple.madeup.peeltest"))
        // A label macOS itself declares is left out.
        let shipped = try #require(SystemDaemons.shipped.first { $0.hasPrefix("com.apple.") })
        try directory.file("root/Library/LaunchDaemons/shipped.plist", contents: job(shipped))
        // So is a label one of macOS's own agents declares, whatever it says.
        try directory.file("home/Library/LaunchAgents/ssh.plist", contents: job("com.openssh.ssh-agent"))
        try directory.file("home/Library/LaunchAgents/unnamed.plist", contents: Data())
        try directory.file("home/Library/LaunchAgents/notes.txt")

        let items = BackgroundItems.declared(in: environment(directory), ownership: BackgroundItemOwnership(installedApps: []))

        #expect(items.map(\.label).sorted() == ["com.apple.madeup.peeltest", "com.example.agent", "com.example.helper"])
        let impostor = try #require(items.first { $0.declaresAnAppleLabel })
        #expect(!impostor.canMoveToTrash)
        #expect(items.first { $0.label == "com.example.agent" }?.canMoveToTrash == true)
    }

    /// One label declared in two folders is two files, and each row opens its own.
    @Test func keepsTwoFilesThatDeclareOneLabelApart() throws {
        let directory = try TemporaryDirectory()
        for folder in ["home/Library/LaunchAgents", "root/Library/LaunchAgents"] {
            try directory.file("\(folder)/com.example.agent.plist", contents: job("com.example.agent"))
        }

        let items = BackgroundItems.declared(in: environment(directory), ownership: BackgroundItemOwnership(installedApps: []))

        #expect(items.count == 2)
        #expect(Set(items.map(\.id)).count == 2)
        #expect(items.map(\.source) == [.userLibrary, .systemLibrary])
    }

    @Test func leavesOutWhatTheUserExcluded() throws {
        let directory = try TemporaryDirectory()
        let excluded = try directory.file("home/Library/LaunchAgents/com.example.agent.plist", contents: job("com.example.agent"))
        try directory.file("home/Library/LaunchAgents/com.example.other.plist", contents: job("com.example.other"))

        let items = BackgroundItems.declared(
            in: environment(directory),
            ownership: BackgroundItemOwnership(installedApps: []),
            exclusions: Exclusions(paths: [excluded])
        )

        #expect(items.map(\.label) == ["com.example.other"])
    }

    /// `launchctl` reports jobs by label, so the state comes from the label inside the file, not from its name.
    @Test func takesTheStateFromTheLabelInsideTheFile() throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/LaunchAgents/named-after-something-else.plist", contents: job("com.example.agent"))
        let loaded = BackgroundItems.Loaded(user: ["com.example.agent": 91], userDisabled: ["com.example.agent": true])

        let items = BackgroundItems.declared(in: environment(directory), ownership: BackgroundItemOwnership(installedApps: []), loaded: loaded)

        #expect(items.first?.state == .running(pid: 91))
        #expect(items.first?.isDisabled == true)
    }

    /// A loaded job is asked about as one an app submitted only when no file in the three folders declares it, so
    /// a job with a file is never asked about again, nor listed a second time. Apple's own are never asked about.
    @Test func asksOnlyAboutLoadedJobsNoFileDeclares() throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/LaunchAgents/updater.plist", contents: job("com.example.agent"))
        let loaded = BackgroundItems.Loaded(user: ["com.example.agent": 91, "com.example.submitted": nil, "com.apple.Finder": 1])
        let items = BackgroundItems.declared(in: environment(directory), ownership: BackgroundItemOwnership(installedApps: []), loaded: loaded)

        let undeclared = BackgroundItems.undeclared(in: loaded, declared: items, userDomain: "gui/501")

        #expect(undeclared.map(\.label) == ["com.example.submitted"])
        #expect(undeclared.first?.target == "gui/501/com.example.submitted")
    }
}
