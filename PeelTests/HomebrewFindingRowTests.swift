import AppKit
@testable import Peel
import SwiftUI
import Testing

@MainActor
struct HomebrewFindingRowTests {
    private final class Frame {
        var size: CGSize = .zero
    }

    private static let line = "Command-line tools using this file may accept forged TLS certificates:"

    @Test func aLineOfHomebrewsTextUnderItsSummaryIsShownWhole() async {
        let frame = Frame()
        let list = List {
            HomebrewFindingLine(line: Self.line)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { frame.size = $0 }
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: ListColumn.width, height: 400), styleMask: [.titled],
            backing: .buffered, defer: true
        )
        window.contentView = NSHostingView(rootView: list)

        for _ in 0..<200 where frame.size == .zero {
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(5))
        }

        let caption = NSFont.preferredFont(forTextStyle: .caption1).pointSize
        let needed = (Self.line as NSString).boundingRect(
            with: CGSize(width: frame.size.width, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: caption, weight: .regular)]
        ).height
        #expect(frame.size.width > 0)
        #expect(frame.size.height + 1 >= needed.rounded(.up))
    }
}
