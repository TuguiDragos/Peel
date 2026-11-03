import AppKit
@testable import Peel
import SwiftUI
import Testing

@MainActor
struct SidebarRulerTests {
    private final class Widths {
        var chosen: CGFloat = 0
        var measured: CGFloat = 0
    }

    @Test func theRulerMeasuresALabelAsWideAsAChosenRowDrawsIt() async {
        let name = "Elementi in background"
        let widths = Widths()
        let sidebar = List(selection: .constant("chosen")) {
            Label {
                Text(verbatim: name)
            } icon: {
                Image(systemName: "gearshape.2")
            }
            .background {
                ToolSidebar.asChosen(Text(verbatim: name))
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { widths.measured = $0 }
            }
            .tag("other")
            Label {
                Text(verbatim: name)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { widths.chosen = $0 }
            } icon: {
                Image(systemName: "gearshape.2")
            }
            .tag("chosen")
        }
        .listStyle(.sidebar)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.titled],
            backing: .buffered, defer: true
        )
        window.contentView = NSHostingView(rootView: sidebar)

        for _ in 0..<200 where widths.chosen == 0 || widths.measured == 0 {
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(widths.chosen > 0)
        #expect(widths.measured >= widths.chosen)
    }
}
