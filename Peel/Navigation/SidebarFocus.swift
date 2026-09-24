import AppKit
import SwiftUI

extension View {
    /// Gives the keyboard focus to this column's list whenever nothing in the window holds it.
    ///
    /// The whole pages (`ContentView.isWholePage`) sit in a split view of two columns and the tools in one of
    /// three, so going from one to the other builds the sidebar again, and AppKit leaves the window itself as the
    /// first responder. The sidebar's selection is then drawn in the unfocused gray. Asking SwiftUI for the focus
    /// from the new sidebar (`.task`, `.defaultFocus`) is not reliable here, so this sets it through AppKit.
    func takesFocusWhenNothingHasIt() -> some View {
        background(ListFocus())
    }
}

private struct ListFocus: NSViewRepresentable {
    func makeNSView(context: Context) -> Anchor {
        Anchor()
    }

    func updateNSView(_ nsView: Anchor, context: Context) {}

    final class Anchor: NSView {
        private var observation: NSKeyValueObservation?

        // Takes the focus at once, never on a later turn of the run loop, so no frame is drawn with the
        // selection in the unfocused gray first.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // `firstResponder` is KVO compliant (`NSWindow.h`), and AppKit changes it on the main thread.
            observation = window?.observe(\.firstResponder, options: [.initial, .new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.takeFocusIfNothingHasIt() }
            }
        }

        /// Checks again on layout, because the list can reach the window after this view does, and layout runs
        /// before the frame is drawn.
        override func layout() {
            super.layout()
            takeFocusIfNothingHasIt()
        }

        private func takeFocusIfNothingHasIt() {
            guard let window, window.firstResponder === window, let list = list(in: enclosingSplitViewItem?.viewController.view) else { return }
            window.makeFirstResponder(list)
        }

        private func list(in view: NSView?) -> NSOutlineView? {
            guard let view else { return nil }
            if let outline = view as? NSOutlineView { return outline }
            for child in view.subviews {
                if let outline = list(in: child) { return outline }
            }
            return nil
        }
    }
}
