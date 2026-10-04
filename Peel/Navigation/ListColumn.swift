import AppKit
import SwiftUI

/// The width of the list column beside a tool's page: 365 points at first, never narrower, and as wide as the
/// user drags it. While the sidebar is hidden, the window's buttons and the sidebar button move into the list's
/// section of the title bar and can run past its divider, so the list widens to fit them, as far as the page's
/// 480 points allow. It gets its earlier width back when the sidebar returns. The divider is moved every time,
/// even to where it already is: on macOS 26, a split view built with the sidebar hidden draws no divider through
/// the title bar until a divider has moved.
@MainActor @Observable
final class ListColumn {
    static let minimum: CGFloat = 365
    /// The page's minimum width plus the divider between the page and the list.
    fileprivate static let besideList: CGFloat = 480 + 1

    /// Incremented each time the list should be fitted again: when the sidebar hides or returns, or when the page
    /// changes while the sidebar is hidden.
    fileprivate private(set) var request = 0
    @ObservationIgnored fileprivate var handled = 0
    @ObservationIgnored fileprivate private(set) var isAside = false
    @ObservationIgnored fileprivate private(set) var title = ""
    @ObservationIgnored fileprivate private(set) var restore: CGFloat?
    @ObservationIgnored fileprivate private(set) var beforeAside: CGFloat?
    @ObservationIgnored fileprivate var current = minimum

    func aside(title: String) {
        if beforeAside == nil { beforeAside = current }
        isAside = true
        self.title = title
        restore = nil
        request += 1
    }

    /// `room` is the width left for the list once the sidebar is back and the page has its 480 points.
    func show(room: CGFloat) {
        guard let before = beforeAside else { return }
        beforeAside = nil
        isAside = false
        restore = max(Self.minimum, min(before, room))
        request += 1
    }
}

extension View {
    func listColumn() -> some View {
        modifier(ListColumnWidth())
    }
}

private struct ListColumnWidth: ViewModifier {
    @Environment(ListColumn.self) private var column

    func body(content: Content) -> some View {
        // The width is read inside the column: a `GeometryReader` around the content would change the column's width.
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { column.current = $0 }
            .background(ListColumnDivider(column: column, request: column.request))
            .navigationSplitViewColumnWidth(min: ListColumn.minimum, ideal: ListColumn.minimum)
    }
}

/// Moves the list's divider the way a drag does. A width limit set through SwiftUI does not last: SwiftUI keeps its
/// own width for the column and puts it back once the limit is lifted.
private struct ListColumnDivider: NSViewRepresentable {
    let column: ListColumn
    let request: Int

    func makeNSView(context: Context) -> Mover {
        Mover(column: column)
    }

    func updateNSView(_ nsView: Mover, context: Context) {
        nsView.needsLayout = true
    }

    final class Mover: NSView {
        let column: ListColumn
        private var pending: Task<Void, Never>?
        private weak var observed: NSSplitView?

        init(column: ListColumn) {
            self.column = column
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func layout() {
            super.layout()
            if let splitView = enclosingSplitView?.view {
                PrivateStructure.found(.listColumn)
                observe(splitView)
            }
            PrivateStructure.check(.listColumn)
            fitSoon()
        }

        /// Also fits the list when the split view resizes its subviews, because the column can change width while
        /// the list inside it keeps its own, for example when the sidebar returns.
        private func observe(_ splitView: NSSplitView) {
            guard observed !== splitView else { return }
            if let observed {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSSplitView.didResizeSubviewsNotification,
                    object: observed
                )
            }
            observed = splitView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(splitViewResized),
                name: NSSplitView.didResizeSubviewsNotification,
                object: splitView
            )
        }

        @objc private func splitViewResized(_ notification: Notification) {
            fitSoon()
        }

        /// Fits the list once the columns have stopped changing for a moment. The sidebar hides and returns with an
        /// animation, and a divider moved before the animation ends lands in the wrong place. The frames of the
        /// sidebar and the column do not show when the animation is over, so this waits for them to stop changing.
        private func fitSoon() {
            guard column.request != column.handled else { return }
            pending?.cancel()
            pending = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                self?.fit()
            }
        }

        private func fit() {
            guard column.request != column.handled, let split = enclosingSplitView else { return }
            // While the sidebar is shown, the column's view runs under it and is wider than the list. Go on only
            // when that matches `isAside`, that is, once the sidebar has finished hiding or returning.
            guard (split.item.viewController.view.frame.width - bounds.width >= 1) != column.isAside else { return }
            let target: CGFloat
            if column.isAside {
                guard let needs = titleBarNeeds(dividerIndex: split.index) else { return }
                target = max(
                    ListColumn.minimum,
                    min(
                        split.view.bounds.width - ListColumn.besideList,
                        max(column.beforeAside ?? ListColumn.minimum, needs)
                    )
                )
            } else if let restore = column.restore {
                target = restore
            } else {
                column.handled = column.request
                return
            }
            column.handled = column.request
            let position = split.item.viewController.view.frame.maxX + target - bounds.width
            // A move to where the divider already is does nothing, so it goes a point away first.
            if abs(target - bounds.width) < 1 {
                split.view.setPosition(position + 1, ofDividerAt: split.index)
            }
            split.view.setPosition(position, ofDividerAt: split.index)
        }

        /// The width the list's section of the title bar needs while the sidebar is hidden. On macOS 26, the
        /// window's buttons and the sidebar button end at 148 points, the title takes its text width plus 24 (at
        /// least 160), each toolbar item takes its view plus 8, and the divider sits 4 into its own item.
        private func titleBarNeeds(dividerIndex: Int) -> CGFloat? {
            guard let items = window?.toolbar?.items,
                  let end = items.firstIndex(where: {
                      ($0 as? NSTrackingSeparatorToolbarItem)?.dividerIndex == dividerIndex
                  }),
                  let start = items[..<end].lastIndex(where: { $0 is NSTrackingSeparatorToolbarItem })
            else { return nil }
            let itemsWidth = items[(start + 1)..<end].reduce(0) { $0 + ($1.view?.frame.width ?? 0) + 8 }
            let words = [NSFont.Weight.semibold, .bold]
                .map {
                    (column.title as NSString)
                        .size(withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: $0)]).width
                }
                .max() ?? 0
            return ceil(148 + max(160, words + 24) + itemsWidth + 4)
        }

        /// The split view around this view, the item of the column that holds it, and that item's index. This
        /// structure is not API (see `PrivateStructure`).
        private var enclosingSplitView: (view: NSSplitView, item: NSSplitViewItem, index: Int)? {
            var view = superview
            while let current = view {
                if let splitView = current as? NSSplitView,
                   let controller = splitView.delegate as? NSSplitViewController,
                   let index = controller.splitViewItems
                       .firstIndex(where: { isDescendant(of: $0.viewController.view) }) {
                    return (splitView, controller.splitViewItems[index], index)
                }
                view = current.superview
            }
            return nil
        }
    }
}
