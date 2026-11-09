import AppKit
@testable import Peel
import PeelCore
import Testing

@MainActor
struct AboutIconTests {
    @Test func closingAboutWhileTheFaceIsAwakeLetsTheIconGo() async throws {
        weak var shown: AboutIconView?
        do {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 120, height: 120), styleMask: [.titled], backing: .buffered,
                defer: true
            )
            window.isReleasedWhenClosed = false
            let icon = AboutIconView()
            window.contentView?.addSubview(icon)
            icon.answer(AboutIcon.Reaction(start: CACurrentMediaTime(), answer: .wake, reducingMotion: false))
            shown = icon
            window.close()
        }
        for _ in 0..<200 where shown != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(shown == nil)
    }
}
