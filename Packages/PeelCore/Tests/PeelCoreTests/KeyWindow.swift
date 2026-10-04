import AppKit

/// The window a test says is key, read each time a window says it became key or stopped being key.
@MainActor
final class KeyWindow {
    var window: NSWindow?

    init(_ window: NSWindow?) {
        self.window = window
    }
}
