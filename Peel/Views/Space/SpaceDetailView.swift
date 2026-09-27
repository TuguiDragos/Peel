import AppKit
import PeelCore
import SwiftUI

struct SpaceDetailView: View {
    @Environment(SpaceLibrary.self) private var space
    let item: SpaceItem

    private var plan: SpaceRemoval.Plan? {
        space.plans[item.id]
    }

    /// The plan's removable children, in the order every list uses: unknown sizes first, then the largest.
    private var rows: [URL] {
        plan.map(Self.ordered) ?? []
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
        .dimmedWhileBusy(space.isScanning)
        .safeAreaBar(edge: .bottom) {
            if !item.isReadOnly {
                RemovalBar(page: Tool.space.page(item.id), isScanning: plan == nil || space.isScanning)
            }
        }
        // Made again each time the page opens, since what is inside changes as apps run. A rescan that finds the
        // area changed makes it again too (`SpaceLibrary.refresh`).
        .task(id: item.id) {
            guard !item.isReadOnly else { return }
            await space.plan(item)
        }
        .fadesInColumn(whenRowsChange: rows)
        .navigationTitle(Text(item.words.title))
        .toolbar(removing: .title)
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
                    warning: plan.heldBack[url].map { String(localized: $0.explanation) },
                    size: plan.sizes[url] ?? 0,
                    isMeasured: plan.sizes[url] != nil,
                    isFirst: index == 0,
                    hasNoteColumn: !plan.heldBack.isEmpty,
                    selection: space, isSelected: space.isSelected(url)
                )
            }
            .listRowSeparator(.hidden)
        } header: {
            SectionHeaderLine {
                heading("Inside", "What is selected goes to the Trash, and History can put it back. The folders it sits in stay, since macOS expects to find them.")
            } actions: {
                SelectAllButton(selectable: rows.filter { plan.heldBack[$0] == nil }, selection: Bindable(space).selectedURLs)
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

    private static func ordered(_ plan: SpaceRemoval.Plan) -> [URL] {
        plan.removable.sorted { first, second in
            SizeTotal([plan.sizes[second]]) < SizeTotal([plan.sizes[first]])
        }
    }
}
