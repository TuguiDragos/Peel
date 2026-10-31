import AppKit
@testable import Peel
import Testing

@MainActor
struct FloorConstraintsTests {
    private func window() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false
        )
        window.contentView = NSView()
        return window
    }

    @Test func aWindowIsNeverMadeSmallerThanItsFloor() throws {
        let window = window()
        FloorConstraints().hold(CGSize(width: 1307, height: 756), in: window)
        window.setContentSize(NSSize(width: 900, height: 500))
        window.layoutIfNeeded()
        let content = try #require(window.contentView)
        #expect(content.frame.width >= 1307)
        #expect(content.frame.height >= 756)
    }

    @Test func aNewFloorTakesThePlaceOfTheOldOne() throws {
        let window = window()
        let floor = FloorConstraints()
        floor.hold(CGSize(width: 1307, height: 756), in: window)
        floor.hold(CGSize(width: 1000, height: 600), in: window)
        window.setContentSize(NSSize(width: 900, height: 500))
        window.layoutIfNeeded()
        let content = try #require(window.contentView)
        #expect(content.frame.size == CGSize(width: 1000, height: 600))
    }

    @Test func aNewContentViewTakesTheFloorWithIt() throws {
        let window = window()
        let floor = FloorConstraints()
        floor.hold(CGSize(width: 1307, height: 756), in: window)
        window.contentView = NSView()
        floor.hold(CGSize(width: 1307, height: 756), in: window)
        window.setContentSize(NSSize(width: 900, height: 500))
        window.layoutIfNeeded()
        let content = try #require(window.contentView)
        #expect(content.frame.size == CGSize(width: 1307, height: 756))
    }
}
