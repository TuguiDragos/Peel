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

    @Test func anAppOfSuchAnAgentStaysForTheAdministrator() {
        let falcon = app("com.crowdstrike.falcon.App", team: "X9E956P446")

        #expect(falcon.removedElsewhere == .byYourOrganization(ManagedAgent.of(team: "X9E956P446", identifier: "com.crowdstrike.falcon.App")!))
        #expect(app("com.crowdstrike.falcon.App", team: "ABCDE12345").removedElsewhere == nil)
        let said = UninstallCommand.said(falcon.removedElsewhere, of: falcon, isAdministrator: true)?.description
        #expect(said?.contains("your IT administrator removes Agent") == true)
    }
}
