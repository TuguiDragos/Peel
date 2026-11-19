import AppKit
import Foundation
@testable import Peel
import PeelCore
import SwiftUI
import Testing

@MainActor
struct SpaceStepTests {
    private final class Frame {
        var size: CGSize = .zero
    }

    private static let step = "Drag an older version to the Trash in Finder, or use the .NET Uninstall Tool, and drag every other older version you no longer need to the Trash in Finder as well."

    @Test func aLongStepInARowShowsEveryLine() async {
        let frame = Frame()
        let page = List {
            Section {
                SpaceStep(
                    step: LocalizedStringResource(stringLiteral: Self.step),
                    note: "Finder asks for an administrator password for a version in /usr/local."
                )
                .onGeometryChange(for: CGSize.self) { $0.size } action: { frame.size = $0 }
            } header: {
                Text(verbatim: "How to Free It")
            }
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560), styleMask: [.titled],
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

    @Test func eachStepSaysWhereAndItsNoteSaysWhatItDoes() throws {
        let messages = try #require(SpaceItem.words(for: "messages"))
        #expect(messages.hint?.key == "Messages > Settings > General > Keep Messages")
        #expect(messages.hintNote?.key == "A shorter time deletes older conversations along with their attachments.")
        for id in ["icloud", "homebrew-data", "tex-live", "dotnet-sdks"] {
            #expect(SpaceItem.words(for: id)?.hint != nil && SpaceItem.words(for: id)?.hintNote != nil, "\(id)")
        }
    }
}
