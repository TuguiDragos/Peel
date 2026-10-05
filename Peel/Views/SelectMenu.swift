import PeelCore
import SwiftUI

/// Select Recommended, Select All and Deselect All for one list, or from a tool's toolbar for every page it lists.
/// Select All asks first when it would also select what Peel does not recommend.
struct SelectMenu: View {
    let list: SelectableRows<URL>
    let selection: any RowSelection
    private let scope: Scope
    /// Reads what the list does not know yet, such as Space's areas never opened, before a command runs. Nil once
    /// the list is whole. False when the reading was stopped, and the command is then dropped.
    private let reading: (() async -> Bool)?
    private let isDisabled: Bool
    @State private var notRecommended: Int?
    /// A command chosen before the list was whole, which runs once it is.
    @State private var waiting: Command?

    private enum Command {
        case recommended, all, none
    }

    private enum Scope {
        /// The list's name, as the page shows it, which the question names. With nothing a click can select, the
        /// menu draws nothing.
        case list(Text)
        /// How many pages Select All reaches, which the question counts.
        case pages(Int)
    }

    init(list: SelectableRows<URL>, place: Text, selection: any RowSelection) {
        self.list = list
        self.selection = selection
        scope = .list(place)
        reading = nil
        isDisabled = false
    }

    init(
        pages: Int,
        list: SelectableRows<URL>,
        selection: any RowSelection,
        reading: (() async -> Bool)?,
        isDisabled: Bool
    ) {
        self.list = list
        self.selection = selection
        scope = .pages(pages)
        self.reading = reading
        self.isDisabled = isDisabled
    }

    var body: some View {
        Group {
            switch scope {
            case .list:
                if !list.selectable.isEmpty {
                    Menu("Select") { commands }
                        .menuStyle(.button)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .fixedSize()
                }
            case .pages:
                Menu {
                    commands
                } label: {
                    ToolbarMenuLabel(title: "Select", systemImage: "checklist")
                }
                .disabled(isDisabled || (list.selectable.isEmpty && reading == nil))
                .help(Text("Select on every page in the list"))
            }
        }
        .alert(
            question,
            isPresented: Binding(get: { notRecommended != nil }, set: { if !$0 { notRecommended = nil } })
        ) {
            // Return chooses the safe answer, so the question is read rather than passed with a key.
            if !list.recommended.isEmpty {
                Button("Select Recommended") {
                    selection.select(list.selectingRecommended(in: selection.selectedURLs))
                }
                .keyboardShortcut(.defaultAction)
            }
            Button("Select All") { selection.select(list.selectingAll(in: selection.selectedURLs)) }
            Button("Cancel", role: .cancel) {}
        } message: {
            if list.recommended.isEmpty {
                Text("This selects ^[\(notRecommended ?? 0) item](inflect: true) Peel doesn’t recommend removing. Check each one before you move it.")
            } else {
                Text("This also selects ^[\(notRecommended ?? 0) item](inflect: true) Peel doesn’t recommend removing. Check each one before you move it, or select only what Peel recommends.")
            }
        }
        .onChange(of: waiting) { _, command in
            guard let command else { return }
            waiting = nil
            run(command)
        }
    }

    /// Until the list is whole, what the commands would do is not known, so they stay offered.
    @ViewBuilder
    private var commands: some View {
        let selected = selection.selectedURLs
        let isWhole = reading == nil
        // Where Peel recommends every row a click can select, it would only repeat Select All.
        if !isWhole || list.recommended.count < list.selectable.count {
            Button("Select Recommended") { choose(.recommended) }
                .disabled(isWhole && (list.recommended.isEmpty || list.isRecommendedSelected(in: selected)))
        }
        Button(!isWhole || !list.notRecommendedAdded(by: selected).isEmpty ? "Select All…" : "Select All") {
            choose(.all)
        }
        .disabled(isWhole && list.isAllSelected(in: selected))
        Button("Deselect All") { run(.none) }
            .disabled(list.isNoneSelected(in: selected))
    }

    private func choose(_ command: Command) {
        guard let reading else { return run(command) }
        Task {
            guard await reading() else { return }
            waiting = command
        }
    }

    private func run(_ command: Command) {
        let selected = selection.selectedURLs
        switch command {
        case .recommended:
            selection.select(list.selectingRecommended(in: selected))
        case .all:
            let added = list.notRecommendedAdded(by: selected).count
            if added == 0 {
                selection.select(list.selectingAll(in: selected))
            } else {
                notRecommended = added
            }
        case .none:
            selection.select(list.deselectingAll(in: selected))
        }
    }

    private var question: Text {
        switch scope {
        case .list(let place): Text("Select everything in “\(place)”?")
        case .pages(let count):
            // An alert's title is drawn as plain text, which leaves inflection markup as written.
            Text(verbatim: String(inflecting: "Select everything on ^[\(count) page](inflect: true)?"))
        }
    }
}
