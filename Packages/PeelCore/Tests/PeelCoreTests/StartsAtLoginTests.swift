import Foundation
@testable import PeelCore
import Testing

struct StartsAtLoginTests {
    /// `launchctl print gui/<uid>/<label>` of a login item an app registered, as macOS 27 writes it, names made up.
    private static let registeredLoginItem = """
        gui/501/org.example.tide.helper = {
        \tactive count = 3
        \tpath = (submitted by smd.341)
        \ttype = Submitted
        \tmanaged_by = com.apple.xpc.ServiceManagement
        \tstate = running

        \tprogram identifier = org.example.tide.helper (mode: 1)
        \tparent bundle identifier = org.example.tide
        \tparent bundle version = 1
        \tBTM uuid = BDB2A4AF-9245-448E-B8A7-EBF0A6967323
        \tinherited environment = {
        \t\tSSH_AUTH_SOCK => /var/run/com.apple.launchd.8xrz08QAWw/Listeners
        \t}
        }
        """

    private static let agentFromAFile = """
        gui/501/org.example.tide.agent = {
        \tactive count = 0
        \tpath = /Users/someone/Library/LaunchAgents/org.example.tide.agent.plist
        \ttype = LaunchAgent
        \tstate = not running

        \tprogram = /Applications/Tide.app/Contents/MacOS/agent
        }
        """

    private func plist(_ values: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
    }

    private func app(in directory: borrowing TemporaryDirectory, identifier: String = "org.example.tide") throws -> URL {
        let app = try directory.directory("home/Applications/Tide.app")
        _ = try directory.file("home/Applications/Tide.app/Contents/Info.plist", contents: plist(["CFBundleIdentifier": identifier]))
        _ = try directory.file(
            "home/Applications/Tide.app/Contents/Library/LoginItems/TideHelper.app/Contents/Info.plist",
            contents: plist(["CFBundleIdentifier": "org.example.tide.helper"])
        )
        _ = try directory.file("home/Applications/Tide.app/Contents/Library/LoginItems/ReadMe.txt", contents: Data())
        _ = try directory.file(
            "home/Applications/Tide.app/Contents/Library/LoginItems/Other.bundle/Contents/Info.plist",
            contents: plist(["CFBundleIdentifier": "org.example.tide.other"])
        )
        let agents = "home/Applications/Tide.app/Contents/Library/LaunchAgents"
        _ = try directory.file("\(agents)/org.example.tide.agent.plist", contents: plist(["Label": "org.example.tide.agent"]))
        _ = try directory.file("\(agents)/apples.plist", contents: plist(["Label": "com.apple.example"]))
        _ = try directory.file("\(agents)/odd.plist", contents: plist(["Label": "../system/org.example.odd"]))
        _ = try directory.file("\(agents)/org.example.tide.backup", contents: plist(["Label": "org.example.tide.backup"]))
        _ = try directory.file("\(agents)/same.plist", contents: plist(["Label": "org.example.tide.helper"]))
        _ = try directory.file(
            "home/Applications/Tide.app/Contents/Library/LaunchDaemons/org.example.tide.daemon.plist",
            contents: plist(["Label": "org.example.tide.daemon"])
        )
        return app
    }

    @Test func labelsAreEachLoginItemsIdentifierAndEachAgentsLabel() throws {
        let directory = try TemporaryDirectory()
        let app = try app(in: directory)

        #expect(StartsAtLogin.labels(declaredBy: app) == ["org.example.tide.helper", "org.example.tide.agent"])
    }

    @Test func asksAboutAtMostSoManyLabels() throws {
        let directory = try TemporaryDirectory()
        let app = try app(in: directory)
        for index in 0..<StartsAtLogin.mostAsked {
            let label = "org.example.tide.extra\(index)"
            _ = try directory.file(
                "home/Applications/Tide.app/Contents/Library/LaunchAgents/\(label).plist",
                contents: plist(["Label": label])
            )
        }

        let labels = StartsAtLogin.labels(declaredBy: app)
        #expect(labels.count == StartsAtLogin.mostAsked)
        #expect(labels.first == "org.example.tide.helper")
    }

    @Test func aJobIsTheAppsWhenServiceManagementManagesItForThatApp() {
        let registered = Launchctl.answer(status: 0, output: Self.registeredLoginItem)
        let unmanaged = Launchctl.answer(
            status: 0,
            output: Self.registeredLoginItem.replacingOccurrences(of: "\tmanaged_by = com.apple.xpc.ServiceManagement\n", with: "")
        )
        let fromAFile = Launchctl.answer(status: 0, output: Self.agentFromAFile)
        let gone = Launchctl.answer(status: 113, output: "Bad request.\nCould not find service")

        #expect(StartsAtLogin.isRegistered(registered, for: "org.example.tide"))
        #expect(StartsAtLogin.isRegistered(registered, for: "ORG.EXAMPLE.TIDE"))
        #expect(!StartsAtLogin.isRegistered(registered, for: "org.example.other"))
        #expect(!StartsAtLogin.isRegistered(unmanaged, for: "org.example.tide"))
        #expect(!StartsAtLogin.isRegistered(fromAFile, for: "org.example.tide"))
        #expect(!StartsAtLogin.isRegistered(gone, for: "org.example.tide"))
    }

    @Test func launchdHoldsNothingForAnAppThatRegisteredNothing() async throws {
        let directory = try TemporaryDirectory()
        let app = try app(in: directory)

        #expect(await StartsAtLogin.registration(of: app) == nil)
    }

    /// Records where each app was when its registration was asked about.
    private actor Asked {
        private(set) var whileInPlace: [Bool] = []

        func record(_ app: URL) {
            whileInPlace.append(FileManager.default.fileExists(atPath: app.path(percentEncoded: false)))
        }
    }

    private func service(
        in directory: borrowing TemporaryDirectory,
        stuck: URL? = nil,
        asked: Asked = Asked(),
        registration: StartsAtLogin.Registration?
    ) throws -> TrashService {
        let trash = try directory.directory("home/.Trash")
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        return TrashService(
            environment: environment,
            registrationAtLogin: { app in
                await asked.record(app)
                return registration
            }
        ) { url in
            guard url != stuck else { throw CocoaError(.fileWriteNoPermission) }
            let destination = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    @Test func notesAnAppThatMovedWithItsBackgroundItemsRegisteredAskedBeforeItMoved() async throws {
        let directory = try TemporaryDirectory()
        let app = try app(in: directory)
        let asked = Asked()
        let registration = StartsAtLogin.Registration(identifier: "org.example.tide", labels: ["org.example.tide.helper"])
        let service = try service(in: directory, asked: asked, registration: registration)

        let result = await service.trash(
            apps: [app], thenFiles: { _ in [] }, usingHelperFor: [], lettingTheirProgramsRun: []
        )

        #expect(result.trashed.map(\.originalURL) == [app])
        #expect(result.startsFromTheTrash == [app])
        #expect(await asked.whileInPlace == [true])
    }

    @Test func notesNoAppThatStayed() async throws {
        let directory = try TemporaryDirectory()
        let app = try app(in: directory)
        let registration = StartsAtLogin.Registration(identifier: "org.example.tide", labels: ["org.example.tide.helper"])
        let service = try service(in: directory, stuck: app, registration: registration)

        let result = await service.trash(
            apps: [app], thenFiles: { _ in [] }, usingHelperFor: [], lettingTheirProgramsRun: []
        )

        #expect(result.failures.map(\.url) == [app])
        #expect(result.startsFromTheTrash.isEmpty)
    }

    @Test func notesNoAppWithNothingRegistered() async throws {
        let directory = try TemporaryDirectory()
        let app = try app(in: directory)
        let service = try service(in: directory, registration: nil)

        let result = await service.trash(
            apps: [app], thenFiles: { _ in [] }, usingHelperFor: [], lettingTheirProgramsRun: []
        )

        #expect(result.trashed.map(\.originalURL) == [app])
        #expect(result.startsFromTheTrash.isEmpty)
    }

    @Test func notesEachAppOfSeveralThatMovedWithItsItemsRegistered() async throws {
        let directory = try TemporaryDirectory()
        let trash = try directory.directory("home/.Trash")
        var apps: [URL] = []
        for name in ["Tide", "Ebb", "Moor"] {
            let app = try directory.directory("home/Applications/\(name).app")
            _ = try directory.file(
                "home/Applications/\(name).app/Contents/Info.plist",
                contents: plist(["CFBundleIdentifier": "org.example.\(name.lowercased())"])
            )
            apps.append(app)
        }
        let (tide, ebb, moor) = (apps[0], apps[1], apps[2])
        let service = TrashService(
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            ),
            registrationAtLogin: { app in
                guard app != ebb else { return nil }
                let name = app.deletingPathExtension().lastPathComponent.lowercased()
                return StartsAtLogin.Registration(identifier: "org.example.\(name)", labels: ["org.example.\(name).helper"])
            }
        ) { url in
            guard url != moor else { throw CocoaError(.fileWriteNoPermission) }
            let destination = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }

        let result = await service.trash(
            apps: apps, thenFiles: { _ in [] }, usingHelperFor: [], lettingTheirProgramsRun: []
        )

        #expect(Set(result.trashed.map(\.originalURL)) == [tide, ebb])
        #expect(result.failures.map(\.url) == [moor])
        #expect(result.startsFromTheTrash == [tide])
    }

    /// Calculator is on every Mac, so an app that shares its identifier has another copy installed, which macOS may
    /// start the items from instead.
    @Test func notesNoAppWhoseIdentifierAnotherInstalledAppHas() async throws {
        let directory = try TemporaryDirectory()
        let app = try app(in: directory, identifier: "com.apple.calculator")
        let registration = StartsAtLogin.Registration(identifier: "com.apple.calculator", labels: ["org.example.tide.helper"])
        let service = try service(in: directory, registration: registration)

        let result = await service.trash(
            apps: [app], thenFiles: { _ in [] }, usingHelperFor: [], lettingTheirProgramsRun: []
        )

        #expect(result.trashed.map(\.originalURL) == [app])
        #expect(result.startsFromTheTrash.isEmpty)
    }
}
