import SwiftUI

/// Selects every row of a section that can be selected, or clears them. With nothing to select it draws nothing: a
/// Select All that changes nothing reads as broken.
struct SelectAllButton<ID: Hashable>: View {
    let selectable: [ID]
    @Binding var selection: Set<ID>

    var body: some View {
        if !selectable.isEmpty {
            let isAllSelected = selectable.allSatisfy(selection.contains)
            Button {
                if isAllSelected {
                    selection.subtract(selectable)
                } else {
                    selection.formUnion(selectable)
                }
            } label: {
                Text(isAllSelected ? "Deselect All" : "Select All")
                    .minimumTarget()
            }
            .buttonStyle(.borderless)
        }
    }
}
