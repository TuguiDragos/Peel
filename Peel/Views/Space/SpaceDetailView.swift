import AppKit
import PeelCore
import SwiftUI

struct SpaceDetailView: View {
    @Environment(SpaceLibrary.self) private var space
    @Environment(HelperModel.self) private var helper
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
            RemovalsHeldBanner()
            if let plan {
                let locked = plan.removable.count { plan.isLocked($0, canUseHelper: helper.canAct) }
                if locked > 0 {
                    HelperRequiredBanner(need: .moving(locked))
                }
            }
            if !item.isReadOnly, let plan, Self.showsDeveloperNotice(for: plan) {
                developerNotice(plan, sizes: plan.developerSizes ?? [:])
                    .listRowSeparator(.hidden)
            }

            Section {
                Text(item.words.detail)
                    .font(.callout)
                if item.howToFreeIt != nil || !item.commands.isEmpty {
                    LabeledContent {
                        if let hint = item.howToFreeIt {
                            if #available(macOS 27, *) {
                                SpaceStep(step: hint)
                            } else {
                                Text(hint)
                                    .font(.callout)
                                    .textSelection(.enabled)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    } label: {
                        titled(
                            "How to free it",
                            "Space doesn’t touch this. How to free it, on this page, says what does."
                        )
                    }
                }
                if !item.commands.isEmpty {
                    CopyableLines(
                        caption: item.commands.count == 1
                            ? Text("Run this in Terminal. It deletes for good, without the Trash.")
                            : Text("Run these in Terminal. Those that remove something delete it for good, without the Trash."),
                        lines: item.commands
                    )
                }
            } header: {
                Text("What It Is")
            }
            .listRowSeparator(.hidden)

            if !item.isReadOnly, let plan {
                contents(of: plan)
            }

            Section {
                ForEach(item.listedPlaces, id: \.self) { url in
                    place(url, size: item.placeSizes[url]) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.abbreviatedPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let note = item.placeNotes[url] {
                                Text(note.words)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listRowSeparator(.hidden)
                ForEach(item.inContainers, id: \.self) { folders in
                    place(folders.parent) {
                        Text(verbatim: Self.sentence(for: folders))
                    }
                }
                .listRowSeparator(.hidden)
            } header: {
                Text("Where")
            }
        }
        .scrollBarBelowSectionHeaders()
        .dimmedWhileBusy(space.isScanning)
        .edgeBar(.bottom) {
            if !item.isReadOnly {
                RemovalBar(
                    page: item.page,
                    isScanning: space.isScanning,
                    isWorking: plan == nil,
                    scan: space.scanRun
                )
            }
        }
        // Made again each time the page opens, since what is inside changes as apps run. Rescan makes it again too
        // (`SpaceLibrary.rescan`), and so does a scan that finds the area changed.
        .task(id: item.id) {
            guard !item.isReadOnly else { return }
            await space.plan(item)
        }
        // The note asks to quit an app to include its folders. The workspace reports every change to the apps that
        // run through key-value observing, while it posts no notice for a menu bar or background app.
        .onReceive(NSWorkspace.shared.publisher(for: \.runningApplications)) { _ in
            space.followQuits(in: item)
        }
        .fadesInColumn(whenRowsChange: rows)
        .navigationTitle(Text(item.words.title))
        .toolbar(removing: .title)
    }

    private func place(_ url: URL, size: SizeTotal? = nil, @ViewBuilder named name: () -> some View) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            name()
            Spacer(minLength: 8)
            if let size {
                Text(size.text)
                    .rowFigure()
            }
            ShowInFinderButton(url: url)
        }
    }

    private static func sentence(for place: SpaceItem.ContainerFolders) -> String {
        let folders = place.folders.formatted(.list(type: .and))
        return place.areGroups
            ? String(inflecting: "\(folders) inside ^[\(place.containers) group container](inflect: true)")
            : String(inflecting: "\(folders) inside ^[\(place.containers) app container](inflect: true)")
    }

    @ViewBuilder
    private func contents(of plan: SpaceRemoval.Plan) -> some View {
        if plan.needsFullDiskAccess || !plan.unreadable.isEmpty {
            UnreadableFoldersNotice(folders: plan.unreadable, needsFullDiskAccess: plan.needsFullDiskAccess)
        }
        Section {
            if plan.removable.isEmpty, plan.unreadable.isEmpty {
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
                    isLocked: plan.isLocked(url, canUseHelper: helper.canAct),
                    isLeftAlone: plan.heldBack[url]?.cannotBeMoved == true,
                    isFirst: index == 0,
                    hasNoteColumn: !plan.heldBack.isEmpty,
                    selection: space, isSelected: space.isSelected(url)
                )
            }
            .listRowSeparator(.hidden)
            if !plan.appsToQuit.isEmpty || !plan.refused.isEmpty {
                ListNotes {
                    if !plan.appsToQuit.isEmpty {
                        Text("Peel doesn’t include folders an open app is still writing to: \(plan.appsToQuit.formatted(.list(type: .and))). Quit an app to include its folders. Peel can only tell a folder is an open app’s when it carries the app’s own name or identifier, not its maker’s.")
                    }
                    let keepingWork = plan.refused.values.count { $0 == .holdsWorkKeptInACache }
                    if keepingWork > 0 {
                        Text("Peel leaves ^[\(keepingWork) folder](inflect: true) here alone because an app keeps work there that exists nowhere else, such as an editor’s local history.")
                    }
                    if plan.refused.count > keepingWork {
                        Text("Peel leaves ^[\(plan.refused.count - keepingWork) folder](inflect: true) here alone because it protects what is there, such as what iCloud keeps to stay in sync, a wallet, an app’s documents, or a library.")
                    }
                }
            }
        } header: {
            SectionHeaderLine {
                heading("Inside", "What is selected goes to the Trash, and History can put it back. The folders it sits in stay, since macOS expects to find them.")
            } actions: {
                SelectMenu(
                    list: plan.selectableRows(canUseHelper: helper.canAct),
                    place: Text(item.words.title),
                    selection: space
                )
            }
        }
    }

    /// The notice comes with the plan, without its figures until they are measured, so it never pushes the rows down.
    static func showsDeveloperNotice(for plan: SpaceRemoval.Plan) -> Bool {
        !plan.leftToDeveloper.isEmpty
    }

    /// Why the area's size in the list is more than this page can move, and where the rest is freed.
    private func developerNotice(_ plan: SpaceRemoval.Plan, sizes: [URL: Int64]) -> some View {
        let folders = RemovalFailureAlert.listedFolders(
            plan.leftToDeveloper
                .sorted { SizeTotal([sizes[$1]]) < SizeTotal([sizes[$0]]) }
                .map { folder in
                    sizes[folder].map { String(localized: "\(folder.lastPathComponent) (\($0.byteCount))") }
                        ?? folder.lastPathComponent
                }
        )
        let title: Text = if let seen = plan.seen, seen.isComplete, total.reading != .unknown {
            Text("\(total.text) of \(seen.known.byteCount) can be moved here.")
        } else {
            Text("Part of this folder is left to the Developer page.")
        }
        let detail: Text = if case .exactly(let size) = SizeTotal(plan.leftToDeveloper.map { sizes[$0] }).reading {
            Text("Developer tools’ folders hold \(size.byteCount) of it: \(folders). The Developer page frees them, keeping what is more than a cache.")
        } else {
            Text("These developer tools’ folders are left to the Developer page: \(folders). It frees them, keeping what is more than a cache.")
        }
        return Notice(title: title, detail: detail, kind: .note, systemImage: Tool.developer.systemImage) {
            Button("Open Developer") { Navigator.shared.requestedTool = .developer }
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
                        title: Text("Listed only"), systemImage: "hand.raised",
                        name: String(localized: "Listed only"),
                        detail: Text("Space doesn’t touch this. How to free it, on this page, says what does.")
                    )
                }
            }
        } trailing: {
            TotalLabel(total: total, caption: caption)
        }
    }

    /// The size of the item's folders until the plan is ready, then the size of what can be moved to the Trash.
    private var total: SizeTotal {
        plan?.movable(canUseHelper: helper.canAct) ?? item.size
    }

    private var caption: Text {
        if item.isReadOnly { return Text("on this Mac") }
        return plan == nil ? Text("in here") : Text("to remove")
    }

    private static func ordered(_ plan: SpaceRemoval.Plan) -> [URL] {
        plan.removable.sorted { first, second in
            SizeTotal([plan.sizes[second]]) < SizeTotal([plan.sizes[first]])
        }
    }
}

/// What frees an area's space, beside its label. On macOS 27 a list lays out a selectable text aligned to the trailing
/// edge narrower than it measured it, which cut its last lines, so the text asks for its whole height.
@available(macOS 27, *)
struct SpaceStep: View {
    let step: LocalizedStringResource

    var body: some View {
        Text(step)
            .font(.callout)
            .textSelection(.enabled)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
    }
}
