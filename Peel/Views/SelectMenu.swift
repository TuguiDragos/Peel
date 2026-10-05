import PeelCore
import SwiftUI

/// Select Recommended, Select All and Deselect All for one list. Select All asks first when it would also select
/// what Peel does not recommend. With nothing a click can select it draws nothing.
struct SelectMenu: View {
    let list: SelectableRows<URL>
    /// The list's name, as the page shows it, which the question names.
    let place: Text
    let selection: any RowSelection
    @State private var notRecommended: Int?

    var body: some View {
        if !list.selectable.isEmpty {
            let selected = selection.selectedURLs
            let asks = !list.notRecommendedAdded(by: selected).isEmpty
            Menu("Select") {
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
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()
            .alert(
                Text("Select everything in “\(place)”?"),
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
    }
}
