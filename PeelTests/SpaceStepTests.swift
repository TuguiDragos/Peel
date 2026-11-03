import AppKit
@testable import Peel
import SwiftUI
import Testing

@MainActor
struct SpaceStepTests {
    private final class Frame {
        var size: CGSize = .zero
    }

    private static let step = "Remove a version with a newer one beside it by dragging its folder to the Trash in Finder, or with Microsoft’s .NET Uninstall Tool. Finder asks for an administrator’s password for a version in /usr/local."

    @Test func aLongStepBesideItsLabelShowsEveryLine() async {
        guard #available(macOS 27, *) else { return }
        let frame = Frame()
        let page = List {
            Section {
                LabeledContent {
                    SpaceStep(step: LocalizedStringResource(stringLiteral: Self.step))
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { frame.size = $0 }
                } label: {
                    Text(verbatim: "How to free it")
                }
            }
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560), styleMask: [.titled],
            backing: .buffered, defer: true
        )
        window.contentView = NSHostingView(rootView: page)

        for _ in 0..<200 where frame.size == .zero {
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(5))
        }

        let needed = (Self.step as NSString).boundingRect(
            with: CGSize(width: frame.size.width, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.preferredFont(forTextStyle: .callout)]
        ).height
        #expect(frame.size.width > 0)
        #expect(frame.size.height + 1 >= needed.rounded(.up))
    }
}
