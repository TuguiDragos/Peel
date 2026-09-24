import AppKit
import os
import SwiftUI

extension View {
    /// Hides the line macOS draws between the title bar and a column whose content is scrolled.
    ///
    /// Each column has its own section of the title bar, so the line appears over the columns that scroll and not
    /// over the others. `NSSplitViewItem.titlebarSeparatorStyle` turns it off for a column once the column has its
    /// own section (see the toolbar item in `ContentView`). The window's style is set to `.none` as well, because
    /// an item's style is "subject to the containing window's preference" (`NSSplitViewItem.h`).
    func quietTitlebarSeparators() -> some View {
        background(TitlebarSeparators())
    }
}

private struct TitlebarSeparators: NSViewRepresentable {
    func makeNSView(context: Context) -> Anchor {
        Anchor()
    }

    func updateNSView(_ nsView: Anchor, context: Context) {}

    final class Anchor: NSView {
        override func layout() {
            super.layout()
            apply()
            PrivateStructure.check(.titlebarSeparators)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        private func apply() {
            // A window left on `.automatic` still draws the line over a column that scrolls. The window and every
            // item are both set, so neither can bring the line back.
            if let window, window.titlebarSeparatorStyle != .none {
                window.titlebarSeparatorStyle = .none
            }
            let controller = controller()
            for item in controller?.splitViewItems ?? [] where item.titlebarSeparatorStyle != .none {
                item.titlebarSeparatorStyle = .none
            }
            if controller != nil { PrivateStructure.found(.titlebarSeparators) }
        }

        /// The controller of the window's columns, found by searching down from the content view: this view is the
        /// background of the whole split view, so the split view is not among its superviews. SwiftUI builds the
        /// columns with an `NSSplitView` whose delegate is an `NSSplitViewController`.
        private func controller() -> NSSplitViewController? {
            guard let content = window?.contentView else { return nil }
            var found: NSSplitViewController?
            func walk(_ view: NSView) {
                if found == nil, let controller = (view as? NSSplitView)?.delegate as? NSSplitViewController {
                    found = controller
                    return
                }
                for child in view.subviews where found == nil { walk(child) }
            }
            walk(content)
            return found
        }
    }
}


/// Reports when SwiftUI stops building the columns from an `NSSplitViewController`. This file,
/// `FixedSplitViewColumn`, and `ListColumn` rely on that structure, which is not API. If it changes, their fixes
/// stop working without any error: the line under the title bar comes back, the sidebar can be dragged to any
/// width, and the list's title bar section runs past its divider.
///
/// In Debug builds, a probe that has not found its structure three seconds after its first layout logs a fault,
/// once. It waits because the columns are not connected yet during that first layout. Each probe is tracked on
/// its own, so one that works cannot hide one that has stopped. It only logs and never stops the app.
@MainActor
enum PrivateStructure {
    enum Probe {
        case titlebarSeparators
        case fixedColumn
        case listColumn

        var consequence: String {
            switch self {
            case .titlebarSeparators: "the line under the title bar is back"
            case .fixedColumn: "the sidebar can be dragged to any width"
            case .listColumn: "with the sidebar aside, the list's title bar runs past its divider"
            }
        }
    }

    private static var seen: Set<Probe> = []
    private static var watched: Set<Probe> = []

    static func found(_ probe: Probe) {
        seen.insert(probe)
    }

    static func check(_ probe: Probe) {
        #if DEBUG
        guard !seen.contains(probe), !watched.contains(probe) else { return }
        watched.insert(probe)
        Task {
            try? await Task.sleep(for: .seconds(3))
            guard !seen.contains(probe) else { return }
            Logger(subsystem: "com.tuguidragos.Peel", category: "layout")
                .fault("SwiftUI no longer builds the columns from NSSplitViewController: \(probe.consequence, privacy: .public)")
        }
        #endif
    }
}
