import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct BackgroundItemAnnouncementTests {
    private func job(_ state: BackgroundItem.State, disabled: Bool = false) -> BackgroundItem {
        BackgroundItem(
            label: "org.example.agent", kind: .agent, source: .userLibrary, plistURL: nil,
            program: "/usr/local/bin/agent", runsAtLoad: true, keepsAlive: false, ownerBundleIdentifier: nil,
            ownerName: nil, ownerURL: nil, isOrphan: false, state: state, isDisabled: disabled
        )
    }

    @Test func saysTheStateAnActionLeftAnItemIn() {
        let stopped = BackgroundItemLibrary.announcement(for: job(.running(pid: 42)), in: [job(.loaded)])
        let disabled = BackgroundItemLibrary.announcement(for: job(.loaded), in: [job(.loaded, disabled: true)])
        let gone = BackgroundItemLibrary.announcement(for: job(.loaded), in: [])

        #expect(stopped.map { String($0.characters) } == words("Not running"))
        #expect(disabled.map { String($0.characters) } == words("Disabled"))
        #expect(gone == nil)
    }

    private func words(_ state: LocalizedStringResource) -> String {
        String(localized: "\("org.example.agent"): \(String(localized: state))")
    }
}
