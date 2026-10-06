import PeelCore
import PeelLink
import SwiftUI

struct ContentView: View {
    @Environment(AppLibrary.self) private var library
    @Environment(OrphanLibrary.self) private var orphans
    @Environment(ProjectLibrary.self) private var projects
    @Environment(InstallerLibrary.self) private var installers
    @Environment(ExtensionLibrary.self) private var extensions
    @Environment(BackgroundItemLibrary.self) private var backgroundItems
    @Environment(PackageLibrary.self) private var packages
    @Environment(DeveloperLibrary.self) private var developer
    @Environment(DuplicateLibrary.self) private var duplicates
    @Environment(FileSearchLibrary.self) private var fileSearch
    @Environment(PluginLibrary.self) private var plugins
    @Environment(HomebrewLibrary.self) private var homebrew
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(HelperModel.self) private var helper
    @Environment(IntelLibrary.self) private var intel
    @Environment(SpaceLibrary.self) private var space
    @State private var tool: Tool = .home
    /// Nil while a tool is showing. Settings and About take the whole pane instead of the split, so they are
    /// held apart from the tool rather than folded into it, and `tool` keeps the place to come back to.
    @State private var page: SidebarDestination?
    /// What the columns draw, a moment behind `tool` and `page`, so the sidebar answers a click at once and the
    /// page is built after: building a page can hold the main thread for a noticeable time.
    @State private var drawn = Destination(tool: .home, page: nil)
    @State private var columns: NavigationSplitViewVisibility = .all
    /// 220, or what the sidebar's widest label needs in the running language (`ToolSidebar`).
    @State private var sidebarWidth = ToolSidebar.minimumWidth
    /// Too narrow for the sidebar beside what the page needs (`besideSidebar`).
    @State private var isNarrow = false
    /// The sidebar was hidden for the width, not by the user, so it comes back when there is room again.
    @State private var hidSidebarForWidth = false
    /// Held where writing it redraws nothing, since it changes at every step of a resize.
    @State private var windowWidth = WindowWidth()
    @State private var listColumn = ListColumn()
    @State private var hostWindow = HostWindow()
    /// The content's share of `WindowFloor` on the window's screen, once the window is known (`fitFloor`).
    @State private var floor: CGSize?
    @State private var searchText = ""
    private var navigator: Navigator { .shared }

    /// Every way of asking for a tool goes through here: setting `tool` alone would leave Settings or About on
    /// screen and change the tool out of sight behind them.
    private func show(_ tool: Tool) {
        self.tool = tool
        page = nil
    }

    /// What the View menu writes to, which is a request like any other.
    private var shownTool: Binding<Tool> {
        Binding(get: { tool }, set: show)
    }

    private var sidebar: some View {
        ToolSidebar(tool: $tool, page: $page, width: $sidebarWidth)
            .fixedSplitViewColumn(width: sidebarWidth)
    }

    /// Home, Tweaks, Terminal, iCloud Drive, Settings, and About are each one page rather than a list beside a
    /// detail, so they are shown in a split view with no content column: `NavigationSplitViewVisibility` cannot hide
    /// one of three. iCloud Drive's list is all it has, and its rows are the widest in the app.
    private var isWholePage: Bool {
        drawn.page != nil || [Tool.home, .tweaks, .terminal, .cloud].contains(drawn.tool)
    }

    @ViewBuilder
    private var wholePage: some View {
        switch drawn.page {
        case .settings:
            SettingsTabs()
                .navigationTitle(Text("Settings"))
        case .about:
            // No title over it: the page says what it is, in larger type than a title bar could.
            AboutContent()
                .frame(width: AboutContent.width)
                .centeredOnColumn()
                .toolbar(removing: .title)
        case .tool, nil:
            if drawn.tool == .tweaks {
                TweakPage()
            } else if drawn.tool == .terminal {
                TerminalPage()
            } else if drawn.tool == .cloud {
                CloudView()
            } else {
                HomeView()
            }
        }
    }

    var body: some View {
        Group {
            if isWholePage {
                NavigationSplitView(columnVisibility: $columns) {
                    sidebar
                } detail: {
                    wholePage
                }
            } else {
                tools
            }
        }
        // The floor is `WindowFloor`, as far as the window's screen has room for it. On a screen too narrow for the
        // sidebar beside what the page needs, the sidebar steps aside (`fitSidebar`), and Home puts its halves one
        // above the other. Growing is unrestricted.
        .frame(minWidth: floor?.width, minHeight: floor?.height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            windowWidth.value = width
            fitWidth()
            fitFloor()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { notice in
            if notice.object as? NSWindow === hostWindow.value { fitFloor() }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
        ) { _ in
            fitFloor()
        }
        .onChange(of: sidebarWidth) { fitWidth() }
        .onChange(of: drawn) { fitWidth(pageChanged: true) }
        // The columns change with the sidebar button as well as with the width.
        .onChange(of: columns) { _, shown in
            if shown == .all, isNarrow { makeRoomForSidebar() }
            fitList()
        }
        .background(HostWindowReader(host: hostWindow, found: fitFloor))
        .environment(listColumn)
        // A later turn of the run loop, after the sidebar's highlight has been committed. A choice made before
        // this one ends replaces it, so arrowing down the sidebar builds only the page it stops on.
        .task(id: Destination(tool: tool, page: page)) {
            try? await Task.sleep(for: .milliseconds(10))
            guard !Task.isCancelled else { return }
            drawn = Destination(tool: tool, page: page)
        }
        .quietTitlebarSeparators()
        .clearTitleBar()
        .measuresFrames()
        .focusedSceneValue(\.selectedTool, shownTool)
        // The page changes only for a bundle that is an app, since any app or web page can send the link.
        .onOpenURL { url in
            guard let applicationURL = OpenRequest.applicationURL(from: url) else { return }
            Task {
                if await library.reveal([applicationURL]) {
                    show(.applications)
                }
            }
        }
        // A request made while the window was closed (from a Shortcut, the Finder extension, or the menu bar
        // panel) is already set when this view appears, and `onChange` only fires on a change, so anything
        // waiting is applied here too. Keyed to `hasLoaded`, so an app named by a Shortcut is looked up once
        // the list has loaded, not in an empty list.
        .task(id: library.hasLoaded) {
            applyPendingRequest()
        }
        // The window's Undo, so Command-Z after a removal means what it means everywhere else on a Mac.
        .focusedSceneValue(\.removalHistory, history)
        .onAppear { history.canUseHelper = helper.canAct }
        .onChange(of: helper.canAct) { _, canAct in
            history.canUseHelper = canAct
        }
        .onChange(of: navigator.requestedTool) { _, requested in
            guard let requested else { return }
            show(requested)
            navigator.requestedTool = nil
        }
        .onChange(of: navigator.requestedApp) { _, app in
            guard let app, library.hasLoaded else { return }
            navigator.requestedApp = nil
            Task { await library.reveal([app]) }
        }
    }


    /// The width a page needs beside the sidebar. A tool needs its two columns, 365 and 480, the 8 points the
    /// sidebar floats in from the window's edge, and the list's divider. A page that takes the whole pane fits
    /// beside the sidebar at the window's narrowest, except Tweaks and Terminal in the languages with the longest tab
    /// titles.
    private var besideSidebar: CGFloat {
        if !isWholePage { return 365 + 480 + 8 + 1 }
        guard drawn.page == nil else { return 0 }
        return switch drawn.tool {
        case .tweaks: TweakPage.tabBarWidth
        case .terminal: TerminalPage.tabBarWidth
        default: 0
        }
    }

    /// `WindowFloor` is the window's whole frame, while a minimum height set here sizes the content under the
    /// title bar, so the title bar's height comes off it.
    private func fitFloor() {
        guard let window = hostWindow.value, let screen = window.screen else { return }
        let frame = WindowFloor.size(within: screen.visibleFrame.size)
        let titleBar = window.frame.height - window.contentLayoutRect.height
        let fitting = CGSize(width: frame.width, height: frame.height - titleBar)
        if fitting != floor { floor = fitting }
    }

    private func fitWidth(pageChanged: Bool = false) {
        let narrow = windowWidth.value < sidebarWidth + besideSidebar
        guard pageChanged || narrow != isNarrow else { return }
        if narrow != isNarrow { isNarrow = narrow }
        fitSidebar()
    }

    /// `doubleColumn` hides the sidebar of a tool's three columns, and is the same as `all` for a whole page's
    /// two, so a sidebar hidden for one kind of page is hidden again the other way when the page changes.
    private func fitSidebar() {
        let hidden: NavigationSplitViewVisibility = isWholePage ? .detailOnly : .doubleColumn
        if isNarrow, columns == .all || (hidSidebarForWidth && columns != hidden) {
            columns = hidden
            hidSidebarForWidth = true
        } else if !isNarrow, hidSidebarForWidth {
            // Inside an animation, even one of no length, SwiftUI brings the column back through AppKit's animated
            // collapse, which takes the room from the page. Without one it calls `NSSplitViewItem.setCollapsed:`,
            // and the window grows by the sidebar's width whenever the page would otherwise get too narrow.
            withAnimation(.linear(duration: 0)) { columns = .all }
            hidSidebarForWidth = false
        }
        fitList()
    }

    /// Widens the window, within its screen, when the user shows the sidebar in a window too narrow for it.
    /// Otherwise the sidebar pushes the columns past the window's left edge. `NSSplitViewItem.h` describes this
    /// for an item that keeps its siblings as they are. On a screen too narrow for that, the sidebar stays aside.
    private func makeRoomForSidebar() {
        guard let window = hostWindow.value, let screen = window.screen?.visibleFrame else { return }
        let extra = sidebarWidth + besideSidebar - windowWidth.value
        guard extra > 0 else { return }
        var frame = window.frame
        guard frame.width + extra <= screen.width else {
            columns = isWholePage ? .detailOnly : .doubleColumn
            return
        }
        frame.size.width += extra
        frame.origin.x = min(frame.minX, screen.maxX - frame.width)
        window.setFrame(frame, display: true)
    }

    /// The list takes the room its title bar needs while the sidebar is aside (`ListColumn`).
    private func fitList() {
        guard !isWholePage else { return }
        if columns == .all {
            listColumn.show(room: windowWidth.value - sidebarWidth - 8 - 481)
        } else {
            listColumn.aside(title: String(localized: drawn.tool.title))
        }
    }

    private var tools: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sidebar
        } content: {
            Group {
                switch drawn.tool {
            // Home is shown as a whole page, never as a column.
            case .home:
                EmptyView()
            case .applications:
                AppList(searchText: searchText)
                    .columnSearch(text: $searchText, prompt: "Search Applications", when: library.hasLoaded && !library.apps.isEmpty)
                    .listColumn()
            case .orphans:
                OrphanList()
                    .listColumn()
            case .developer:
                DeveloperList()
                    .listColumn()
            case .projects:
                ProjectList()
                    .listColumn()
            case .installers:
                InstallerList()
                    .listColumn()
            case .duplicates:
                DuplicateList()
                    .listColumn()
            case .cloud:
                EmptyView()
            case .fileSearch:
                FileSearchList()
                    .listColumn()
            case .backgroundItems:
                BackgroundItemList()
                    .listColumn()
            case .packages:
                PackageList()
                    .listColumn()
            case .extensions:
                ExtensionList()
                    .listColumn()
            case .plugins:
                PluginList()
                    .listColumn()
            case .homebrew:
                HomebrewList()
                    .listColumn()
            case .space:
                SpaceList()
                    .listColumn()
            case .intel:
                IntelList()
                    .listColumn()
            // Tweaks and Terminal are shown as whole pages, never as a column.
            case .tweaks, .terminal:
                EmptyView()
            case .history:
                HistoryList()
                    .listColumn()
                }
            }
            .builtWithItsTitleBar()
            // A scroll view that keeps its own background paints a panel of its own inside the column:
            // `ContentUnavailableView` is the visible case, drawing a lighter slab whose top edge reads as a
            // line under the title bar. Hidden, the window's own material shows through instead.
            .scrollContentBackground(.hidden)
        } detail: {
            Group {
                switch drawn.tool {
                case .home:
                    EmptyView()
                case .applications:
                    applicationDetail
                case .orphans:
                    orphanDetail
                case .developer:
                    developerDetail
                case .projects:
                    projectDetail
                case .installers:
                    installerDetail
                case .duplicates:
                    duplicateDetail
                case .cloud:
                    EmptyView()
                case .fileSearch:
                    fileSearchDetail
                case .backgroundItems:
                    backgroundItemDetail
                case .packages:
                    packageDetail
                case .extensions:
                    extensionDetail
                case .plugins:
                    pluginDetail
                case .homebrew:
                    homebrewDetail
                case .space:
                    spaceDetail
                case .intel:
                    intelDetail
                case .tweaks, .terminal:
                    EmptyView()
                case .history:
                    historyDetail
                }
            }
            .frame(minWidth: 480)
            .scrollContentBackground(.hidden)
            // Claims a title bar section for this column. SwiftUI only inserts its
            // `NSTrackingSeparatorToolbarItem` once both columns carry a toolbar item, and that separator is
            // what lets the divider run up through the title bar the way Notes and Mail do. An `EmptyView`
            // is dropped before it counts, so the item has to hold something; a spacer holds nothing visible.
            .toolbar {
                ToolbarItem(placement: .primaryAction) { Spacer() }
            }
        }
    }

    private func applyPendingRequest() {
        if let requested = navigator.requestedTool {
            show(requested)
            navigator.requestedTool = nil
        }
        if let app = navigator.requestedApp, library.hasLoaded {
            navigator.requestedApp = nil
            Task { await library.reveal([app]) }
        }
    }

    @ViewBuilder
    private var duplicateDetail: some View {
        if let group = duplicates.selectedFolderGroup {
            DuplicateFolderGroupView(group: group)
                .id(group.id)
        } else if let group = duplicates.selectedGroup {
            DuplicateGroupView(group: group)
                .id(group.id)
        } else if let scan = duplicates.scan, !(scan.groups.isEmpty && scan.folderGroups.isEmpty) {
            DuplicateSummaryView(scan: scan)
        } else {
            DetailPlaceholder(title: Tool.duplicates.title, systemImage: Tool.duplicates.systemImage, description: nil)
        }
    }

    @ViewBuilder
    private var fileSearchDetail: some View {
        if let file = fileSearch.chosenFile {
            FileSearchFileView(file: file)
                .id(file.id)
        } else {
            DetailPlaceholder(tool: .fileSearch, summary: fileSearch.summary, instruction: "Choose a file to see where it is.")
        }
    }

    @ViewBuilder
    private var spaceDetail: some View {
        if let item = space.selectedItem {
            SpaceDetailView(item: item)
                .id(item.id)
        } else {
            DetailPlaceholder(tool: .space, summary: space.summary, instruction: "Choose an item to see what it is and whether you can free it.")
        }
    }

    @ViewBuilder
    private var intelDetail: some View {
        if let finding = intel.selectedFinding {
            IntelDetailView(finding: finding)
                .id(finding.id)
        } else {
            DetailPlaceholder(tool: .intel, summary: intel.summary, instruction: "Choose an item to see why it still needs Rosetta.")
        }
    }

    @ViewBuilder
    private var historyDetail: some View {
        if let batch = history.selectedBatch {
            HistoryDetailView(batch: batch)
                .id(batch.id)
        } else if let refusals = history.selectedRefusals {
            RefusalDetailView(batch: refusals)
                .id(refusals.id)
        } else {
            DetailPlaceholder(tool: .history, summary: history.summary, instruction: "Choose a removal to put any of it back.")
        }
    }

    @ViewBuilder
    private var homebrewDetail: some View {
        if homebrew.progress != nil {
            HomebrewProgressView()
        } else if let package = homebrew.selectedPackage {
            HomebrewDetailView(package: package)
                .id(package.id)
        } else {
            DetailPlaceholder(tool: .homebrew, summary: homebrew.summary, instruction: "Choose a package to see its details.")
        }
    }

    @ViewBuilder
    private var pluginDetail: some View {
        if let plugin = plugins.selectedPlugin {
            PluginDetailView(plugin: plugin)
                .id(plugin.id)
        } else {
            DetailPlaceholder(tool: .plugins, summary: plugins.summary, instruction: "Choose a plug-in to see its details.")
        }
    }

    @ViewBuilder
    private var developerDetail: some View {
        if let environment = developer.selectedEnvironment {
            DeveloperDetailView(environment: environment)
                .id(environment.id)
        } else {
            DetailPlaceholder(tool: .developer, summary: developer.summary, instruction: "Choose a developer tool to see its caches.")
        }
    }

    @ViewBuilder
    private var packageDetail: some View {
        if let receipt = packages.selectedReceipt {
            PackageDetailView(receipt: receipt)
                .id(receipt.id)
        } else {
            DetailPlaceholder(tool: .packages, summary: packages.summary, instruction: "Choose a package to see what it installed.")
        }
    }

    @ViewBuilder
    private var backgroundItemDetail: some View {
        if let item = backgroundItems.selectedItem {
            BackgroundItemDetailView(item: item)
                .id(item.id)
        } else {
            DetailPlaceholder(tool: .backgroundItems, summary: backgroundItems.summary, instruction: "Choose an item to see what it runs and control it.")
        }
    }

    @ViewBuilder
    private var extensionDetail: some View {
        if let item = extensions.selectedExtension {
            ExtensionDetailView(item: item)
                .id(item.id)
        } else {
            DetailPlaceholder(tool: .extensions, summary: extensions.summary, instruction: "Choose an extension to see what it plugs into and where it came from.")
        }
    }

    @ViewBuilder
    private var installerDetail: some View {
        if let kind = installers.selection {
            InstallerDetailView(kind: kind)
                .id(kind)
        } else {
            DetailPlaceholder(tool: .installers, summary: installers.summary, instruction: "Choose a kind to see what is in it.")
        }
    }

    @ViewBuilder
    private var projectDetail: some View {
        if let group = projects.selectedGroup {
            ProjectDetailView(group: group)
                .id(group.id)
        } else {
            DetailPlaceholder(tool: .projects, summary: projects.summary, instruction: "Choose a project to see what its builds left behind.")
        }
    }

    @ViewBuilder
    private var orphanDetail: some View {
        if let group = orphans.selectedGroup {
            OrphanDetailView(group: group)
                .id(group.id)
        } else {
            DetailPlaceholder(tool: .orphans, summary: orphans.summary, instruction: "Choose a group to see the files it contains.")
        }
    }

    /// What makes a page a new page: where the app is, and which build of it is there.
    private static func build(of app: InstalledApp) -> [String] {
        [app.id.path(percentEncoded: false), app.version ?? "", app.buildVersion ?? ""]
    }

    @ViewBuilder
    private var applicationDetail: some View {
        if let app = library.selectedApp {
            // Keyed to the build, not only to the path: a page keeps the app it was made with, so after an
            // upgrade made elsewhere it would show the old version, and Rescan would ask about that one.
            AppDetailView(app: app)
                .id(Self.build(of: app))
        } else if library.isShowingSeveral {
            MultipleAppsView(apps: library.selectedApps)
                .id(library.selectedApps.map(Self.build))
        } else {
            ApplicationsPlaceholder()
        }
    }
}

/// The Applications pane with no app chosen. A view of its own because its summary reads every app's size and
/// update: read in the window's body, each size measured would build the whole window again.
private struct ApplicationsPlaceholder: View {
    @Environment(AppLibrary.self) private var library

    var body: some View {
        DetailPlaceholder(tool: .applications, summary: library.summary, instruction: "Choose an app to see what it leaves behind.")
    }
}

/// A page of the window: a tool, or one of the pages that take the whole pane.
private struct Destination: Equatable {
    var tool: Tool
    var page: SidebarDestination?
}

/// The window's width, outside SwiftUI's state: see `ContentView.windowWidth`.
private final class WindowWidth {
    var value: CGFloat = 0
}

/// The window the view is in, held the same way.
private final class HostWindow {
    weak var value: NSWindow?
}

private struct HostWindowReader: NSViewRepresentable {
    let host: HostWindow
    /// Called once the view is in a window.
    let found: @MainActor () -> Void

    func makeNSView(context: Context) -> Reader {
        Reader(host: host, found: found)
    }

    func updateNSView(_ nsView: Reader, context: Context) {}

    final class Reader: NSView {
        let host: HostWindow
        let found: @MainActor () -> Void

        init(host: HostWindow, found: @escaping @MainActor () -> Void) {
            self.host = host
            self.found = found
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            host.value = window
            // On a later turn, since what it changes is SwiftUI state and this can run inside SwiftUI's update.
            if window != nil {
                Task { found() }
            }
        }
    }
}
