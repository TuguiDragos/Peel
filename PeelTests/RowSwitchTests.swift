import AppKit
@testable import Peel
import SwiftUI
import Testing

@MainActor
struct RowSwitchTests {
    private final class Width {
        var value: CGFloat = 0
    }

    private static let title = "A switch whose title runs long, as titles do in German and Romanian"

    @Test func theSwitchAtTheEndOfARowLeavesItsTitleWhole() async {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let needed = (Self.title as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
        let width = Width()
        let form = Form {
            HStack(spacing: 10) {
                Text(verbatim: Self.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width.value = $0 }
                Spacer(minLength: 8)
                RowSwitch(title: Text(verbatim: Self.title), isOn: .constant(false))
            }
        }
        .formStyle(.grouped)
        .frame(width: needed + 160)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: needed + 200, height: 120), styleMask: [.titled],
            backing: .buffered, defer: true
        )
        window.contentView = NSHostingView(rootView: form)

        for _ in 0..<200 where width.value == 0 {
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(width.value > 0)
        #expect(width.value + 1 >= needed)
    }
}
