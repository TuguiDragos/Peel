import AppKit
@testable import Peel
import SwiftUI
import Testing

@MainActor
struct ListNotesTests {
    private final class Heights {
        var row: CGFloat = 0
        var note: CGFloat = 0
    }

    private struct Page: View {
        let heights: Heights

        var body: some View {
            List {
                Section {
                    Text(verbatim: "Row")
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights.row = $0 }
                    ListNotes {
                        Text(verbatim: String(repeating: "Peel leaves this folder where it is for now. ", count: 8))
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights.note = $0 }
                    }
                }
            }
        }
    }

    @Test func aNoteUnderAListsRowsShowsEveryLine() async {
        let heights = Heights()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 600), styleMask: [.titled],
            backing: .buffered, defer: true
        )
        window.contentView = NSHostingView(rootView: Page(heights: heights))

        for _ in 0..<200 where heights.note == 0 || heights.row == 0 {
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(heights.row > 0)
        #expect(heights.note > 3 * heights.row)
    }
}
