import Foundation
@testable import PeelCommandLine
@testable import PeelCore
import Testing

struct ManagedAgentTests {
    private func app(_ identifier: String, team: String?) -> InstalledApp {
        InstalledApp(
            url: URL(filePath: "/Applications/Agent.app", directoryHint: .isDirectory), bundleIdentifier: identifier,
            name: "Agent", teamIdentifier: team, isSealIntact: true
        )
    }

    @Test func knowsAnAgentAnOrganizationManagesTheMacWith() {
        #expect(ManagedAgent.of(team: "X9E956P446", identifier: "com.crowdstrike.falcon.Agent")?.name == "CrowdStrike Falcon")
        #expect(ManagedAgent.of(team: "4AYE5J54KN", identifier: "com.sentinelone.sentineld")?.name == "SentinelOne")
        #expect(ManagedAgent.of(team: "483DWKW443", identifier: "com.jamf.protect.agent")?.page != nil)
        #expect(ManagedAgent.of(team: "2BT3HPN62Z", identifier: "co.elastic.systemextension")?.name == "Elastic Agent")
        #expect(ManagedAgent.of(team: "7AGZNQ2S2T", identifier: "com.carbonblack.defense.kext")?.page == nil)
        #expect(ManagedAgent.of(team: "DE8Y96K9QP", identifier: "com.cisco.endpoint.svc.securityextension") != nil)
        #expect(ManagedAgent.of(team: "DE8Y96K9QP", identifier: "com.cisco.secureclient.gui") == nil)
        #expect(ManagedAgent.of(team: "ABCDE12345", identifier: "com.crowdstrike.falcon.Agent") == nil)
        #expect(ManagedAgent.of(team: nil, identifier: "com.crowdstrike.falcon.Agent") == nil)
    }

    @Test func aJobOfSuchAnAgentStaysForTheAdministrator() throws {
        let directory = try TemporaryDirectory()
        let program = try directory.file("root/Library/Application Support/Example/agentd").path(percentEncoded: false)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["Label": "com.crowdstrike.falcon.daemon", "ProgramArguments": [program]],
            format: .xml, options: 0
        )
        try directory.file("root/Library/LaunchDaemons/com.crowdstrike.falcon.daemon.plist", contents: plist)
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        func row(team: String) -> BackgroundItem? {
            let ownership = BackgroundItemOwnership(installedApps: [], teamOfProgram: { $0 == program ? team : nil })
            return BackgroundItems.declared(in: environment, ownership: ownership).first
        }

        let managed = try #require(row(team: "X9E956P446"))
        #expect(managed.managedBy?.name == "CrowdStrike Falcon")
        #expect(!managed.canMoveToTrash)
        #expect(!managed.canBeControlled)
        #expect(row(team: "ABCDE12345")?.managedBy == nil)
        #expect(row(team: "ABCDE12345")?.canMoveToTrash == true)
    }

    @Test func aJobNoFileHereDeclaresStaysForTheAdministratorToo() throws {
        let directory = try TemporaryDirectory()
        try directory.file(
            "Applications/Falcon.app/Contents/Library/LoginItems/Helper.app/Contents/Info.plist",
            contents: PropertyListSerialization.data(
                fromPropertyList: ["CFBundleIdentifier": "org.example.loginhelper"], format: .xml, options: 0
            )
        )
        let falcon = InstalledApp(
            url: directory.url.appending(path: "Applications/Falcon.app", directoryHint: .isDirectory),
            bundleIdentifier: "com.crowdstrike.falcon.App", name: "Falcon", teamIdentifier: "X9E956P446"
        )
        let other = InstalledApp(
            url: URL(filePath: "/Applications/Tide.app", directoryHint: .isDirectory), bundleIdentifier: "org.example.tide",
            name: "Tide", teamIdentifier: "EXAMPLE123"
        )
        let daemon = directory.url.appending(path: "Library/Example/agentd").path(percentEncoded: false)
        let ownership = BackgroundItemOwnership(
            installedApps: [falcon, other], teamOfProgram: { $0 == daemon ? "4AYE5J54KN" : nil }
        )
        func item(
            _ label: String, _ kind: BackgroundItem.Kind, _ details: Launchctl.JobDetails
        ) throws -> BackgroundItem {
            let found = BackgroundItems.undeclaredItem(
                (label, kind, "system/\(label)"), answer: .details(details), ownership: ownership,
                loaded: .init(user: [label: 77], system: [label: 77]), exclusions: .none
            )
            guard case .item(let item) = found else { throw CocoaError(.featureUnsupported) }
            return item
        }
        func registered(by app: String) -> Launchctl.JobDetails {
            Launchctl.JobDetails(
                path: "(submitted by smd.341)", managedBy: "com.apple.xpc.ServiceManagement", parentBundleIdentifier: app
            )
        }
        let closedFile = directory.url.appending(path: "Library/LaunchDaemons/com.sentinelone.sentineld.plist")

        let ofTheAgent = try item("org.example.helper", .agent, registered(by: "com.crowdstrike.falcon.App"))
        #expect(ofTheAgent.managedBy?.name == "CrowdStrike Falcon")
        #expect(ofTheAgent.controls.isEmpty)
        let fromAFile = try item("com.sentinelone.sentineld", .daemon, .init(path: closedFile.path(percentEncoded: false), program: daemon))
        #expect(fromAFile.managedBy?.name == "SentinelOne")
        #expect(!fromAFile.canBeControlled)
        let ofAnotherApp = try item("org.example.helper", .agent, registered(by: "org.example.tide"))
        #expect(ofAnotherApp.managedBy == nil)
        #expect(ofAnotherApp.controls == [.stop])
        let named = "com.crowdstrike.falcon.App.other"
        let disabled = BackgroundItems.disabledJobs(
            in: .init(user: [:], system: [:], userDisabled: ["org.example.loginhelper": true, named: true]),
            listed: [], ownership: ownership
        )
        let declared = try #require(disabled.first { $0.label == "org.example.loginhelper" })
        #expect(declared.managedBy?.name == "CrowdStrike Falcon")
        #expect(!declared.offersEnableOrDisable)
        #expect(disabled.first { $0.label == named }.map { $0.managedBy == nil && $0.offersEnableOrDisable } == true)
    }

    @Test func anAppOfSuchAnAgentStaysForTheAdministrator() {
        let falcon = app("com.crowdstrike.falcon.App", team: "X9E956P446")

        #expect(falcon.removedElsewhere == .byYourOrganization(ManagedAgent.of(team: "X9E956P446", identifier: "com.crowdstrike.falcon.App")!))
        #expect(app("com.crowdstrike.falcon.App", team: "ABCDE12345").removedElsewhere == nil)
        let said = UninstallCommand.said(falcon.removedElsewhere, of: falcon, isAdministrator: true)?.description
        #expect(said?.contains("your IT administrator removes Agent") == true)
    }
}
