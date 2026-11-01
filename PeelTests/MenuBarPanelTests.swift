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
}
