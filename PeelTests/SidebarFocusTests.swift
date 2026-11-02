import AppKit
@testable import Peel
import SwiftUI
import Testing

@MainActor
struct SidebarFocusTests {
    private final class WatchedWindow: NSWindow {
        var windowsOfTheViewsGivenFocus: [NSWindow?] = []

        override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
            if let view = responder as? NSOutlineView { windowsOfTheViewsGivenFocus.append(view.window) }
            return super.makeFirstResponder(responder)
        }
    }

    private struct Sidebar: View {
        var body: some View {
            List {
                Text("A row")
                Text("Another row")
            }
            .takesFocusWhenNothingHasIt()
        }
    }

    @Test func aListIsGivenTheFocusOnlyOnceItIsInTheWindow() throws {
        let sidebar = NSHostingController(rootView: Sidebar())
        sidebar.view.frame = NSRect(x: 0, y: 0, width: 300, height: 300)
        sidebar.view.layoutSubtreeIfNeeded()
        let controller = NSSplitViewController()
        controller.addSplitViewItem(NSSplitViewItem(sidebarWithViewController: sidebar))
        controller.addSplitViewItem(NSSplitViewItem(viewController: NSHostingController(rootView: Color.clear)))
        controller.view.frame = NSRect(x: 0, y: 0, width: 800, height: 300)
        controller.view.layoutSubtreeIfNeeded()
        let window = WatchedWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 300),
            styleMask: [.titled], backing: .buffered, defer: true
        )

        window.contentViewController = controller
        window.setContentSize(NSSize(width: 900, height: 400))
        window.layoutIfNeeded()

        #expect(!window.windowsOfTheViewsGivenFocus.isEmpty)
        #expect(window.windowsOfTheViewsGivenFocus.allSatisfy { $0 === window })
        #expect(window.firstResponder is NSOutlineView)
    }
}
