import AppKit
@testable import Peel
import SwiftUI
import Testing

@MainActor
struct NoProjectFoldersTests {
    @Test func itsButtonsFitTheListColumn() {
        let suggested = ["Developer", "Projects", "Code", "src"].map { URL(filePath: "/Users/Shared/\($0)") }
        let host = NSHostingController(rootView: NoProjectFolders(suggested: suggested, choose: {}, add: { _ in }))
        let column = ListColumn.width

        let size = host.sizeThatFits(in: CGSize(width: column, height: 2_000))

        #expect(size.width <= column)
    }

    @Test func manyUsualPlacesScrollUnderTheMainButton() async {
        let suggested = (1...50).map { URL(filePath: "/Users/Shared/Place \($0)") }
        let column = CGSize(width: ListColumn.width, height: 700)
        let host = NSHostingView(
            rootView: NoProjectFolders(suggested: suggested, choose: {}, add: { _ in })
                .frame(width: column.width, height: column.height)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: column), styleMask: [.titled], backing: .buffered, defer: true
        )
        window.contentView = host

        for _ in 0..<200 where Self.scrolling(in: host).isEmpty {
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(5))
        }

        let scrolling = Self.scrolling(in: host)
        #expect(!scrolling.isEmpty)
        for view in scrolling {
            let frame = view.convert(view.bounds, to: host)
            let fromTop = host.isFlipped ? frame.minY : host.bounds.height - frame.maxY
            #expect(host.bounds.contains(frame))
            #expect(fromTop >= column.height / 4)
        }
    }

    private static func scrolling(in view: NSView) -> [NSScrollView] {
        let own = (view as? NSScrollView).flatMap { scroll in
            (scroll.documentView?.frame.height ?? 0) > scroll.contentView.bounds.height + 1 ? [scroll] : nil
        } ?? []
        return own + view.subviews.flatMap(scrolling)
    }
}
