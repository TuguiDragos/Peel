import AppKit
@testable import Peel
import SwiftUI
import Testing

@MainActor
struct SectionHeaderLineTests {
    private nonisolated final class Counter {
        var count = 0
    }

    /// Counts how often SwiftUI asks the view inside for its size.
    private struct Counting: Layout {
        let counter: Counter

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            counter.count += 1
            return subviews.first?.sizeThatFits(proposal) ?? .zero
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        }
    }

    private struct Measured {
        let heading = Counter(), buttons = Counter()

        var measuredHeading: some View {
            Counting(counter: heading) {
                HStack(spacing: 5) {
                    Text(verbatim: "Review Before Removing")
                    Button(String("i")) {}
                }
            }
        }

        var measuredButtons: some View {
            Counting(counter: buttons) { Button(String("Select")) {} }
        }

        func size(of view: some View, width: CGFloat) -> (heading: Int, buttons: Int) {
            let host = NSHostingController(rootView: view)
            heading.count = 0
            buttons.count = 0
            _ = host.sizeThatFits(in: CGSize(width: width, height: 200))
            return (heading.count, buttons.count)
        }
    }

    @Test(arguments: [CGFloat(600), 160, 40])
    func measuresEachPartAsOftenAsAPlainRow(width: CGFloat) {
        let header = Measured(), row = Measured()
        let inHeader = header.size(
            of: SectionHeaderLine {
                header.measuredHeading
            } count: {
                Text(verbatim: "8 items")
            } actions: {
                header.measuredButtons
            },
            width: width
        )
        let inRow = row.size(
            of: HStack(spacing: 8) {
                row.measuredHeading
                Spacer(minLength: 8)
                Text(verbatim: "8 items")
                row.measuredButtons
            },
            width: width
        )
        #expect(inHeader.heading <= inRow.heading)
        #expect(inHeader.buttons <= inRow.buttons)
    }
}
