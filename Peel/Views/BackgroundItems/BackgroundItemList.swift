import PeelCore
import SwiftUI

struct BackgroundItemList: View {
    @Environment(AppLibrary.self) private var library
    @Environment(BackgroundItemLibrary.self) private var backgroundItems
    @State private var searchText = ""
    @State private var isRescanning = false

    var body: some View {
        @Bindable var backgroundItems = backgroundItems
        let filtered = filteredItems

        List(selection: $backgroundItems.selection) {
            section(Text("Agents"), items: filtered.filter { $0.kind == .agent })
            section(Text("Daemons"), items: filtered.filter { $0.kind == .daemon })
        }
        .scanState(phase(filtered), isRescanning: isRescanning, scan: backgroundItems.scanRun) {
            if backgroundItems.items?.isEmpty == true {
                ContentUnavailableView(
                    "No Background Items",
                    systemImage: "gearshape.2",
                    description: Text("Apps that run in the background will appear here.")
                )
            } else {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .columnSearch(text: $searchText, prompt: "Search Background Items", when: backgroundItems.items?.isEmpty == false)
        .fadesInColumn(whenRowsChange: backgroundItems.items?.map(\.id))
        .navigationTitle(Text(Tool.backgroundItems.title))
        .announcesScan(backgroundItems.isScanning, found: backgroundItems.summary, wasStopped: backgroundItems.scanRun.wasStopped)
        .toolbar {
            ToolbarItem {
                RescanButton(isRunning: $isRescanning, isDisabled: !library.hasLoaded || !backgroundItems.runningActionItemIDs.isEmpty, scan: backgroundItems.scanRun) {
                    await backgroundItems.refresh(installedApps: library.apps)
                }
            }
        }
        // The first scan waits for the installed apps, which it needs to trace each item to the app that owns it.
        .task(id: library.hasLoaded) {
            guard library.hasLoaded, backgroundItems.items == nil, !backgroundItems.isScanning, !backgroundItems.scanRun.wasStopped else { return }
            await backgroundItems.refresh(installedApps: library.apps)
        }
        .rescanOnExclusionChange("BackgroundItemList") { await backgroundItems.refresh(installedApps: library.apps) }
        // Shown from the list, which stays on screen. An alert on the item's page would vanish with the page if
        // the rescan after the action removed the item, and then show up on the next item the user opens.
        .alert(failureTitle, isPresented: isShowingFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            failureMessage
        }
    }

    private func phase(_ filtered: [BackgroundItem]) -> ScanPhase {
        if backgroundItems.items == nil { return backgroundItems.scanRun.wasStopped ? .stopped : .scanning(.walk) }
        if backgroundItems.items?.isEmpty == true { return .message }
        if filtered.isEmpty, !searchText.isEmpty { return .message }
        return .content
    }

    private var isShowingFailure: Binding<Bool> {
        Binding(
            get: { backgroundItems.failure != nil },
            set: { if !$0 { backgroundItems.failure = nil } }
        )
    }

    private var failureTitle: Text {
        switch backgroundItems.failure?.action {
        case .start: Text("The item couldn’t be started.")
        case .stop: Text("The item couldn’t be stopped.")
        case .enable: Text("The item couldn’t be enabled.")
        case .disable: Text("The item couldn’t be disabled.")
        case .moveToTrash: Text("The item couldn’t be moved to the Trash.")
        case nil: Text(verbatim: "")
        }
    }

    private var failureMessage: Text {
        switch backgroundItems.failure?.reason {
        case .requiresPrivileges: Text("It needs administrator access, which Peel’s helper provides.")
        case .noFileToMove: Text("This one comes from the app itself, so there is no file to move. Remove the app to get rid of it.")
        case .launchctl(let output): Text(verbatim: FixedSentence.translated(output))
        case .trash(let reason): Text(verbatim: reason.explanation)
        case .quarantinedPlist: Text("macOS won’t load this: its configuration file carries the mark macOS puts on downloads. Reinstalling the app that put it there may write it again without the mark.")
        case nil: Text(verbatim: "")
        }
    }

    @ViewBuilder
    private func section(_ title: Text, items: [BackgroundItem]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    BackgroundItemRow(item: item, ownerName: ownerName(of: item))
                }
            } header: {
                title
            }
        }
    }

    private var filteredItems: [BackgroundItem] {
        let items = backgroundItems.items ?? []
        guard !searchText.isEmpty else { return items }
        return items.filter { item in
            SearchText.matches(item.label, searchText) || ownerName(of: item).map { SearchText.matches($0, searchText) } == true
        }
    }

    /// The owner's name as the item's page gives it: the name found with the owner, which knows an app outside the
    /// scanned folders, and else the installed app's.
    private func ownerName(of item: BackgroundItem) -> String? {
        item.ownerBundleIdentifier.map { item.ownerName ?? library.name(forBundleIdentifier: $0) }
    }
}

private struct BackgroundItemRow: View {
    let item: BackgroundItem
    let ownerName: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            BackgroundItemStateIndicator(item: item)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.isOrphan {
                    Text("Nothing left to run")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                } else if let ownerName {
                    Group {
                        if item.isOwnerConfirmed {
                            Text(ownerName)
                        } else {
                            Text("Named like \(ownerName)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            // Only for a file Peel can move to the Trash. A job an app registered goes with the app, and a job
            // with an Apple label is left alone.
            if item.canMoveToTrash, let plist = item.plistURL {
                ItemMenu(url: plist)
            }
        }
    }
}

struct BackgroundItemStateIndicator: View {
    let item: BackgroundItem

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .imageScale(.small)
            .accessibilityLabel(label)
    }

    // A state Peel could not read comes first, since whether the job is disabled may not have been read either.
    private var symbol: String {
        switch item.state {
        case .unknown: "questionmark.circle.dashed"
        case _ where item.isDisabled: "minus.circle.fill"
        case .running: "circle.fill"
        case .loaded: "circle"
        case .notLoaded: "circle.dashed"
        }
    }

    private var color: Color {
        switch item.state {
        case .unknown: .secondary
        case _ where item.isDisabled: .orange
        case .running: .green
        case .loaded, .notLoaded: .secondary
        }
    }

    private var label: Text {
        switch item.state {
        case .unknown: Text(.unknownBackgroundItemState)
        case _ where item.isDisabled: Text("Disabled")
        case .running: Text("Running")
        case .loaded: Text("Not running")
        case .notLoaded: Text("Not loaded")
        }
    }
}

extension LocalizedStringResource {
    /// The state of a background item when `launchctl` did not say it in a form Peel can read.
    static let unknownBackgroundItemState = LocalizedStringResource(
        "Unknown (background item state)",
        defaultValue: "Unknown"
    )
}
