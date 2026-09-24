import AppKit
import PeelCore
import SwiftUI

struct SpaceDetailView: View {
    @Environment(SpaceLibrary.self) private var space
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(RemovalOutcome.self) private var outcome
    @Environment(ExclusionsStore.self) private var exclusions
    @State private var isConfirmingRemoval = false
    @State private var plan: SpaceRemoval.Plan?
    /// The plan's removable children, in the order every list uses: unknown sizes first, then the largest.
    @State private var rows: [URL] = []
    let item: SpaceItem

    /// The apps that are open, by the names their folders may carry. Read each time rather than stored, since
    /// an app can be opened while this page is on screen.
    private var running: [String: String] {
        SpaceRemoval.namesOfRunningApps()
    }

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)
            ExclusionsUnreadableBanner()

            Section {
                Text(item.words.detail)
                    .font(.callout)
                if let hint = item.words.hint {
                    LabeledContent {
                        Text(hint)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        heading(
                            "How to free it",
                            "Space doesn’t touch this: the app that made it knows what is still needed."
                        )
                    }
                }
            } header: {
                Text("What It Is")
            }
            .listRowSeparator(.hidden)

            if !item.isReadOnly, let plan {
                contents(of: plan)
            }

            Section {
                ForEach(item.urls, id: \.self) { url in
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(url.abbreviatedPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Label("Show in Finder", systemImage: "arrow.up.forward.app")
                                .minimumTarget()
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help(Text("Show in Finder"))
                    }
                }
                .listRowSeparator(.hidden)
            } header: {
                Text("Where")
            }
        }
        .safeAreaBar(edge: .bottom) {
            if !item.isReadOnly {
                RemovalBar(
                    selectedSize: selected.known,
                    isSelectionMeasured: selected.isComplete,
                    isScanning: plan == nil,
                    isEnabled: !selectedRows.isEmpty && !space.isRemoving,
                    onRemove: { isConfirmingRemoval = true }
                )
            }
        }
        // Builds the plan again when a rescan changes the item's size or the exclusions change, so the list
        // follows what is on disk, not what was there when the page opened.
        .task(id: [item.id, String(item.size ?? 0), String(exclusions.revision)]) {
            plan = nil
            guard !item.isReadOnly else { return }
            let found = await SpaceRemoval.plan(for: item, exclusions: exclusions.exclusions, running: running)
            guard !Task.isCancelled else { return }
            plan = found
            rows = Self.ordered(found)
            // Selects only the children whose size is known, as every page does, and leaves the rest to the user.
            space.selectedURLs = Set(found.removable.filter { found.sizes[$0] != nil })
        }
        .fadesInColumn(whenRowsChange: rows)
        .navigationTitle(Text(item.words.title))
        .toolbar(removing: .title)
        .confirmationDialog(Text.movingToTrash(selectedRows.count, selected), isPresented: $isConfirmingRemoval) {
            Button("Move to Trash") {
                Task { await remove() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func contents(of plan: SpaceRemoval.Plan) -> some View {
        Section {
            if plan.removable.isEmpty {
                Text("Nothing in here can be moved now.")
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            }
            ForEach(Array(rows.enumerated()), id: \.element) { index, url in
                RemovalRow(
                    url: url,
                    icon: .file(url),
                    detail: nil,
                    size: plan.sizes[url] ?? 0,
                    isMeasured: plan.sizes[url] != nil,
                    isFirst: index == 0,
                    hasNoteColumn: false,
                    selection: space, isSelected: space.isSelected(url)
                )
            }
            .listRowSeparator(.hidden)
        } header: {
            SectionHeaderLine {
                heading("Inside", "What is selected goes to the Trash, and History can put it back. The folders it sits in stay, since macOS expects to find them.")
            } actions: {
                SelectAllButton(selectable: rows, selection: Bindable(space).selectedURLs)
            }
        } footer: {
            if !plan.appsToQuit.isEmpty || !plan.leftToDeveloper.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !plan.appsToQuit.isEmpty {
                        Text("Peel doesn’t include folders an open app is still writing to: \(plan.appsToQuit.formatted(.list(type: .and))). Quit an app to include its folders. Peel can only tell a folder is an open app’s when it carries the app’s own name or identifier, not its maker’s.")
                    }
                    if !plan.leftToDeveloper.isEmpty {
                        Text("Peel leaves ^[\(plan.leftToDeveloper.count) folder](inflect: true) here to the Developer page, which knows which part of each is only a cache.")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        PageHeader(systemImage: item.category.systemImage) {
            Text(item.words.title)
                .pageHeading()
        } details: {
            FlowLayout {
                Badge(title: Text(item.category.title), systemImage: item.category.systemImage)
                if item.isReadOnly {
                    NoteBadge(
                        title: Text("Read only"), systemImage: "hand.raised", tint: .secondary,
                        name: String(localized: "Read only"),
                        detail: Text("Space doesn’t touch this: the app that made it knows what is still needed.")
                    )
                }
            }
        } trailing: {
            TotalLabel(total: total, caption: caption)
                .accessibilityLabel(Text(verbatim: total.text))
        }
    }

    /// The size of the item's folders until the plan is ready, then the size of what can be moved to the Trash.
    private var total: SizeTotal {
        guard let plan else { return SizeTotal([item.size]) }
        return SizeTotal(plan.removable.map { plan.sizes[$0] })
    }

    private var caption: Text {
        if item.isReadOnly { return Text("in use") }
        return plan == nil ? Text("in here") : Text("to remove")
    }

    private var selectedRows: [URL] {
        plan?.removable.filter { space.selectedURLs.contains($0) } ?? []
    }

    private var selected: SizeTotal {
        SizeTotal(selectedRows.map { plan?.sizes[$0] })
    }

    private func remove() async {
        space.isRemoving = true
        defer { space.isRemoving = false }
        let exclusions = ExclusionsStore.shared.exclusions
        // Builds the plan again rather than trusting the one on screen. An app opened since then may be writing
        // to some of these folders, and the new plan leaves them out.
        let fresh = await SpaceRemoval.plan(for: item, exclusions: exclusions, running: running)
        let urls = fresh.removable.filter { space.selectedURLs.contains($0) }
        let result = await TrashService(exclusions: exclusions).trash(urls)
        outcome.report(result)
        await history.record(result, tool: .space, source: item.words.title.inEnglish, sourceKey: "space.\(item.id)", sizes: fresh.sizes)
        let after = await SpaceRemoval.plan(for: item, exclusions: exclusions, running: running)
        plan = after
        rows = Self.ordered(after)
        await space.refresh()
    }

    private static func ordered(_ plan: SpaceRemoval.Plan) -> [URL] {
        plan.removable.sorted { first, second in
            SizeTotal([plan.sizes[second]]) < SizeTotal([plan.sizes[first]])
        }
    }
}
