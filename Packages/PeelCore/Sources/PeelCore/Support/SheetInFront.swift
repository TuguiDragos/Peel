public import AppKit
public import Observation

/// Whether the key window is a sheet, such as a question or a sheet a page opened. The window under a sheet takes no
/// command from the menus, so the commands that act on a page are turned off meanwhile and its keys reach the sheet.
@MainActor
@Observable
public final class SheetInFront {
    public private(set) var isShowing = false
    @ObservationIgnored private let keyWindow: @MainActor () -> NSWindow?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    public init(keyWindow: @escaping @MainActor () -> NSWindow? = { NSApp.keyWindow }) {
        self.keyWindow = keyWindow
    }

    /// Follows whichever window is key from now on.
    public func start() {
        guard observers.isEmpty else { return }
        observers = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.read() }
            }
        }
        read()
    }

    private func read() {
        isShowing = keyWindow()?.sheetParent != nil
    }
}
