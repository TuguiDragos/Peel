import AppKit
@testable import Peel
import SwiftUI
import Testing

@MainActor
struct ListEditingButtonsTests {
    private final class Heights {
        var add: CGFloat = 0
        var remove: CGFloat = 0
    }

    @Test func theButtonsAtTheFootOfASettingsListAreAsHighAsTheHIGsSmallestControl() async {
        let heights = Heights()
        let form = Form {
            Section {
                Text(verbatim: "org.example.folder")
                ListEditingButtons {
                    Button("Add Folder…", systemImage: "plus") {}
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights.add = $0 }
                    Button("Remove", systemImage: "minus") {}
                        .disabled(true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights.remove = $0 }
                }
            }
        }
        .formStyle(.grouped)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.titled],
            backing: .buffered, defer: true
        )
        window.contentView = NSHostingView(rootView: form)

        for _ in 0..<200 where heights.add == 0 || heights.remove == 0 {
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(heights.add >= 20)
        #expect(heights.remove >= 20)
    }
}
