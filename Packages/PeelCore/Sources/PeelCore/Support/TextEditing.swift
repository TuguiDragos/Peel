public import AppKit
public import Observation

/// Whether text is being typed in the key window. A key equivalent reaches the menus before the text system, so a
/// command whose key also edits text, such as Command-Delete, is turned off meanwhile and the key reaches the text.
@MainActor
@Observable
public final class TextEditing {
    public private(set) var isEditing = false
    @ObservationIgnored private let keyWindow: @MainActor () -> NSWindow?
    @ObservationIgnored private var responder: NSKeyValueObservation?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    public init(keyWindow: @escaping @MainActor () -> NSWindow? = { NSApp.keyWindow }) {
        self.keyWindow = keyWindow
    }

    /// Follows whichever window is key from now on. The window a notification names is not asked: the list macOS
    /// shows to complete a word says it became key while the field's window stays the key one.
    public func start() {
        guard observers.isEmpty else { return }
        observers = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.follow(self.keyWindow())
                }
            }
        }
        follow(keyWindow())
    }

    func follow(_ window: NSWindow?) {
        // `firstResponder` is KVO compliant (`NSWindow.h`), and AppKit changes it on the main thread.
        responder = window?.observe(\.firstResponder, options: [.initial, .new]) { [weak self] window, _ in
            MainActor.assumeIsolated { self?.isEditing = Self.edits(window.firstResponder) }
        }
        if window == nil {
            isEditing = false
        }
    }

    /// A text field being typed in answers with its field editor, an `NSTextView`, as the first responder.
    static func edits(_ responder: NSResponder?) -> Bool {
        (responder as? NSText)?.isEditable == true
    }
}
