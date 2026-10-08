import AppKit
import SwiftUI

/// The window a view is in, outside SwiftUI's state, since it is set while SwiftUI updates the view.
final class HostWindow {
    weak var value: NSWindow?
}

struct HostWindowReader: NSViewRepresentable {
    let host: HostWindow
    /// Called once the view is in a window.
    var found: @MainActor () -> Void = {}

    func makeNSView(context: Context) -> Reader {
        Reader(host: host, found: found)
    }

    func updateNSView(_ nsView: Reader, context: Context) {}

    final class Reader: NSView {
        let host: HostWindow
        let found: @MainActor () -> Void

        init(host: HostWindow, found: @escaping @MainActor () -> Void) {
            self.host = host
            self.found = found
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            host.value = window
            // On a later turn, since what it changes is SwiftUI state and this can run inside SwiftUI's update.
            if window != nil {
                Task { found() }
            }
        }
    }
}
