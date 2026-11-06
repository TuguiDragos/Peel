import AppKit
@testable import Peel
import SwiftUI
import Testing

@MainActor
struct EmptyStateActionsTests {
    private final class Frames {
        var all: [String: CGRect] = [:]
    }

    private struct Buttons: View {
        let frames: Frames
        let tag: String

        var body: some View {
            ForEach(["Open Home", "Copy Details", "Help"], id: \.self) { title in
                Button(title) {}
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                        frames.all["\(tag) \(title)"] = $0
                    }
            }
        }
    }

    @Test func buttonsThatFitStandAsAnEmptyStateSpacesItsOwn() async {
        let frames = Frames()
        let page = VStack {
            ContentUnavailableView {
                Label(String("Own"), systemImage: "folder")
            } actions: {
                Buttons(frames: frames, tag: "own")
            }
            ContentUnavailableView {
                Label(String("Wrapped"), systemImage: "folder")
            } actions: {
                EmptyStateActions { Buttons(frames: frames, tag: "wrapped") }
            }
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled],
            backing: .buffered, defer: true
        )
        window.contentView = NSHostingView(rootView: page)

        for _ in 0..<200 where frames.all.count < 6 {
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(5))
        }

        func gap(_ tag: String) -> CGFloat? {
            guard let first = frames.all["\(tag) Open Home"], let second = frames.all["\(tag) Copy Details"] else {
                return nil
            }
            return second.minX - first.maxX
        }
        #expect(gap("own") != nil)
        #expect(gap("wrapped") == gap("own"))
        #expect(frames.all["wrapped Open Home"]?.minY == frames.all["wrapped Help"]?.minY)
    }
}
