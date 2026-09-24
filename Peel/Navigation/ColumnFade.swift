import AppKit
import SwiftUI

extension View {
    /// Fades in this page's column when the page enters the window.
    func fadesInOnArrival() -> some View {
        background(ColumnFade(value: nil))
    }

    /// Fades the column in again when `value` changes while the column is on screen. The first value never
    /// fades, and a change while a fade is running does not start another.
    func fadesInColumn(on value: some Hashable) -> some View {
        background(ColumnFade(value: AnyHashable(value)))
    }

    /// Fades the column in again when its rows change, such as after a Move to Trash or a rescan that finds
    /// something else. On macOS 26.0 a `List` cannot animate rows as they are removed, so the whole list fades in
    /// instead. Pass the rows as found, not as filtered, so typing in a search field fades nothing. A detail page
    /// is rebuilt for each selection, so choosing another row does not count as a change.
    func fadesInColumn<ID: Hashable>(whenRowsChange rows: [ID]?) -> some View {
        fadesInColumn(on: rows)
    }
}

private struct ColumnFade: NSViewRepresentable {
    /// Nil for a page that fades only as it arrives.
    let value: AnyHashable?

    func makeNSView(context: Context) -> Anchor {
        Anchor(fadesOnArrival: value == nil)
    }

    func updateNSView(_ anchor: Anchor, context: Context) {
        guard let value, anchor.value != value else { return }
        if anchor.value != nil, anchor.window != nil, !anchor.isFading {
            anchor.fadeIn()
        }
        anchor.value = value
    }

    final class Anchor: NSView {
        let fadesOnArrival: Bool
        var value: AnyHashable?

        init(fadesOnArrival: Bool) {
            self.fadesOnArrival = fadesOnArrival
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, fadesOnArrival {
                fadeIn()
            }
        }

        var isFading: Bool {
            column?.layer?.animation(forKey: "fade") != nil
        }

        func fadeIn() {
            guard let layer = column?.layer else { return }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.duration = Motion.step.duration
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(fade, forKey: "fade")
        }

        /// The ancestor two levels below the `NSSplitView`, found by walking up the view tree, because a split
        /// view that was just built does not report `enclosingSplitViewItem` yet. This structure is not API (see
        /// `PrivateStructure`). Outside a split view, such as in a sheet, it is nil and nothing fades.
        private var column: NSView? {
            var view = superview
            while let current = view, !(current.superview?.superview is NSSplitView) {
                view = current.superview
            }
            return view
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
