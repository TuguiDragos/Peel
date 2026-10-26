@testable import Peel
import SwiftUI
import Testing

@MainActor
struct UpToHeightTests {
    private func panelHeight(rows: Int, maximum: CGFloat) -> CGFloat {
        let list = VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { _ in Color.clear.frame(height: 40) }
        }
        let panel = UpToHeight(maximum: maximum) {
            VStack(spacing: 0) {
                Color.clear.frame(height: 50)
                ViewThatFits(in: .vertical) {
                    list
                    ScrollView { list }
                }
                Color.clear.frame(height: 50)
            }
            .frame(width: 320)
        }
        return NSHostingView(rootView: panel).fittingSize.height
    }

    @Test func aPanelTallerThanItsRoomTakesTheRoom() {
        #expect(panelHeight(rows: 60, maximum: 600) == 600)
    }

    @Test func aPanelThatFitsKeepsItsHeight() {
        #expect(panelHeight(rows: 5, maximum: 600) == 300)
    }
}
