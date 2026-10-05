import PeelCore
import SwiftUI

/// Select Recommended, Select All and Deselect All for one list, or from a tool's toolbar for every page it lists.
/// Select All asks first when it would also select what Peel does not recommend.
struct SelectMenu: View {
    let list: SelectableRows<URL>
    let selection: any RowSelection
    private let scope: Scope
    @State private var notRecommended: Int?

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
    }

    init(pages: Int, list: SelectableRows<URL>, selection: any RowSelection) {
        self.list = list
        self.selection = selection
        scope = .pages(pages)
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
                .disabled(list.selectable.isEmpty)
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
    }

    @ViewBuilder
    private var commands: some View {
        let selected = selection.selectedURLs
        let asks = !list.notRecommendedAdded(by: selected).isEmpty
        // Where Peel recommends every row a click can select, it would only repeat Select All.
        if list.recommended.count < list.selectable.count {
            Button("Select Recommended") { selection.select(list.selectingRecommended(in: selected)) }
                .disabled(list.recommended.isEmpty || list.isRecommendedSelected(in: selected))
        }
        Button(asks ? "Select All…" : "Select All") {
            if asks {
                notRecommended = list.notRecommendedAdded(by: selected).count
            } else {
                selection.select(list.selectingAll(in: selected))
            }
        }
        .disabled(list.isAllSelected(in: selected))
        Button("Deselect All") { selection.select(list.deselectingAll(in: selected)) }
            .disabled(list.isNoneSelected(in: selected))
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
