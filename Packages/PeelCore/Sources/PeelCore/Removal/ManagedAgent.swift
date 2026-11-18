public import Foundation

/// An agent an organization manages its Macs with, which the organization's IT administrator removes.
public struct ManagedAgent: Sendable, Hashable {
    public let name: String
    public let page: URL?

    /// Each agent's signing team and the identifiers its parts begin with, as its maker documents them or, for
    /// CrowdStrike and SentinelOne, as several administrators' guides agree.
    private static let known: [(team: String, families: [String], name: String, page: String?)] = [
        (
            "483DWKW443", ["com.jamf.protect"], "Jamf Protect",
            "https://learn.jamf.com/r/en-US/jamf-protect-documentation/Uninstalling_Jamf_Protect"
        ),
        ("7AGZNQ2S2T", ["com.vmware.carbonblack.cloud", "com.carbonblack.defense.kext"], "Carbon Black Cloud", nil),
        (
            "DE8Y96K9QP", ["com.cisco.endpoint.svc"], "Cisco Secure Endpoint",
            "https://www.cisco.com/c/en/us/support/docs/security/amp-endpoints/216232-manual-uninstall-procedure-for-amp-for-e.html"
        ),
        (
            "2BT3HPN62Z", ["co.elastic"], "Elastic Agent",
            "https://www.elastic.co/docs/reference/fleet/uninstall-elastic-agent"
        ),
        ("X9E956P446", ["com.crowdstrike.falcon"], "CrowdStrike Falcon", nil),
        ("4AYE5J54KN", ["com.sentinelone"], "SentinelOne", nil),
    ]

    static func of(team: String?, identifier: String?) -> ManagedAgent? {
        guard let team, let identifier = identifier?.lowercased(),
              let agent = known.first(where: { agent in
                  agent.team == team && agent.families.contains { identifier == $0 || identifier.hasPrefix($0 + ".") }
              })
        else { return nil }
        return ManagedAgent(name: agent.name, page: agent.page.flatMap(URL.init(string:)))
    }
}
