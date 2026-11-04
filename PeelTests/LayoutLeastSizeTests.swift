import AppKit
@testable import Peel
import SwiftUI
import Testing

@MainActor
struct LayoutLeastSizeTests {
    private func leastAndIdealHeight(of view: some View) -> (least: CGFloat, ideal: CGFloat) {
        let host = NSHostingController(rootView: view)
        return (host.sizeThatFits(in: .zero).height, host.view.fittingSize.height)
    }

    @Test func aNoticeAskedForItsLeastSizeIsNoTallerThanItsIdealOne() {
        let heights = leastAndIdealHeight(of: Notice(
            title: Text(verbatim: "History no longer lists 1 older removal"),
            detail: Text(verbatim: "What was moved is still in the Trash unless you emptied it."),
            kind: .note
        ) { EmptyView() })

        #expect(heights.least <= heights.ideal)
    }

    @Test func aFlowAskedForItsLeastSizeIsNoTallerThanItsIdealOne() {
        let heights = leastAndIdealHeight(of: FlowLayout {
            Text(verbatim: "Needs approval, or was turned off")
            Button("Open System Settings") {}
                .buttonStyle(.link)
        })

        #expect(heights.least <= heights.ideal)
    }
}
