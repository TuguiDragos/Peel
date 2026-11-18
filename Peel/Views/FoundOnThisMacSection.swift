import PeelCore
import SwiftUI

/// What a page found, as one list to read, where nothing can be selected: no Select menu, and no split into what Peel
/// recommends and what to review, since both are about choosing.
struct FoundOnThisMacSection<Rows: View>: View {
    let count: Int
    let size: SizeTotal
    @ViewBuilder let rows: Rows

    var body: some View {
        Section {
            rows
        } header: {
            SectionHeaderLine {
                Text("Found on This Mac")
            } count: {
                Text("^[\(count) item](inflect: true) · \(size.text)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } actions: {
                EmptyView()
            }
        }
    }
}
