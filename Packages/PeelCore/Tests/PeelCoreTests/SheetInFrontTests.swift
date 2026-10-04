import AppKit
@testable import PeelCore
import Testing

@MainActor
struct SheetInFrontTests {
    @Test func isShowingWhileTheKeyWindowIsASheet() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let key = KeyWindow(window)
        let sheetInFront = SheetInFront(keyWindow: { key.window })
        sheetInFront.start()
        #expect(!sheetInFront.isShowing)

        window.beginSheet(sheet)
        key.window = sheet
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: sheet)
        #expect(sheetInFront.isShowing)

        window.endSheet(sheet)
        key.window = window
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        #expect(!sheetInFront.isShowing)

        key.window = nil
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        #expect(!sheetInFront.isShowing)
    }
}
