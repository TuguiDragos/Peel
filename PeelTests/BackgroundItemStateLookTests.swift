import Foundation
@testable import Peel
@testable import PeelCore
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
        #expect(String(localized: job(.running(pid: 4_242), disabled: true).stateWords()) == String(localized: "Disabled, still running"))
        #expect(String(localized: job(.loaded, disabled: true).stateWords()) == String(localized: "Disabled"))
        #expect(String(localized: job(.running(pid: 4_242), disabled: false).stateWords()) == String(localized: "Running"))
    }

    @Test func whetherLaunchdHasTheJobIsSaidWhereTheStateDoesNotSayIt() {
        #expect(job(.loaded, disabled: false).loadWords().map { String(localized: $0) } == String(localized: "Loaded"))
        #expect(job(.loaded, disabled: true).loadWords().map { String(localized: $0) } == String(localized: "Loaded"))
        #expect(job(.notLoaded, disabled: true).loadWords().map { String(localized: $0) } == String(localized: "Not loaded"))
        #expect(job(.notLoaded, disabled: false).loadWords() == nil)
        #expect(job(.running(pid: 4_242), disabled: false).loadWords() == nil)
        #expect(job(.unknown, disabled: false).loadWords() == nil)
    }
}
