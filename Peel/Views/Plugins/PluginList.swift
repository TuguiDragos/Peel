import PeelCore
import SwiftUI

struct PluginList: View {
    @Environment(PluginLibrary.self) private var plugins
    @Environment(HomeModel.self) private var home
    @State private var searchText = ""
    @State private var isRescanning = false

    var body: some View {
        @Bindable var plugins = plugins
        let filtered = filteredPlugins
        let byCategory = Dictionary(grouping: filtered, by: \.category)

        List(selection: $plugins.selection) {
            if plugins.plugins?.isEmpty == false {
                if plugins.needsFullDiskAccess {
                    FullDiskAccessBanner()
                } else if !plugins.unreadable.isEmpty {
                    UnreadableFoldersNotice(folders: plugins.unreadable)
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
                                    if let version = plugin.version {
                                        Text(verbatim: version)
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
                    if plugins.needsFullDiskAccess {
                        Text("No plug-ins were found, but Peel couldn’t look in ^[\(plugins.unreadable.count) folder](inflect: true), so there may be some there. Give Peel Full Disk Access to look there too.")
                    } else {
                        Text("No plug-ins were found, but Peel couldn’t look inside \(plugins.unreadable.map(\.abbreviatedPath).formatted(.list(type: .and))), so there may be some there.")
                    }
                } actions: {
                    if plugins.needsFullDiskAccess {
                        Button("Open System Settings") { home.openFullDiskAccessSettings() }
                    }
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
            guard plugins.plugins == nil, !plugins.isScanning, !plugins.scanRun.wasStopped else { return }
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
        return all.filter {
            SearchText.matches($0.name, searchText)
                || $0.bundleIdentifier.map { identifier in SearchText.matches(identifier, searchText) } == true
        }
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
