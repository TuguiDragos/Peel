import Foundation
@testable import Peel
@testable import PeelCore
import SwiftUI
import Testing

struct BackgroundItemStateLookTests {
    private func job(_ state: BackgroundItem.State, disabled: Bool) -> BackgroundItem {
        BackgroundItem(
            label: "org.example.agent", kind: .agent, source: .userLibrary, plistURL: nil,
            program: "/usr/local/bin/agent", runsAtLoad: true, keepsAlive: true, ownerBundleIdentifier: nil,
            ownerName: nil, ownerURL: nil, isOrphan: false, state: state, isDisabled: disabled
        )
    }

    @Test func aDisabledJobThatStillRunsSaysBoth() {
        #expect(job(.running(pid: 4_242), disabled: true).stateLook().title == Text("Disabled, still running"))
        #expect(job(.loaded, disabled: true).stateLook().title == Text("Disabled"))
        #expect(job(.running(pid: 4_242), disabled: false).stateLook().title == Text("Running"))
    }
}
