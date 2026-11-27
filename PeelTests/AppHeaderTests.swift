import AppKit
@testable import Peel
import PeelCore
import SwiftUI
import Synchronization
import Testing

@MainActor
struct AppHeaderTests {
    private nonisolated final class Offered: Sendable {
        private let width = Mutex<CGFloat?>(nil)
        var value: CGFloat? { width.withLock { $0 } }
        func set(_ value: CGFloat?) { width.withLock { $0 = value } }
    }

    /// Takes almost no room and notes the width the text column offers it. SwiftUI also asks with no width and with
    /// an endless one, to learn how far the view bends, which say nothing of the column.
    private struct Probe: Layout {
        let offered: Offered

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            if let width = proposal.width, width.isFinite, width > 0 { offered.set(width) }
            return CGSize(width: 1, height: 1)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {}
    }

    /// The width the text column of a head `width` wide has for its lines.
    private func textColumn(total: SizeTotal?, in width: CGFloat) -> CGFloat? {
        let offered = Offered()
        let app = InstalledApp(
            url: URL(filePath: "/Applications/Tide.app"), bundleIdentifier: "org.example.tide", name: "Tide",
            version: "3.2.1"
        )
        let header = AppHeader(
            app: app, updateStatus: .upToDate, isCheckingForUpdates: false, cannotCheck: .namesNoFeed, brew: "brew",
            total: total
        ) {
            Probe(offered: offered) {}
        }
        _ = NSHostingController(rootView: header).sizeThatFits(in: CGSize(width: width, height: 300))
        return offered.value
    }

    @Test func theTextTakesAllTheRoomButTheRowsSpacingBeforeTheSize() throws {
        let icon: CGFloat = 64, spacing: CGFloat = 16, width: CGFloat = 700
        let total = SizeTotal(known: 612_000_000, isComplete: true)
        let label = NSHostingController(rootView: TotalLabel(total: total, caption: Text("to remove")))
            .sizeThatFits(in: CGSize(width: 1_000, height: 100)).width

        let alone = try #require(textColumn(total: nil, in: width))
        let besideTheSize = try #require(textColumn(total: total, in: width))

        #expect(alone == width - icon - spacing)
        #expect(abs(besideTheSize - (width - icon - spacing - spacing - label)) <= 1)
    }
}
