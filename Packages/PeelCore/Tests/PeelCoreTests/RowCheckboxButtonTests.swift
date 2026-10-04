import AppKit
@testable import PeelCore
import Testing

@MainActor
struct RowCheckboxButtonTests {
    @Test func showMenuOpensWhatARightClickOnItOpensEvenWhileItCannotBeChanged() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let row = RightClicks(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        window.contentView = row
        let checkbox = RowCheckboxButton(frame: NSRect(x: 20, y: 30, width: 16, height: 16))
        checkbox.setButtonType(.switch)
        checkbox.isEnabled = false
        row.addSubview(checkbox)

        #expect(checkbox.accessibilityPerformShowMenu())
        #expect(row.clicks.isEmpty)
        let deadline = Date(timeIntervalSinceNow: 2)
        while row.clicks.isEmpty, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        #expect(row.clicks == [NSPoint(x: 28, y: 38)])
        #expect(checkbox.state == .off)
    }

    @Test func showMenuOpensNothingOutsideAWindow() {
        let checkbox = RowCheckboxButton(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        checkbox.setButtonType(.switch)
        #expect(!checkbox.accessibilityPerformShowMenu())
    }
}

private final class RightClicks: NSView {
    var clicks: [NSPoint] = []

    override func rightMouseDown(with event: NSEvent) {
        clicks.append(event.locationInWindow)
    }
}
