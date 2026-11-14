import AppKit
@testable import Peel
import PeelCore
import SwiftUI
import Testing

@MainActor
struct DefaultAppsSectionTests {
    private func size(of view: some View) -> CGSize {
        NSHostingView(rootView: view).fittingSize
    }

    @Test func aListOfManyKindsScrollsUnderThePopoverCeilingAndAShortOneHugsIt() {
        let extensions = (1...60).map { ".x\($0)" }.joined(separator: ", ")
        let kinds = (1...100).map { "Kind \($0)" } + ["Image File (\(extensions))"]
        let many = DefaultHandOver(app: "Preview", kinds: kinds, count: 160)
        let few = DefaultHandOver(app: nil, kinds: ["JPEG image", "PNG image", "TIFF image"], count: 3)

        let tall = size(of: HandOverList(handOver: many, kind: .fileKind))
        let short = size(of: HandOverList(handOver: few, kind: .fileKind))

        #expect(tall.height == 460)
        #expect(short.height < 200)
        #expect(tall.width == 340 && short.width == 340)
    }

    @Test func manyAppsTakingOverWrapTheirBadgesWholeInsideTheRow() {
        let one = [DefaultHandOver(app: "Preview", kinds: ["JPEG image"], count: 1)]
        let twelve = (1...12).map { DefaultHandOver(app: "Viewer \($0)", kinds: ["Kind \($0)"], count: $0) }
        let size = { (handOvers: [DefaultHandOver]) in
            NSHostingController(
                rootView: HandOverRow(lead: "Once it’s gone, they open with", handOvers: handOvers, kind: .fileKind)
            ).sizeThatFits(in: CGSize(width: 480, height: 10_000))
        }

        let wrapped = size(twelve)

        #expect(wrapped.width <= 480)
        #expect(wrapped.height > 2 * size(one).height)
    }
}
