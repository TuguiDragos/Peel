import AppKit
import PeelCore
import SwiftUI

extension FocusedValues {
    @Entry var removalHistory: RemovalHistoryStore?
    @Entry var selectedTool: Binding<Tool>?
    /// Set to true to put the cursor in the column's search field. It is a binding, not a closure, because
    /// `FocusedBinding` carries bindings, the same way `selectedTool` serves the tool shortcuts.
    @Entry var searchField: Binding<Bool>?
    /// The page's Move to Trash, offered as a menu item as well as a button, because the bar at the bottom of the
    /// window can be off screen.
    @Entry var moveToTrash: MenuCommand?
}

/// The Rescan and Stop commands of the page in front, for the View menu. A focused value set by a toolbar item
/// does not reach the menu bar, so `RescanButton` registers them here instead.
@Observable
final class PageCommands {
    static let shared = PageCommands()
    private(set) var owner: UUID?
    private(set) var rescan: MenuCommand?
    private(set) var stop: MenuCommand?

    func offer(rescan: MenuCommand, stop: MenuCommand?, from owner: UUID) {
        self.owner = owner
        self.rescan = rescan
        self.stop = stop
    }

    /// Clears the commands, unless another page has offered its own since.
    func withdraw(from owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        rescan = nil
        stop = nil
    }
}

/// What a menu item runs on the page in front, as the page's own button would.
struct MenuCommand {
    let title: LocalizedStringResource
    let isEnabled: Bool
    let perform: () -> Void
}

struct PeelCommands: Commands {
    /// What the Applications toolbar's two menus act on, so the menu bar can offer them as well.
    let library: AppLibrary
    let homebrew: HomebrewLibrary
    let textEditing: TextEditing
    let sheetInFront: SheetInFront
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.removalHistory) private var history
    @FocusedBinding(\.selectedTool) private var selectedTool
    @FocusedBinding(\.searchField) private var searchField
    @FocusedValue(\.moveToTrash) private var moveToTrash

    var body: some Commands {
        // Undo takes back the typing while text is being edited, and otherwise the last removal, as Finder's
        // Undo does after a move to the Trash.
        CommandGroup(replacing: .undoRedo) {
            if let typing = textEditing.typing {
                Button(typing.undo) { textEditing.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!typing.canUndo)
                Button(typing.redo) { textEditing.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!typing.canRedo)
            } else {
                Button {
                    Task { await history?.undoLastRemoval() }
                } label: {
                    if let name = history?.undoName {
                        Text("Undo Remove \(name)")
                    } else {
                        Text("Undo")
                    }
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(history?.undoName == nil || history?.isRestoring == true || sheetInFront.isShowing)
                Button("Redo") {}
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(true)
            }
        }

        CommandGroup(replacing: .appInfo) {
            Button("About Peel") {
                openWindow(id: AboutView.windowID)
            }
        }

        // Replaces the standard Help item, which in an app with no help book only shows an alert that help is
        // not available. Peel explains itself in the notes beside what they explain.
        CommandGroup(replacing: .help) {
            Button("Peel on GitHub") { NSWorkspace.shared.open(Links.repository) }
            Button("Report an Issue\u{2026}") { NSWorkspace.shared.open(Links.report) }
        }

        CommandGroup(after: .newItem) {
            Divider()
            Button(String(localized: moveToTrash?.title ?? "Move to Trash")) { moveToTrash?.perform() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(moveToTrash?.isEnabled != true || textEditing.isEditing || sheetInFront.isShowing)
            Divider()
            Menu("Export List of Apps") {
                ExportListMenuContent(library: library, homebrew: homebrew)
            }
            .disabled(!InventoryExport.canExport(library: library, homebrew: homebrew) || sheetInFront.isShowing)
        }

        CommandGroup(before: .textEditing) {
            Button("Find") { searchField = true }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(searchField == nil || sheetInFront.isShowing)
            Divider()
        }

        // The tools follow the sidebar's order and groups, so ⌘1 to ⌘9 match the first nine tools there.
        CommandGroup(before: .sidebar) {
            let rescan = PageCommands.shared.rescan
            Button(String(localized: rescan?.title ?? "Rescan")) { rescan?.perform() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(rescan?.isEnabled != true || sheetInFront.isShowing)
            let stop = PageCommands.shared.stop
            Button(String(localized: stop?.title ?? "Stop")) { stop?.perform() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(stop?.isEnabled != true || sheetInFront.isShowing)
            Menu("Sort and Filter") {
                AppListMenuContent(library: library)
            }
            .disabled(selectedTool != .applications || sheetInFront.isShowing)
            Divider()
            let ordered = Tool.Group.allCases.flatMap(\.tools)
            ForEach(Tool.Group.allCases, id: \.self) { group in
                ForEach(group.tools) { tool in
                    let index = ordered.firstIndex(of: tool) ?? ordered.count
                    Button {
                        selectedTool = tool
                    } label: {
                        Text(tool.title)
                    }
                    .keyboardShortcut(
                        index < 9
                            ? KeyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                            : nil
                    )
                    .disabled(selectedTool == nil || sheetInFront.isShowing)
                }
                Divider()
            }
        }
    }
}

