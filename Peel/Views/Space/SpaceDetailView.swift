import AppKit
import PeelCore
import SwiftUI

struct SpaceDetailView: View {
    @Environment(SpaceLibrary.self) private var space
    @Environment(HelperModel.self) private var helper
    @Environment(SelectionCarrier.self) private var carrier
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

            if item.howToFreeIt != nil || !item.commands.isEmpty {
                Section {
                    if let hint = item.howToFreeIt {
                        SpaceStep(step: hint, note: item.howToFreeItNote)
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
                    Text("How to Free It")
                }
                .listRowSeparator(.hidden)
            }

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
            if !item.isReadOnly,
               Self.offersItsBar(plan, canUseHelper: helper.canAct) || carrier.movesSomething(from: item.page) {
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

    /// True when the area lists folders and a click can select none of them: the page is then a list to read.
    static func isOnlyToRead(_ plan: SpaceRemoval.Plan, canUseHelper: Bool) -> Bool {
        !plan.removable.isEmpty && plan.selectableRows(canUseHelper: canUseHelper).selectable.isEmpty
    }

    /// The bar while the plan is made, or once something in it can be selected.
    static func offersItsBar(_ plan: SpaceRemoval.Plan?, canUseHelper: Bool) -> Bool {
        guard let plan else { return true }
        return !plan.selectableRows(canUseHelper: canUseHelper).selectable.isEmpty
    }

    @ViewBuilder
    private func contents(of plan: SpaceRemoval.Plan) -> some View {
        if Self.isOnlyToRead(plan, canUseHelper: helper.canAct) {
            FoundOnThisMacSection(count: rows.count, size: SizeTotal(rows.map { plan.sizes[$0] })) {
                inside(plan, isReadOnly: true)
            }
        } else {
            UnreadableFoldersNotice(folders: plan.unreadable, needsFullDiskAccess: plan.needsFullDiskAccess)
            Section {
                if plan.removable.isEmpty, plan.unreadable.isEmpty {
                    Text("Nothing in here can be moved now.")
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                }
                inside(plan, isReadOnly: false)
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
    }

    @ViewBuilder
    private func inside(_ plan: SpaceRemoval.Plan, isReadOnly: Bool) -> some View {
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
                isReadOnly: isReadOnly,
                selection: space, isSelected: space.isSelected(url)
            )
        }
        .listRowSeparator(.hidden)
        if !plan.appsToQuit.isEmpty || !plan.refused.isEmpty {
            ListNotes {
                if !plan.appsToQuit.isEmpty {
                    let title = Self.quitToInclude(plan.appsToQuit)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(title)
                        InfoNote(about: Text(title), detail: Text(Self.openAppsNote), isAlbum: false)
                    }
                }
                if !plan.refused.isEmpty {
                    let title = Self.leftAlone(plan.refused.count)
                    let keepingWork = plan.refused.values.count { $0 == .holdsWorkKeptInACache }
                    let why = Self.whyLeftAlone(keepingWork: keepingWork, protected: plan.refused.count - keepingWork)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(title)
                        InfoNote(
                            about: Text(title),
                            detail: why.dropFirst().reduce(Text(why[0])) { Text("\($0)\n\n\(Text($1))") },
                            isAlbum: false
                        )
                    }
                }
            }
        }
    }

    static func quitToInclude(_ apps: [String]) -> LocalizedStringResource {
        let names = apps.formatted(.list(type: .and))
        if apps.count == 1 {
            return "Quit \(names) to include its folders"
        }
        return "Quit \(names) to include their folders"
    }

    static let openAppsNote: LocalizedStringResource = "Peel leaves out the folders an open app is writing to. It can tell only by the name or identifier of the app."

    static func leftAlone(_ count: Int) -> LocalizedStringResource {
        "Peel leaves ^[\(count) folder](inflect: true) here alone"
    }

    /// Why the folders a note counts stay, a sentence for each reason that holds for any of them.
    static func whyLeftAlone(keepingWork: Int, protected: Int) -> [LocalizedStringResource] {
        var why: [LocalizedStringResource] = []
        if keepingWork > 0 {
            why.append("An app keeps work there that exists nowhere else, such as the local history of an editor.")
        }
        if protected > 0 {
            why.append("Peel protects what is there, such as what iCloud keeps to stay in sync, a wallet, the documents of an app, or a library.")
        }
        return why
    }

    /// The notice comes with the plan, without its figures until they are measured, so it never pushes the rows down.
    static func showsDeveloperNotice(for plan: SpaceRemoval.Plan) -> Bool {
        !plan.leftToDeveloper.isEmpty
    }

    /// Why the area's size in the list is more than this page can move, and where the rest is freed.
    private func developerNotice(_ plan: SpaceRemoval.Plan, sizes: [URL: Int64]) -> some View {
        let folders = plan.leftToDeveloper.sorted { SizeTotal([sizes[$1]]) < SizeTotal([sizes[$0]]) }
        return Notice(
            title: Text(Self.developerTitle(SizeTotal(folders.map { sizes[$0] }))),
            detail: Text("The Developer page frees them, keeping what is more than a cache."),
            kind: .note,
            systemImage: Tool.developer.systemImage
        ) {
            DeveloperFoldersButton(folders: folders, sizes: sizes)
            Button("Open Developer") { Navigator.shared.requestedTool = .developer }
        }
    }

    /// What the developer tools' folders hold, once Peel has measured any of them.
    static func developerTitle(_ held: SizeTotal) -> LocalizedStringResource {
        held.reading == .unknown
            ? "Part of this folder belongs to developer tools"
            : "\(held.text) of this folder belongs to developer tools"
    }

    private var header: some View {
        PageHeader(systemImage: item.category.systemImage) {
            // Beside a title that takes one line, under one that takes more, so it never stands apart.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.words.title)
                        .pageHeading()
                    about
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.words.title)
                        .pageHeading()
                    about
                }
            }
        } details: {
            FlowLayout {
                Badge(title: Text(item.category.title), systemImage: item.category.systemImage)
                if item.isReadOnly {
                    NoteBadge(
                        title: Text("Listed only"), systemImage: "hand.raised",
                        name: String(localized: "Listed only"),
                        detail: Text("Space does not touch this. How to Free It, on this page, says what does.")
                    )
                }
            }
        } trailing: {
            // Where macOS's privacy protection kept the whole area from Peel, what would measure it takes the figure's
            // place; an area with a plan has the button in its plan's note.
            if item.isReadOnly, item.whyUnknown == .needsFullDiskAccess {
                VStack(alignment: .trailing, spacing: 6) {
                    UnreadableFoldersActions(folders: [], needsFullDiskAccess: true)
                }
            } else {
                let figure = figure
                TotalLabel(total: figure.total, caption: figure.caption)
            }
        }
    }

    private var about: some View {
        InfoNote(about: Text(item.words.title), detail: Text(item.words.detail), isAlbum: false)
    }

    /// The size of what can be moved to the Trash once the plan holds something to move, else of the item's folders.
    private var figure: (total: SizeTotal, caption: Text) {
        if item.isReadOnly { return (item.size, Text("on this Mac")) }
        guard let movable = plan?.movable(canUseHelper: helper.canAct), !movable.isNothing else {
            return (item.size, Text("in here"))
        }
        return (movable, Text("to remove"))
    }

    private static func ordered(_ plan: SpaceRemoval.Plan) -> [URL] {
        plan.removable.sorted { first, second in
            SizeTotal([plan.sizes[second]]) < SizeTotal([plan.sizes[first]])
        }
    }
}

/// What frees an area's space, with what it does in a circled i beside it.
struct SpaceStep: View {
    let step: LocalizedStringResource
    var note: LocalizedStringResource?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(step)
                .font(.callout)
                .textSelection(.enabled)
                // A list row on macOS 27 draws its text on one line unless the text asks for its whole height.
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                InfoNote(about: Text(step), detail: Text(note), isAlbum: false)
            }
        }
    }
}

private struct DeveloperFoldersButton: View {
    let folders: [URL]
    let sizes: [URL: Int64]
    @State private var isShowingFolders = false

    var body: some View {
        Button("Show Folders") { isShowingFolders = true }
            .popover(isPresented: $isShowingFolders, arrowEdge: .bottom) {
                FolderListPopover(folders: folders, sizes: sizes)
            }
    }
}
