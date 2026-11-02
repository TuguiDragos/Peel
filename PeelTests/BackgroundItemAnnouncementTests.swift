import Accessibility
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

    @Test func anActionsOwnScanIsToldToNobody() async {
        final class Reads {
            var shown: [Bool] = []
            var library: BackgroundItemLibrary?
        }
        let reads = Reads()
        let listed = job(.loaded)
        let library = BackgroundItemLibrary { _, _ in
            reads.shown.append(reads.library?.isScanningAsAsked == true)
            return BackgroundItems.Scan(items: [listed])
        }
        reads.library = library

        await library.refresh(installedApps: [])
        await library.perform(.stop, on: listed)

        #expect(reads.shown == [true, false])
    }

    @Test func aScansEndWaitsForWhatVoiceOverIsSaying() {
        let words = AttributedString("Found").waitingForOtherSpeech

        #expect(words.accessibilitySpeechAnnouncementPriority == .low)
    }

    private func words(_ state: LocalizedStringResource) -> String {
        String(localized: "\("org.example.agent"): \(String(localized: state))")
    }
}
