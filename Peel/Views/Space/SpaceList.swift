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
                    UnreadableFoldersNotice(folders: [], needsFullDiskAccess: true)
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
            if space.report != nil { await space.readDisks() }
            guard space.report == nil, !space.scanRun.isWaitedFor, !space.scanRun.wasStopped else { return }
            await space.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await space.readDisks() }
        }
        .rescanOnExclusionChange("SpaceList") { await space.refresh() }
        .rescanAfterPutBack(.space) { await space.refresh() }
    }

    private func storage(_ report: SpaceReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DiskBands(disks: space.disks, snapshots: report.snapshots)
            if #available(macOS 27, *), let size = AppleIntelligence.onThisMac {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Intelligence can keep up to \(size.byteCount) on this Mac, by Apple’s figure.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .wrapsInARow()
                    Link(destination: Links.appleIntelligenceGuide) {
                        Text("How to Turn Off Apple Intelligence Features, in the Mac User Guide")
                            .minimumTarget()
                    }
                    .font(.caption)
                }
            }
            if let models = space.models {
                VStack(alignment: .leading, spacing: 2) {
                    modelsLine(models)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .wrapsInARow()
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

    private static let whyNotMeasured: [HoldBack] = [.notMeasured, .couldNotBeRead, .closedByPermissions]

    static func modelsSentence(_ reading: SizeTotal.Reading) -> LocalizedStringResource {
        switch reading {
        case .exactly(let size): "The AI models and datasets the Developer page lists take \(size.byteCount)."
        case .atLeast(let size): "The AI models and datasets the Developer page lists take over \(size.byteCount)."
        case .unknown: "Peel could not measure the AI models and datasets the Developer page lists."
        }
    }

    private func modelsLine(_ total: SizeTotal) -> Text {
        switch total.reading {
        case .exactly, .atLeast: Text(Self.modelsSentence(total.reading))
        case .unknown:
            Text(verbatim: ([String(localized: Self.modelsSentence(.unknown))]
                + Self.whyNotMeasured.filter(space.modelsNotMeasured.contains).map {
                    switch $0 {
                    case .couldNotBeRead: String(localized: "macOS kept Peel out of a folder of theirs.")
                    case .closedByPermissions: String(localized: "A folder of theirs has permissions of its own that keep your account out.")
                    default: String(localized: "Measuring a folder of theirs took too long.")
                    }
                }).joined(separator: " "))
        }
    }
}

/// Each disk Space shows, with what macOS clears from it by itself and the snapshots kept on it. A disk is named only
/// when there are two: the startup disk, and the one the home folder is kept on.
struct DiskBands: View {
    let disks: [DiskSpace]
    let snapshots: [DiskSnapshots]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(disks, id: \.snapshotVolume) { disk in
                VStack(alignment: .leading, spacing: 8) {
                    if disks.count > 1, let name = disk.name {
                        Text(verbatim: name)
                            .font(.callout.weight(.semibold))
                    }
                    StorageStrip(storage: disk.storage)
                    if let purgeable = disk.purgeable, purgeable > 0 {
                        // The strip's available figure already includes these bytes, so the note ties them to it,
                        // not to the used figure.
                        Text("The available space includes \(purgeable.byteCount) that macOS clears when something needs the room.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .wrapsInARow()
                    } else if disk.purgeable == nil {
                        Text("Peel couldn’t find out how much of the available space macOS clears by itself.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .wrapsInARow()
                    }
                    let kept = snapshots.first { $0.volume == disk.snapshotVolume }
                    if let list = kept?.snapshots, !list.isEmpty {
                        SnapshotNote(snapshots: list, volume: disk.snapshotVolume)
                    } else if let kept, kept.snapshots == nil {
                        Text("Peel couldn’t list the snapshots kept on this disk, which may hold some of its space.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .wrapsInARow()
                    }
                }
            }
        }
    }
}

/// A note on the disk's local snapshots, which make up most of its purgeable space. Deleting a snapshot can't
/// be undone, so Peel explains them and never removes one.
private struct SnapshotNote: View {
    let snapshots: [LocalSnapshot]
    let volume: String

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
                Text("Peel doesn’t remove them: a deleted snapshot can’t be put back, unlike what Peel moves to the Trash. `\(LocalSnapshots.deleteCommand(for: volume))` deletes Time Machine’s snapshots, if you are sure.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.top, 4)
    }

    /// One sentence for each kind of snapshot in the list, which can hold all three, and one more when macOS says it
    /// can't delete some of them to make room. `.other` covers any name that is neither Time Machine's nor macOS's,
    /// and `tmutil deletelocalsnapshots` doesn't delete those.
    private var explanations: [LocalizedStringResource] {
        let kinds = Set(snapshots.map(\.kind))
        var lines: [LocalizedStringResource] = []
        if kinds.contains(.timeMachine) {
            lines.append("Time Machine’s snapshots are made as it backs up, and kept for a while. macOS deletes them itself when something needs the room.")
        }
        if kinds.contains(.systemUpdate) {
            lines.append("macOS saves a snapshot before it installs an update.")
        }
        if kinds.contains(.other) {
            lines.append("Snapshots another app made, such as a backup app, are that app’s to remove, not Peel’s.")
        }
        if snapshots.contains(where: { $0.isPurgeable == false }) {
            lines.append("macOS says it can’t delete some of these to make room, so their space isn’t available until they are gone.")
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
            if item.isReadOnly, !item.words.isFreedByPeel {
                if item.isRemovedByHand {
                    Text("Removed by hand in Finder")
                } else {
                    Text("Managed by its own app or tool")
                }
            }
        } trailing: {
            Text(item.size.text)
                .rowFigure()
        }
    }
}

private extension View {
    /// macOS 27 draws the text of a list row on one line unless it asks for its full height; macOS 26 wraps it.
    @ViewBuilder
    func wrapsInARow() -> some View {
        if #available(macOS 27, *) {
            fixedSize(horizontal: false, vertical: true)
        } else {
            self
        }
    }
}
