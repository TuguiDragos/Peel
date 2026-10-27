import PeelCore
import SwiftUI

struct PluginList: View {
    @Environment(PluginLibrary.self) private var plugins
    @State private var searchText = ""
    @State private var isRescanning = false

    var body: some View {
        @Bindable var plugins = plugins
        let filtered = filteredPlugins
        let byCategory = Dictionary(grouping: filtered, by: \.category)
        let forAllUsers = Plugin.sayingForAllUsers(plugins.plugins ?? [])

        List(selection: $plugins.selection) {
            if plugins.plugins?.isEmpty == false {
                if plugins.needsFullDiskAccess || !plugins.unreadable.isEmpty {
                    UnreadableFoldersNotice(
                        folders: plugins.unreadable,
                        needsFullDiskAccess: plugins.needsFullDiskAccess
                    )
                }
            }
            ForEach(Plugin.Category.allCases, id: \.self) { category in
                if let items = byCategory[category] {
                    Section {
                        ForEach(items) { plugin in
                            HStack(spacing: 10) {
                                AppIcon(url: plugin.url)
                                    .frame(width: 24, height: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: plugin.name)
                                        .lineLimit(1)
                                    let details = [
                                        plugin.version,
                                        forAllUsers.contains(plugin.id) ? String(localized: "All users") : nil,
                                    ].compactMap(\.self)
                                    if !details.isEmpty {
                                        Text(verbatim: details.joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 6)
                                Text(plugin.size.byteCount)
                                    .rowFigure()
                            }
                            .padding(.vertical, 2)
                            .contextMenu {
                                ItemMenu(url: plugin.url)
                            }
                        }
                        .listRowSeparator(.hidden)
                    } header: {
                        Text(category.title)
                    }
                }
            }
        }
        .accessibilityLabel(Text(Tool.plugins.title))
        .scrollBarBelowSectionHeaders(!byCategory.isEmpty)
        .scanState(phase(filtered), isRescanning: isRescanning, scan: plugins.scanRun) {
            if plugins.plugins?.isEmpty == true, !plugins.unreadable.isEmpty {
                ContentUnavailableView {
                    Label("Not Everything Could Be Read", systemImage: "exclamationmark.triangle")
                } description: {
                    let named = Text("No plug-ins were found, but Peel couldn’t look inside \(RemovalFailureAlert.listedFolders(plugins.unreadable.map(\.abbreviatedPath))), so there may be some there.")
                    if plugins.needsFullDiskAccess {
                        Text("\(named)\n\n\(Text("Give Peel Full Disk Access so it can read the folders macOS protects."))")
                    } else {
                        named
                    }
                } actions: {
                    UnreadableFoldersActions(
                        folders: plugins.unreadable,
                        needsFullDiskAccess: plugins.needsFullDiskAccess
                    )
                }
            } else if plugins.plugins?.isEmpty == true {
                ContentUnavailableView(
                    "No Plug-ins",
                    systemImage: "powerplug",
                    description: Text("Plug-ins installed on this Mac will appear here.")
                )
            } else {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .columnSearch(text: $searchText, prompt: "Search Plug-ins", when: plugins.plugins?.isEmpty == false)
        .fadesInColumn(whenRowsChange: plugins.plugins?.map(\.id))
        .navigationTitle(Text(Tool.plugins.title))
        .announcesScan(
            plugins.isScanning,
            found: plugins.summary,
            couldNotLook: plugins.plugins?.isEmpty == true && !plugins.unreadable.isEmpty
                ? "Not Everything Could Be Read" : nil,
            wasStopped: plugins.scanRun.wasStopped
        )
        .toolbar {
            ToolbarItem {
                RescanButton(isRunning: $isRescanning, isDisabled: plugins.isRemoving, scan: plugins.scanRun) {
                    await plugins.refresh()
                }
            }
        }
        .task {
            guard plugins.plugins == nil, !plugins.scanRun.isWaitedFor, !plugins.scanRun.wasStopped else { return }
            await plugins.refresh()
        }
        .rescanOnExclusionChange("PluginList") { await plugins.refresh() }
        .rescanAfterPutBack(.plugins) { await plugins.refresh() }
    }

    private func phase(_ filtered: [Plugin]) -> ScanPhase {
        if plugins.plugins == nil { return plugins.scanRun.wasStopped ? .stopped : .scanning(.walk) }
        if plugins.plugins?.isEmpty == true { return .message }
        if filtered.isEmpty, !searchText.isEmpty { return .message }
        return .content
    }

    private var filteredPlugins: [Plugin] {
        let all = plugins.plugins ?? []
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.matches(searchText) }
    }
}

extension Plugin {
    /// Whether a search for `text` finds it: by its name, by its file's name, which Finder shows, or by its identifier.
    func matches(_ text: String) -> Bool {
        [name, url.deletingPathExtension().lastPathComponent, bundleIdentifier].contains {
            $0.map { SearchText.matches($0, text) } == true
        }
    }

    /// The copies for all users of the plug-ins installed in both Libraries, whose rows would otherwise read alike.
    static func sayingForAllUsers(_ plugins: [Plugin]) -> Set<Plugin.ID> {
        let sameName = Dictionary(grouping: plugins) { "\($0.category.rawValue)/\($0.name)" }.values
        return Set(sameName.filter { copies in copies.contains { !$0.isInstalledForAllUsers } }
            .flatMap { copies in copies.filter(\.isInstalledForAllUsers).map(\.id) })
    }
}

extension Plugin.Category {
    var title: LocalizedStringResource {
        switch self {
        case .audioUnits: "Audio Units"
        case .audioDrivers: "Audio Drivers"
        case .vst: "VST Plug-ins"
        case .vst3: "VST3 Plug-ins"
        case .clap: "CLAP Plug-ins"
        case .midiDrivers: "MIDI Drivers"
        case .internetPlugIns: "Internet Plug-ins"
        case .preferencePanes: "Preference Panes"
        case .quickLook: "Quick Look Plug-ins"
        case .screenSavers: "Screen Savers"
        case .spotlight: "Spotlight Importers"
        case .services: "Services"
        case .inputMethods: "Input Methods"
        case .colorPickers: "Color Pickers"
        case .contextualMenuItems: "Contextual Menu Items"
        case .mailBundles: "Mail Plug-ins"
        case .aax: "AAX Plug-ins"
        case .mas: "MAS Plug-ins"
        case .imageUnits: "Image Units"
        case .dictionaries: "Dictionaries"
        case .automatorActions: "Automator Actions"
        case .contactsPlugIns: "Contacts Plug-ins"
        }
    }
}
