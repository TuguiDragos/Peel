import PeelCore
import SwiftUI

/// What Peel was asked to move in one removal and did not, with the reason for each item.
struct RefusalDetailView: View {
    @Environment(ExclusionsStore.self) private var exclusions
    let batch: RefusalBatch

    var body: some View {
        List {
            PageHeader(systemImage: "nosign") {
                Text(verbatim: batch.title)
                    .pageTitle()
                    .textSelection(.enabled)
                    .help(Text(verbatim: batch.title))
            } details: {
                Text("You asked to move these \(batch.date, format: .relative(presentation: .named)), on \(batch.date, format: .dateTime.day().month(.wide).year().hour().minute()).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .listRowSeparator(.hidden)

            Section {
                ForEach(Array(batch.records.enumerated()), id: \.element.id) { index, record in
                    RefusalRecordRow(record: record, isExcluded: exclusions.exclusions.excludes(record.url), isFirst: index == 0)
                }
                .listRowSeparator(.hidden)
            } header: {
                Text("Items")
            }
        }
        .navigationTitle(Text(verbatim: batch.title))
        .toolbar(removing: .title)
    }
}

private struct RefusalRecordRow: View {
    let record: RefusalRecord
    let isExcluded: Bool
    var isFirst = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "nosign")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.url.abbreviatedPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .tableRow(isFirst: isFirst)
        .contextMenu {
            ItemMenu(url: record.url, isExcluded: isExcluded)
        }
    }

    /// Why the item stayed, in the words Peel shows when it refuses. A reason this version doesn't know is shown
    /// as it was stored.
    private var explanation: String {
        TrashFailure.Reason(name: record.reason, detail: record.detail)?.explanation ?? record.detail ?? record.reason
    }
}
