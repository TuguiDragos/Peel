import PeelCore
import SwiftUI

struct SpaceList: View {
    @Environment(SpaceLibrary.self) private var space
    @Environment(HelperModel.self) private var helper
    @State private var isRescanning = false
    @State private var searchText = ""

    private func listed(in category: SpaceItem.Category, of report: SpaceReport) -> [SpaceItem] {
        let items = report.items(in: category)
        guard !searchText.isEmpty else { return items }
        return items.filter { SearchText.matches(String(localized: $0.words.title), searchText) }
    }

    private var shownAreas: [SpaceItem] {
        guard let report = space.report else { return [] }
        return SpaceItem.Category.allCases.flatMap { listed(in: $0, of: report) }
    }

    private var isFindingNothing: Bool {
        guard let report = space.report, !searchText.isEmpty else { return false }
        return SpaceItem.Category.allCases.allSatisfy { listed(in: $0, of: report).isEmpty }
    }

    var body: some View {
        @Bindable var space = space

        List(selection: $space.selection) {
            if let report = space.report {
                storage(report)
                    .listRowSeparator(.hidden)
                if report.needsFullDiskAccess {
                    FullDiskAccessBanner()
                }
                // Both messages are rows under the storage strip, not an overlay on the list, so the disk's
                // figures stay visible when no item is listed.
                if report.items.isEmpty {
                    ContentUnavailableView(
                        "Nothing Big Found",
                        systemImage: "checkmark.seal",
                        description: Text("None of the places Peel checks here takes up enough room to report.")
                    )
                    .listRowSeparator(.hidden)
                } else if isFindingNothing {
                    ContentUnavailableView.search(text: searchText)
                        .listRowSeparator(.hidden)
                }
                ForEach(SpaceItem.Category.allCases, id: \.self) { category in
                    let items = listed(in: category, of: report)
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { item in
                                SpaceRow(item: item)
                                    .tag(item.id)
                            }
                        } header: {
                            Text(category.title)
                        }
                    }
                }
            }
        }
        .accessibilityLabel(Text(Tool.space.title))
        .scrollBarBelowSectionHeaders(space.report?.items.isEmpty == false)
        .columnSearch(text: $searchText, prompt: "Search Space", when: space.report?.items.isEmpty == false)
        .scanState(
            space.report != nil ? .content : space.scanRun.wasStopped ? .stopped : .scanning(.walk),
            isRescanning: isRescanning,
            scan: space.scanRun
        )
        .fadesInColumn(whenRowsChange: space.report?.items.map(\.id))
        .navigationTitle(Text(Tool.space.title))
        .announcesScan(space.isScanning, found: space.summary, wasStopped: space.scanRun.wasStopped)
        .toolbar {
            ToolbarItem {
                let shown = shownAreas
                SelectOnEveryPage(
                    pages: SelectablePages(shown.compactMap { item in
                        space.plans[item.id].map { (item.page, $0.selectableRows(canUseHelper: helper.canAct)) }
                    }),
                    selection: space,
                    reading: shown.contains { !$0.isReadOnly && space.plans[$0.id] == nil }
                        ? { await space.planEvery(shown) } : nil,
                    isDisabled: space.isScanning
                ) { page in
                    guard space.selection == nil, let item = shown.first(where: { $0.page == page }) else { return }
                    space.selection = item.id
                }
            }
            ToolbarItem {
                RescanButton(isRunning: $isRescanning, isDisabled: space.isRemoving, scan: space.scanRun) {
                    await space.rescan()
                }
            }
        }
        .task {
            if space.report != nil { await space.readDisk() }
            guard space.report == nil, !space.isScanning, !space.scanRun.wasStopped else { return }
            await space.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await space.readDisk() }
        }
        .rescanOnExclusionChange("SpaceList") { await space.refresh() }
        .rescanAfterPutBack(.space) { await space.refresh() }
    }

    private func storage(_ report: SpaceReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let disk = space.disk {
                StorageStrip(storage: disk.storage)
            }
            if let purgeable = space.disk?.purgeable, purgeable > 0 {
                // The strip's available figure already includes these bytes, so the note ties them to it, not
                // to the used figure.
                Text("The available space includes \(purgeable.byteCount) that macOS clears when something needs the room.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if space.disk != nil, space.disk?.purgeable == nil {
                Text("Peel couldn’t find out how much of the available space macOS clears by itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let snapshots = report.snapshots, !snapshots.isEmpty {
                SnapshotNote(snapshots: snapshots)
            } else if report.snapshots == nil {
                Text("Peel couldn’t list the snapshots kept on this disk, which may hold some of its space.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if #available(macOS 27, *), let size = AppleIntelligence.onThisMac {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Intelligence can keep up to \(size.byteCount) on this Mac, by Apple’s figure.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link(destination: Links.appleIntelligenceGuide) {
                        Text("Turn Off Apple Intelligence Features")
                            .minimumTarget()
                    }
                    .font(.caption)
                }
            }
            if #available(macOS 27, *), let models = space.models {
                VStack(alignment: .leading, spacing: 2) {
                    modelsLine(models)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        Navigator.shared.requestedTool = .developer
                    } label: {
                        Text("Open Developer")
                            .minimumTarget()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 6)
    }

    @available(macOS 27, *)
    private func modelsLine(_ total: SizeTotal) -> Text {
        switch total.reading {
        case .exactly(let size): Text("AI models and datasets take \(size.byteCount) on this Mac.")
        case .atLeast(let size): Text("AI models and datasets take over \(size.byteCount) on this Mac.")
        case .unknown: Text("Peel couldn’t measure the AI models and datasets on this Mac.")
        }
    }
}

/// A note on the disk's local snapshots, which make up most of its purgeable space. Deleting a snapshot can't
/// be undone, so Peel explains them and never removes one.
private struct SnapshotNote: View {
    let snapshots: [LocalSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("^[\(snapshots.count) snapshot](inflect: true) of this disk, kept on this disk")
                .font(.callout.weight(.semibold))
            ForEach(explanations, id: \.key) { explanation in
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(snapshots.prefix(3)) { snapshot in
                Text(verbatim: describe(snapshot))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    // A snapshot's name is an identifier, so it is cut in the middle to keep both ends. A date or
                    // a sentence is cut at the end.
                    .truncationMode(snapshot.date == nil && snapshot.kind != .systemUpdate ? .middle : .tail)
            }
            // Per `man tmutil`, this command deletes only Time Machine's snapshots, so it is shown only when
            // there is one.
            if snapshots.contains(where: { $0.kind == .timeMachine }) {
                Text("Peel doesn’t remove them: a deleted snapshot can’t be put back, unlike what Peel moves to the Trash. `\(LocalSnapshots.deleteCommand)` deletes Time Machine’s snapshots, if you are sure.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.top, 4)
    }

    /// One sentence for each kind of snapshot in the list, which can hold all three. `.other` covers any name
    /// that is neither Time Machine's nor macOS's, and `tmutil deletelocalsnapshots` doesn't delete those.
    private var explanations: [LocalizedStringResource] {
        let kinds = Set(snapshots.map(\.kind))
        var lines: [LocalizedStringResource] = []
        if kinds.contains(.timeMachine) {
            lines.append("Time Machine’s snapshots are made as it backs up, and kept for a while. macOS deletes them itself when something needs the room.")
        }
        if kinds.contains(.systemUpdate) {
            lines.append("macOS makes a snapshot before it updates, so the update can be undone. It goes away by itself.")
        }
        if kinds.contains(.other) {
            lines.append("Snapshots another app made, such as a backup app, are that app’s to remove, not Peel’s.")
        }
        return lines
    }

    private func describe(_ snapshot: LocalSnapshot) -> String {
        if let date = snapshot.date {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        if snapshot.kind == .systemUpdate {
            return String(localized: "Taken before a macOS update")
        }
        return snapshot.name
    }
}

private struct SpaceRow: View {
    let item: SpaceItem

    var body: some View {
        ToolRow(systemImage: item.category.systemImage) {
            Text(item.words.title)
                .lineLimit(2)
        } details: {
            if item.isReadOnly {
                Text("Managed by its own app")
            }
        } trailing: {
            Text(item.size.byteCount)
                .rowFigure()
        }
    }
}
