import SwiftUI

/// Notes under the rows of a list's section, in a row of their own: macOS shows a `List` section's footer on one line
/// and cuts off the rest of a longer note.
struct ListNotes<Notes: View>: View {
    @ViewBuilder let notes: Notes

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            notes
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .listRowSeparator(.hidden)
    }
}
