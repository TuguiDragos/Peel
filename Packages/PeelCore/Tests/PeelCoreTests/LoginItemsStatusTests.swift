import Foundation
@testable import PeelCore
import Testing

struct LoginItemsStatusTests {
    private func daemon(
        _ state: BackgroundItem.State, disabled: Bool = false, _ status: LoginItemsStatus?
    ) -> BackgroundItem {
        var job = BackgroundItem(
            label: "org.example.helper", kind: .daemon, source: .systemLibrary,
            plistURL: URL(filePath: "/Library/LaunchDaemons/org.example.helper.plist"),
            program: "/Library/Application Support/Example/helper", runsAtLoad: true, keepsAlive: true,
            ownerBundleIdentifier: nil, ownerName: nil, ownerURL: nil, isOrphan: false, state: state,
            isDisabled: disabled
        )
        job.loginItemsStatus = status
        return job
    }

    @Test func aJobSystemSettingsKeepsFromRunningIsOnlyTakenOutOfLaunchd() {
        for status in [LoginItemsStatus.turnedOff, .unknown] {
            #expect(daemon(.notLoaded, status).controls.isEmpty)
            #expect(!daemon(.notLoaded, status).offersControls)
            #expect(!daemon(.notLoaded, status).offersEnableOrDisable)
            #expect(daemon(.running(pid: 42), status).controls == [.stop])
            #expect(!daemon(.running(pid: 42), status).offersEnableOrDisable)
            #expect(daemon(.loaded, status).controls == [.unload])
            #expect(!daemon(.loaded, status).mayBeDisabled)
            #expect(daemon(.notLoaded, disabled: true, status).controls.isEmpty)
            #expect(daemon(.notLoaded, disabled: true, status).offersEnableOrDisable)
        }
        for status in [nil, .allowed, .notListedYet, .notFound] as [LoginItemsStatus?] {
            #expect(daemon(.notLoaded, status).controls == [.load])
            #expect(daemon(.running(pid: 42), status).controls == [.stop, .restart])
            #expect(daemon(.loaded, status).controls == [.runNow, .unload])
            #expect(daemon(.loaded, status).offersEnableOrDisable)
        }
        let disabled = daemon(.notLoaded, disabled: true, .turnedOff)
        #expect(BackgroundItemActions.refusal(toSwitch: daemon(.loaded, .turnedOff), on: false) != nil)
        #expect(BackgroundItemActions.refusal(toSwitch: disabled, on: true) == nil)
    }

    @Test func startAndRestartAskSystemSettingsAtTheMoment() async throws {
        let directory = try TemporaryDirectory()
        // No file is made, so whatever reached launchctl would find nothing to load.
        let read = BackgroundItem(
            label: "org.example.off", kind: .agent, source: .userLibrary,
            plistURL: directory.url.appending(path: "LaunchAgents/org.example.off.plist"), program: nil,
            runsAtLoad: true, keepsAlive: false, ownerBundleIdentifier: nil, ownerName: nil, ownerURL: nil,
            isOrphan: false, state: .notLoaded, isDisabled: false
        )
        #expect(read.controls == [.load])

        await LoginItemsStatus.$standIn.withValue({ _ in .turnedOff }) {
            await #expect(throws: BackgroundItemActions.Failure.turnedOffInSystemSettings) {
                try await BackgroundItemActions.start(read)
            }
            await #expect(throws: BackgroundItemActions.Failure.turnedOffInSystemSettings) {
                try await BackgroundItemActions.restart(read)
            }
        }
        LoginItemsStatus.$standIn.withValue({ _ in .allowed }) {
            #expect(BackgroundItemActions.refusal(toStart: read) == nil)
        }
    }

    @Test func theScanReadsWhatSystemSettingsSaysOfEachJobFile() async throws {
        let directory = try TemporaryDirectory()
        func job(_ label: String) -> Data {
            Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict><key>Label</key><string>\(label)</string></dict></plist>
            """.utf8)
        }
        try directory.file("home/Library/LaunchAgents/org.example.off.plist", contents: job("org.example.off"))
        try directory.file("root/Library/LaunchDaemons/org.example.on.plist", contents: job("org.example.on"))
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )

        let status: @Sendable (URL) -> LoginItemsStatus = {
            $0.lastPathComponent == "org.example.off.plist" ? .turnedOff : .allowed
        }
        let items = await LoginItemsStatus.$standIn.withValue(status) {
            await BackgroundItems.scan(environment: environment).items
        }

        #expect(items.first { $0.label == "org.example.off" }?.loginItemsStatus == .turnedOff)
        #expect(items.first { $0.label == "org.example.on" }?.loginItemsStatus == .allowed)
    }

    @Test func asksSystemSettingsOnlyAboutAFileInTheFoldersItReads() {
        func job(_ source: BackgroundItem.Source, at path: String?) -> BackgroundItem {
            BackgroundItem(
                label: "org.example.agent", kind: .agent, source: source, plistURL: path.map { URL(filePath: $0) },
                program: "/usr/local/bin/agent", runsAtLoad: true, keepsAlive: false, ownerBundleIdentifier: nil,
                ownerName: nil, ownerURL: nil, isOrphan: false, state: .notLoaded, isDisabled: false
            )
        }
        let agents = URL.homeDirectory.appending(path: "Library/LaunchAgents/org.example.agent.plist")

        #expect(LoginItemsStatus.of(job(.userLibrary, at: agents.path(percentEncoded: false))) != nil)
        #expect(LoginItemsStatus.of(job(.otherFile, at: "/Users/Shared/org.example.agent.plist")) == nil)
        #expect(LoginItemsStatus.of(job(.app, at: nil)) == nil)
    }
}
