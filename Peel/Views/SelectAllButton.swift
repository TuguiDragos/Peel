import PeelCore
import SwiftUI

/// Selects every row of a section that can be selected, or clears them all. With nothing to select it draws nothing:
/// a Select All that changes nothing reads as broken.
struct SelectAllButton<ID: Hashable>: View {
    let selectable: [ID]
    /// Every row of the section, which Deselect All clears, a row selected by hand included.
    let rows: [ID]
    @Binding var selection: Set<ID>

    var body: some View {
        if !selectable.isEmpty {
            let isAllSelected = SelectAll.isAllSelected(selectable, in: selection)
            Button {
                selection = SelectAll.toggled(selection, selectable: selectable, rows: rows)
            } label: {
                Text(isAllSelected ? "Deselect All" : "Select All")
                    .minimumTarget()
            }
            .buttonStyle(.borderless)
        }
    }
}
