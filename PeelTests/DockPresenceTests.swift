import AppKit
@testable import Peel
import Testing

struct DockPresenceTests {
    @Test func leavesTheDockOnlyWhenAskedWhileInTheMenuBarWithNoWindowOpen() {
        #expect(!DockPresence.belongsInTheDock(hidesFromDock: true, showsInMenuBar: true, hasAWindowOpen: false))
        #expect(DockPresence.belongsInTheDock(hidesFromDock: true, showsInMenuBar: true, hasAWindowOpen: true))
        #expect(DockPresence.belongsInTheDock(hidesFromDock: true, showsInMenuBar: false, hasAWindowOpen: false))
        #expect(DockPresence.belongsInTheDock(hidesFromDock: false, showsInMenuBar: true, hasAWindowOpen: false))
    }

    @Test func countsAMinimizedWindowButNeitherOneClosingNorOneThatCantBeMain() {
        let open = window(visible: true)
        #expect([open].containsAnOpenWindow())
        #expect([window(minimized: true)].containsAnOpenWindow())
        #expect(![open, window(visible: true, mayBeMain: false), window()].containsAnOpenWindow(besides: open))
    }

    private func window(visible: Bool = false, minimized: Bool = false, mayBeMain: Bool = true) -> NSWindow {
        let window = StandInWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: true)
        window.onScreen = visible
        window.minimized = minimized
        window.mayBeMain = mayBeMain
        return window
    }
}

/// Never ordered in, so the window server makes no window for it.
private final class StandInWindow: NSWindow {
    var onScreen = false
    var minimized = false
    var mayBeMain = true

    override var isVisible: Bool { onScreen }
    override var isMiniaturized: Bool { minimized }
    override var canBecomeMain: Bool { mayBeMain }
}
