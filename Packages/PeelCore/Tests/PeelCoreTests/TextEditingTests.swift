import AppKit
@testable import PeelCore
import Testing

@MainActor
struct TextEditingTests {
    /// A text field being typed in makes its window's field editor the first responder, and while it is, a command
    /// whose key is also a text editing key leaves that key to the text.
    @Test func followsTheFieldEditorOfTheWindowItWatches() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 200, height: 24))
        let label = NSTextField(labelWithString: "Name")
        window.contentView?.addSubview(field)
        window.contentView?.addSubview(label)
        let editing = TextEditing()
        editing.follow(window)
        #expect(!editing.isEditing)

        window.makeFirstResponder(field)
        #expect(editing.isEditing)

        window.makeFirstResponder(nil)
        #expect(!editing.isEditing)

        window.makeFirstResponder(field)
        editing.follow(nil)
        #expect(!editing.isEditing)
    }

    /// A window that is not key can still say it became key, as the list macOS shows to complete a word does
    /// while a field is typed in. The field's window is still the key one, so the text is still being edited.
    @Test func asksWhichWindowIsKeyWheneverOneSaysItBecameKey() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 200, height: 24))
        window.contentView?.addSubview(field)
        window.makeFirstResponder(field)
        let completions = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [],
            backing: .buffered,
            defer: true
        )
        let key = KeyWindow(window)
        let editing = TextEditing(keyWindow: { key.window })
        editing.start()
        #expect(editing.isEditing)

        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: completions)
        #expect(editing.isEditing)

        key.window = completions
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: completions)
        #expect(!editing.isEditing)

        key.window = nil
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: completions)
        #expect(!editing.isEditing)
    }

    /// Undo and Redo act on the typing in the field being edited, and say what they would take back in the
    /// words of the field's undo manager.
    @Test func undoesAndRedoesTheTypingInTheFieldBeingEdited() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 200, height: 24))
        window.contentView?.addSubview(field)
        let editing = TextEditing()
        editing.follow(window)
        #expect(editing.typing == nil)

        window.makeFirstResponder(field)
        let editor = try #require(window.firstResponder as? NSTextView)
        let undoManager = try #require(editor.undoManager)
        let nothingTyped = TextEditing.Typing(
            undo: undoManager.undoMenuItemTitle, redo: undoManager.redoMenuItemTitle, canUndo: false, canRedo: false
        )
        #expect(editing.typing == nothingTyped)

        undoManager.beginUndoGrouping()
        editor.insertText("Xcode", replacementRange: editor.selectedRange())
        undoManager.endUndoGrouping()
        #expect(editor.string == "Xcode")
        #expect(editing.typing?.canUndo == true)
        #expect(editing.typing?.undo == undoManager.undoMenuItemTitle)

        editing.undo()
        #expect(editor.string.isEmpty)
        #expect(editing.typing?.canUndo == false)
        #expect(editing.typing?.canRedo == true)

        editing.redo()
        #expect(editor.string == "Xcode")
        #expect(editing.typing?.canUndo == true)
        #expect(editing.typing?.canRedo == false)

        window.makeFirstResponder(nil)
        #expect(editing.typing == nil)
    }

    /// Only text that can be typed in counts: selecting the words of a label, or a list holding the focus, edits
    /// nothing.
    @Test func countsOnlyTextThatCanBeTypedIn() {
        let editable = NSTextView()
        let readOnly = NSTextView()
        readOnly.isEditable = false
        #expect(TextEditing.edits(editable))
        #expect(!TextEditing.edits(readOnly))
        #expect(!TextEditing.edits(NSTableView()))
        #expect(!TextEditing.edits(nil))
    }
}
