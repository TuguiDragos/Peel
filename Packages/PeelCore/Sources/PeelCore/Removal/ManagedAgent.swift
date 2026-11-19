public import Foundation

/// An agent an organization manages its Macs with, which the organization's IT administrator removes.
public struct ManagedAgent: Sendable, Hashable {
    public let name: String
    public let page: URL?
    /// The command its maker's page gives a person who installed it for their own Mac, for an agent one can.
    let ownCommand: OwnCommand?

    struct OwnCommand: Sendable, Hashable {
        let maker: String
        let program: String
        let arguments: String
    }

    /// Whether whose it is depends on whether an organization enrolled this Mac: an agent a person can also install.
    public var dependsOnDeviceManagement: Bool { ownCommand != nil }

    /// Whether an organization removes it: always, but for an agent a person can also install on a Mac that `profiles`
    /// says no organization enrolled.
    public var isTheOrganizations: Bool {
        ownCommand == nil || DeviceManagement.enrollment != .notEnrolled
    }

    /// The maker's own step while it isn't the organization's: the command from the maker's page, offered only where
    /// the maker puts the program and only root can change it, as every maker's command run with `sudo` is.
    public var makersUninstaller: MakersUninstaller? {
        makersUninstaller(
            isOnTheMac: { !URL(filePath: $0).isMissing }, isOnlyRoots: MakersUninstaller.onlyRootCanChange
        )
    }

    func makersUninstaller(isOnTheMac: (String) -> Bool, isOnlyRoots: (URL) -> Bool) -> MakersUninstaller? {
        guard !isTheOrganizations, let own = ownCommand, let page else { return nil }
        let program = URL(filePath: own.program)
        let step: MakersUninstaller.Step = if !isOnTheMac(own.program) {
            .notOnTheMac
        } else if isOnlyRoots(program) {
            .command("sudo \(program.wordForTheShell(home: .homeDirectory)) \(own.arguments)")
        } else {
            .notTrusted
        }
        return MakersUninstaller(maker: own.maker, step: step, instructions: page, removes: nil)
    }

    /// Each agent's signing team and the identifiers its parts begin with, as its maker documents them or, for
    /// CrowdStrike and SentinelOne, as several administrators' guides agree.
    private static let known: [(team: String, families: [String], name: String, page: String?, own: OwnCommand?)] = [
        (
            "483DWKW443", ["com.jamf.protect"], "Jamf Protect",
            "https://learn.jamf.com/r/en-US/jamf-protect-documentation/Uninstalling_Jamf_Protect", nil
        ),
        ("7AGZNQ2S2T", ["com.vmware.carbonblack.cloud", "com.carbonblack.defense.kext"], "Carbon Black Cloud", nil, nil),
        (
            "DE8Y96K9QP", ["com.cisco.endpoint.svc"], "Cisco Secure Endpoint",
            "https://www.cisco.com/c/en/us/support/docs/security/amp-endpoints/216232-manual-uninstall-procedure-for-amp-for-e.html",
            nil
        ),
        (
            "2BT3HPN62Z", ["co.elastic"], "Elastic Agent",
            "https://www.elastic.co/docs/reference/fleet/uninstall-elastic-agent",
            OwnCommand(maker: "Elastic", program: "/Library/Elastic/Agent/elastic-agent", arguments: "uninstall")
        ),
        ("X9E956P446", ["com.crowdstrike.falcon"], "CrowdStrike Falcon", nil, nil),
        ("4AYE5J54KN", ["com.sentinelone"], "SentinelOne", nil, nil),
    ]

    static func of(team: String?, identifier: String?) -> ManagedAgent? {
        guard let team, let identifier = identifier?.lowercased(),
              let agent = known.first(where: { $0.team == team && holds(identifier, in: $0.families) })
        else { return nil }
        return ManagedAgent(name: agent.name, page: agent.page.flatMap(URL.init(string:)), ownCommand: agent.own)
    }

    /// Whether an agent's family holds `identifier`, whoever signed what bears it.
    static func isInAFamily(_ identifier: String) -> Bool {
        known.contains { holds(identifier.lowercased(), in: $0.families) }
    }

    private static func holds(_ identifier: String, in families: [String]) -> Bool {
        families.contains { identifier == $0 || identifier.hasPrefix($0 + ".") }
    }
}
