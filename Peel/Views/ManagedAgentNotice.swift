import PeelCore
import SwiftUI

/// The note on the page of an agent the IT administrator removes.
struct ManagedAgentNotice: View {
    let agent: ManagedAgent

    var body: some View {
        Notice(title: Text(Self.title(of: agent)), detail: Text("Your IT administrator removes it."), kind: .note) {
            if let page = agent.page {
                Link("Instructions from \(agent.name)", destination: page)
            }
        }
    }

    static func title(of agent: ManagedAgent) -> LocalizedStringResource {
        "Your organization manages this Mac with \(agent.name)"
    }
}
