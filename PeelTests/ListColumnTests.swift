import AppKit
@testable import Peel
import Testing

@MainActor
struct ListColumnTests {
    private final class Pane: NSViewController {
        override func loadView() {
            view = NSView()
        }
    }

    /// A window holding a sidebar, a list and a page, the three columns SwiftUI builds for a tool.
    private func columns() -> (NSWindow, NSSplitViewController) {
        let controller = NSSplitViewController()
        let sidebar = NSSplitViewItem(sidebarWithViewController: Pane())
        sidebar.minimumThickness = 221
        sidebar.maximumThickness = 221
        let list = NSSplitViewItem(contentListWithViewController: Pane())
        list.minimumThickness = ListColumn.width
        list.maximumThickness = ListColumn.width
        let page = NSSplitViewItem(viewController: Pane())
        page.minimumThickness = 480
        [sidebar, list, page].forEach(controller.addSplitViewItem)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1307, height: 800),
            styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false
        )
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1307, height: 800))
        window.layoutIfNeeded()
        return (window, controller)
    }

    private func pageStart(of controller: NSSplitViewController) -> CGFloat? {
        let page = controller.splitViewItems[2].viewController.view
        return controller.splitView.subviews.first { page.isDescendant(of: $0) }?.frame.minX
    }

    /// Gives the list the widths the column asks for, as SwiftUI does, and lays the window out.
    private func apply(_ column: ListColumn, to controller: NSSplitViewController, in window: NSWindow) {
        controller.splitViewItems[1].minimumThickness = column.widths.lowerBound
        controller.splitViewItems[1].maximumThickness = column.widths.upperBound
        window.layoutIfNeeded()
    }

    @Test func theDividerStaysWhereItIsWhileTheSidebarHidesAndReturns() throws {
        let (window, controller) = columns()
        let column = ListColumn()
        #expect(column.found(controller))
        let start = try #require(pageStart(of: controller))

        column.sidebarSlides(aside: true, windowWidth: 1307)
        apply(column, to: controller, in: window)
        controller.splitViewItems[0].isCollapsed = true
        window.layoutIfNeeded()
        #expect(pageStart(of: controller) == start)
        column.settle()
        apply(column, to: controller, in: window)
        #expect(pageStart(of: controller) == start)
        #expect(column.widths.lowerBound == column.widths.upperBound)

        column.sidebarSlides(aside: false, windowWidth: 1307)
        apply(column, to: controller, in: window)
        controller.splitViewItems[0].isCollapsed = false
        window.layoutIfNeeded()
        #expect(pageStart(of: controller) == start)
        column.settle()
        apply(column, to: controller, in: window)
        #expect(pageStart(of: controller) == start)
        #expect(column.widths == ListColumn.width...ListColumn.width)
    }

    @Test func aHiddenSidebarLeavesThePageItsWidthInANarrowWindow() {
        let (window, controller) = columns()
        let column = ListColumn()
        #expect(column.found(controller))
        column.rest(aside: true, windowWidth: 1000)
        #expect(column.widths == (1000 - ListColumn.besideList)...(1000 - ListColumn.besideList))
        column.rest(aside: false, windowWidth: 1000)
        #expect(column.widths == ListColumn.width...ListColumn.width)
        withExtendedLifetime(window) {}
    }
}
