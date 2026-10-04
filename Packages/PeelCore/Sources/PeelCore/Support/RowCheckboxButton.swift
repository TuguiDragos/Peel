public import AppKit

/// AppKit's checkbox for a row of a list. When VoiceOver asks for its menu, it opens what a right click on it opens,
/// the row's menu, even while the checkbox cannot be changed.
public final class RowCheckboxButton: NSButton {
    public override func accessibilityPerformShowMenu() -> Bool {
        guard window != nil else { return false }
        // From the run loop, as AppKit opens a view's menu, so VoiceOver has its answer before the menu holds the
        // main thread.
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated { self?.rightClick() }
        }
        return true
    }

    private func rightClick() {
        guard let window else { return }
        let center = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
        guard let event = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: center,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else { return }
        rightMouseDown(with: event)
    }
}
