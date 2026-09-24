import AppKit
import SwiftUI

extension View {
    /// Holds the split view column around this view at `width`: a divider drag cannot resize it, and a window
    /// resize cannot collapse it.
    func fixedSplitViewColumn(width: CGFloat) -> some View {
        navigationSplitViewColumnWidth(width)
            .background(FixedColumnLock(width: width))
    }
}

/// Sets the limits on the `NSSplitViewItem` that hosts the column, because SwiftUI's column width alone does not
/// stop a divider drag from resizing it.
private struct FixedColumnLock: NSViewRepresentable {
    let width: CGFloat

    func makeNSView(context: Context) -> Probe {
        Probe(width: width)
    }

    func updateNSView(_ nsView: Probe, context: Context) {
        nsView.width = width
    }

    final class Probe: NSView {
        var width: CGFloat {
            didSet { if width != oldValue { needsLayout = true } }
        }

        init(width: CGFloat) {
            self.width = width
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func layout() {
            super.layout()
            PrivateStructure.check(.fixedColumn)
            guard let item = enclosingSplitViewItem else { return }
            PrivateStructure.found(.fixedColumn)
            // The sidebar button and ⌃⌘S collapse the column, so `canCollapse` stays on, and pinning the thickness
            // keeps a divider drag from resizing it. `canCollapse` is set first because assigning it resets
            // `canCollapseFromWindowResize` to the same value. That one stays off: AppKit's collapse misses a resize
            // made from outside the window, so `ContentView` hides the sidebar in a narrow window instead.
            item.canCollapse = true
            item.canCollapseFromWindowResize = false
            item.minimumThickness = width
            item.maximumThickness = width
        }
    }
}

extension NSView {
    /// The split view item whose column holds this view, found through the `NSSplitViewController` that SwiftUI
    /// builds. That structure is not API (see `PrivateStructure`).
    var enclosingSplitViewItem: NSSplitViewItem? {
        var view = superview
        while let current = view {
            if let controller = (current as? NSSplitView)?.delegate as? NSSplitViewController {
                return controller.splitViewItems.first { isDescendant(of: $0.viewController.view) }
            }
            view = current.superview
        }
        return nil
    }
}
