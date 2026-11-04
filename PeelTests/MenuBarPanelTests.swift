import Foundation
@testable import Peel
import SwiftUI
import Testing

@MainActor
struct MenuBarPanelTests {
    private func height(with updater: PeelUpdater) throws -> CGFloat {
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "MenuBarPanelTests-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        let panel = MenuBarPanel()
            .environment(AppLibrary(defaults: made.defaults))
            .environment(HomebrewLibrary())
            .environment(LifetimeStats(
                defaults: made.defaults, bundle: folder, history: folder.appending(path: "removals.json")
            ))
            .environment(FoundLastTimeStore(defaults: made.defaults))
            .environment(updater)
        return NSHostingView(rootView: panel).fittingSize.height
    }

    @Test func aNewVersionOfPeelHasARowOfItsOwn() throws {
        #expect(try height(with: PeelUpdater(found: "9.9")) > height(with: PeelUpdater()))
    }

    @Test func showsAHiddenPeel() {
        let app = StandInApp(isHidden: true)
        MenuBarPanel.showPeelIfHidden(app)
        #expect(!app.isHidden)
        #expect(app.unhides == 1)
    }

    @Test func leavesAPeelThatIsNotHiddenAlone() {
        let app = StandInApp(isHidden: false)
        MenuBarPanel.showPeelIfHidden(app)
        #expect(app.unhides == 0)
    }
}

/// The test host can't be hidden on demand: its activation policy is prohibited while it hosts tests.
private final class StandInApp: HidingApp {
    var isHidden: Bool
    var unhides = 0

    init(isHidden: Bool) { self.isHidden = isHidden }

    func unhideWithoutActivation() {
        unhides += 1
        isHidden = false
    }
}
