public import AppKit
public import Observation

/// Whether text is being typed in the key window. A key equivalent reaches the menus before the text system, so a
/// command whose key also edits text, such as Command-Delete, is turned off meanwhile and the key reaches the text.
@MainActor
@Observable
public final class TextEditing {
    public private(set) var isEditing = false
    /// What Undo and Redo would do to the text being typed, or nil while nothing is.
    public private(set) var typing: Typing?
    @ObservationIgnored private let keyWindow: @MainActor () -> NSWindow?
    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private var responder: NSKeyValueObservation?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var followedUndoManager: UndoManager?
    @ObservationIgnored private var undoObservers: [any NSObjectProtocol] = []

    /// The items Undo and Redo show for the text being typed, titled by its undo manager as the standard items are.
    public struct Typing: Equatable, Sendable {
        public let undo: String
        public let redo: String
        public let canUndo: Bool
        public let canRedo: Bool
    }

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
        self.window = window
        // `firstResponder` is KVO compliant (`NSWindow.h`), and AppKit changes it on the main thread.
        responder = window?.observe(\.firstResponder, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.read() }
        }
        if window == nil {
            read()
        }
    }

    public func undo() {
        editedUndoManager?.undo()
    }

    public func redo() {
        editedUndoManager?.redo()
    }

    private var editedUndoManager: UndoManager? {
        guard let responder = window?.firstResponder, Self.edits(responder) else { return nil }
        return responder.undoManager
    }

    private func read() {
        isEditing = Self.edits(window?.firstResponder)
        let undoManager = editedUndoManager
        typing = undoManager.map {
            Typing(undo: $0.undoMenuItemTitle, redo: $0.redoMenuItemTitle, canUndo: $0.canUndo, canRedo: $0.canRedo)
        }
        follow(undoManager)
    }

    /// Reads the titles again whenever the undo manager of the text being typed records, undoes or redoes
    /// something. That undo manager is its window's, which AppKit uses on the main thread.
    private func follow(_ undoManager: UndoManager?) {
        guard undoManager !== followedUndoManager else { return }
        undoObservers.forEach(NotificationCenter.default.removeObserver)
        followedUndoManager = undoManager
        guard let undoManager else {
            undoObservers = []
            return
        }
        let names: [Notification.Name] = [
            .NSUndoManagerCheckpoint, .NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange,
            .NSUndoManagerDidRedoChange,
        ]
        undoObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: undoManager, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.read() }
            }
        }
    }

    /// A text field being typed in answers with its field editor, an `NSTextView`, as the first responder.
    static func edits(_ responder: NSResponder?) -> Bool {
        (responder as? NSText)?.isEditable == true
    }
}
