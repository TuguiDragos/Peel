import AppKit

/// Keeps Peel out of the Dock while it shows in the menu bar with no window open, when the person chose so in
/// Settings, and brings it back as soon as one of its windows opens.
final class DockPresence {
    static let shared = DockPresence()

    private var observers: [any NSObjectProtocol] = []

    private init() {}

    static func belongsInTheDock(hidesFromDock: Bool, showsInMenuBar: Bool, hasAWindowOpen: Bool) -> Bool {
        !hidesFromDock || !showsInMenuBar || hasAWindowOpen
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: nil) { note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let window, window.countsAsOpen else { return }
                DockPresence.shared.update(closing: window)
            }
        })
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didChangeOcclusionStateNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { note in
                let window = note.object as? NSWindow
                MainActor.assumeIsolated {
                    guard let window else { return }
                    DockPresence.shared.comeBack(for: window)
                }
            })
        }
        update()
    }

    /// Puts Peel in the Dock or takes it out, as the rule says for the windows open now but `closing`.
    func update(closing: NSWindow? = nil) {
        guard !observers.isEmpty else { return }
        let defaults = UserDefaults.standard
        let inTheDock = Self.belongsInTheDock(
            hidesFromDock: defaults.bool(forKey: SettingsKey.hidesFromDock),
            showsInMenuBar: defaults.bool(forKey: SettingsKey.showsInMenuBar),
            hasAWindowOpen: NSApp.windows.containsAnOpenWindow(besides: closing)
        )
        let policy: NSApplication.ActivationPolicy = inTheDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    private func comeBack(for window: NSWindow) {
        guard window.canBecomeMain, window.isVisible, NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}

extension NSWindow {
    /// Whether the window is open for the person: minimized, or on screen and able to be main. AppKit answers that a
    /// minimized window can't be main, and the menu bar panel and the menu bar item's own window never can.
    var countsAsOpen: Bool { isMiniaturized || canBecomeMain && isVisible }
}

extension [NSWindow] {
    func containsAnOpenWindow(besides closing: NSWindow? = nil) -> Bool {
        contains { $0 !== closing && $0.countsAsOpen }
    }
}
