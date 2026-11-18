import PeelCore
import SwiftUI

/// What Peel was asked to move in one removal and did not, with the reason for each item.
struct RefusalDetailView: View {
    @Environment(ExclusionsStore.self) private var exclusions
    let batch: RefusalBatch
    /// The records whose item is still where it was, looked at once the page opens.
    @State private var stillThere: Set<RefusalRecord.ID> = []

    /// The tools the items were asked to move from, in their order, where a new scan judges them again.
    private var tools: [Tool] {
        var seen: Set<Tool> = []
        return batch.records.compactMap { Tool(rawValue: $0.tool) }.filter { seen.insert($0).inserted }
    }

    var body: some View {
        List {
            PageHeader(systemImage: "nosign") {
                Text(verbatim: batch.title)
                    .pageTitle()
                    .textSelection(.enabled)
                    .help(Text(verbatim: batch.title))
            } details: {
                TimelineView(.everyMinute) { _ in
                    Text("You asked to move these \(batch.date, format: .relative(presentation: .named)), on \(batch.date, format: .dateTime.day().month(.wide).year().hour().minute()).")
                }
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .listRowSeparator(.hidden)

            Section {
                ForEach(Array(batch.records.enumerated()), id: \.element.id) { index, record in
                    RefusalRecordRow(
                        record: record,
                        isExcluded: exclusions.exclusions.excludes(record.url),
                        isStillThere: stillThere.contains(record.id),
                        isFirst: index == 0
                    )
                }
                .listRowSeparator(.hidden)
            } header: {
                Text("Items")
            }

            if !tools.isEmpty {
                PageActions {
                    ForEach(tools, id: \.self) { tool in
                        Button { Navigator.shared.requestedTool = tool } label: { Text("Open \(Text(tool.title))") }
                    }
                }
            }
        }
        .scrollBarBelowSectionHeaders()
        .task(id: batch.id) {
            let records = batch.records
            stillThere = await Task.detached {
                Set(records.filter { !$0.url.isMissing }.map(\.id))
            }.value
        }
        .navigationTitle(Text(verbatim: batch.title))
        .toolbar(removing: .title)
    }
}

private struct RefusalRecordRow: View {
    let record: RefusalRecord
    let isExcluded: Bool
    /// Whether the item is still where it was, so Finder can show it.
    let isStillThere: Bool
    var isFirst = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "nosign")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.url.abbreviatedPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if isStillThere {
                ShowInFinderButton(url: record.url)
            }
        }
        .tableRow(isFirst: isFirst)
        .contextMenu {
            ItemMenu(url: record.url, isExcluded: isExcluded)
        }
    }

    /// Why the item stayed, in the words Peel shows when it refuses. A reason this version doesn't know is shown
    /// as it was stored.
    private var explanation: String {
        record.failureReason?.explanation ?? record.detail ?? record.reason
    }
}
