import AppKit
import SwiftUI

/// The list column beside a tool's page. Its divider stays where it is whether the sidebar is shown or not, and it
/// can't be dragged: the sidebar floats over the list's left part, so hiding it uncovers the list beneath and showing
/// it covers it again. While the sidebar slides, the page's place is pinned, so the list takes exactly the room the
/// sidebar leaves or gives it back: AppKit otherwise hands that room to the page at once, since the page holds its
/// width with the lowest priority, and the divider moves.
@MainActor @Observable
final class ListColumn {
    /// The list's width beside the sidebar.
    static let width: CGFloat = 366
    /// The page's minimum width plus the divider between the page and the list.
    static let besideList: CGFloat = 480 + 1

    /// What the list's width is held within: one width at rest, both ends while the sidebar slides.
    fileprivate(set) var widths: ClosedRange<CGFloat> = width...width
    /// Incremented each time the sidebar starts to slide, so the column lets go of the page once it stops.
    fileprivate private(set) var slides = 0
    @ObservationIgnored fileprivate var settled = 0
    @ObservationIgnored private var aside = false
    @ObservationIgnored private var windowWidth: CGFloat = 0
    /// How much of the list the sidebar covers while it is shown: its width, and the margin it floats in by where
    /// macOS draws one. Read from AppKit's layout, which keeps the sidebar's place while it is hidden too.
    @ObservationIgnored private var covered: CGFloat = 0
    @ObservationIgnored private weak var columns: NSSplitViewController?
    @ObservationIgnored private var pin: NSLayoutConstraint?

    /// The list's width without the sidebar: also the part the sidebar covered, so the divider stays, as far as the
    /// page's 480 points allow.
    private var asideWidth: CGFloat {
        min(Self.width + covered, max(Self.width, windowWidth - Self.besideList))
    }

    /// Called with the window's columns each time the list is laid out. Answers whether they are built as expected.
    func found(_ columns: NSSplitViewController?) -> Bool {
        self.columns = columns
        guard let columns = shownColumns, place(of: 0, in: columns) != nil, place(of: 2, in: columns) != nil else {
            return false
        }
        measure(columns)
        fit()
        return true
    }

    /// Called as the sidebar starts to hide or return.
    func sidebarSlides(aside: Bool, windowWidth: CGFloat) {
        self.aside = aside
        self.windowWidth = windowWidth
        guard let columns = shownColumns else {
            fit()
            return
        }
        measure(columns)
        let (sidebar, list) = (columns.splitViewItems[0], columns.splitViewItems[1])
        // The window keeps its size: AppKit would otherwise make it narrower or wider by the sidebar's width.
        sidebar.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        list.minimumThickness = Self.width
        list.maximumThickness = asideWidth
        if pin == nil, let place = place(of: 2, in: columns) {
            pin = place.leadingAnchor.constraint(equalTo: columns.splitView.leadingAnchor, constant: place.frame.minX)
            pin?.isActive = true
        }
        widths = Self.width...asideWidth
        slides += 1
    }

    /// Called when the window, the page or the sidebar changes while nothing slides.
    func rest(aside: Bool, windowWidth: CGFloat) {
        self.aside = aside
        self.windowWidth = windowWidth
        if let columns = shownColumns { measure(columns) }
        fit()
    }

    func settle() {
        settled = slides
        pin?.isActive = false
        pin = nil
        if let columns = shownColumns { measure(columns) }
        fit()
    }

    /// Holds the list at one width, unless the page is pinned while the sidebar slides.
    private func fit() {
        guard pin == nil else { return }
        let width = aside ? asideWidth : Self.width
        if widths != width...width { widths = width...width }
    }

    private var shownColumns: NSSplitViewController? {
        guard let columns, columns.splitViewItems.count == 3, columns.splitView.window != nil else { return nil }
        return columns
    }

    /// Reads what the sidebar covers from its place while it rests, shown or hidden: AppKit keeps the place's width
    /// while the sidebar is hidden, and only an animation leaves it part way.
    private func measure(_ columns: NSSplitViewController) {
        guard slides == settled, let sidebar = place(of: 0, in: columns),
              !columns.splitViewItems[0].isCollapsed || sidebar.isHidden else { return }
        covered = sidebar.frame.width
    }

    /// The view the split view lays out for an item, which holds the item's own view. Not API (see `PrivateStructure`).
    private func place(of item: Int, in columns: NSSplitViewController) -> NSView? {
        let view = columns.splitViewItems[item].viewController.view
        return columns.splitView.subviews.first { view.isDescendant(of: $0) }
    }
}

extension View {
    func listColumn() -> some View {
        modifier(ListColumnWidth())
    }

    /// Builds the list column only once it knows the title bar above it, keeping the column's width meanwhile. On
    /// macOS 27, a list built before then, as the window changes from two columns to three, gets neither the blur
    /// under its bar at the top nor the margin of its scroll bar.
    @ViewBuilder
    func builtWithItsTitleBar() -> some View {
        if #available(macOS 27, *) {
            BuiltWithItsTitleBar(column: self)
        } else {
            self
        }
    }
}

@available(macOS 27, *)
private struct BuiltWithItsTitleBar<Column: View>: View {
    @Environment(ListColumn.self) private var listColumn
    let column: Column
    @State private var knowsItsTitleBar = false

    var body: some View {
        Group {
            if knowsItsTitleBar {
                column
            } else {
                Color.clear
            }
        }
        .onGeometryChange(for: Bool.self) { $0.safeAreaInsets.top > 0 } action: { known in
            if known { knowsItsTitleBar = true }
        }
        .navigationSplitViewColumnWidth(
            min: listColumn.widths.lowerBound, ideal: listColumn.widths.lowerBound, max: listColumn.widths.upperBound
        )
    }
}

private struct ListColumnWidth: ViewModifier {
    @Environment(ListColumn.self) private var column

    func body(content: Content) -> some View {
        content
            .background(SlideWatch(column: column, slides: column.slides))
            .navigationSplitViewColumnWidth(
                min: column.widths.lowerBound, ideal: column.widths.lowerBound, max: column.widths.upperBound
            )
    }
}

/// Hands `ListColumn` the window's columns, and tells it once they have stopped changing after the sidebar slid:
/// AppKit says nothing when the animation ends.
private struct SlideWatch: NSViewRepresentable {
    let column: ListColumn
    let slides: Int

    func makeNSView(context: Context) -> Watch {
        Watch(column: column)
    }

    func updateNSView(_ nsView: Watch, context: Context) {
        if slides != column.settled { nsView.needsLayout = true }
    }

    final class Watch: NSView {
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
            if let splitView = enclosingSplitView {
                if column.found(splitView.delegate as? NSSplitViewController) { PrivateStructure.found(.listColumn) }
                observe(splitView)
            }
            PrivateStructure.check(.listColumn)
            settleSoon()
        }

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
            settleSoon()
        }

        private func settleSoon() {
            guard column.slides != column.settled else { return }
            pending?.cancel()
            pending = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, let column = self?.column, column.slides != column.settled else { return }
                column.settle()
            }
        }

        /// The split view of the window's columns, which SwiftUI builds with an `NSSplitViewController` as its
        /// delegate. This structure is not API (see `PrivateStructure`).
        private var enclosingSplitView: NSSplitView? {
            var view = superview
            while let current = view {
                if let splitView = current as? NSSplitView, splitView.delegate is NSSplitViewController {
                    return splitView
                }
                view = current.superview
            }
            return nil
        }
    }
}
