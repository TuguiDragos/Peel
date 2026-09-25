import PeelCore
import SwiftUI

struct DeveloperDetailView: View {
    @Environment(DeveloperLibrary.self) private var developer
    @Environment(RemovalHistoryStore.self) private var history
    @State private var isConfirmingRemoval = false
    @Environment(RemovalOutcome.self) private var outcome
    @State private var isShowingQuitAlert = false
    /// The app the quit alert names: whichever of the environment's apps is running.
    @State private var appToQuit = ""
    let environment: DeveloperEnvironment

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)
            ExclusionsUnreadableBanner()

            Section {
                ForEach(Array(environment.locations.enumerated()), id: \.element.id) { index, location in
                    RemovalRow(
                        url: location.url,
                        icon: .symbol(location.kind.symbolName),
                        detail: location.kind.title,
                        warning: location.size == nil ? String(localized: location.couldNotBeRead ? HoldBack.couldNotBeRead.explanation : HoldBack.notMeasured.explanation) : nil,
                        size: location.size ?? 0,
                        isMeasured: location.size != nil,
                        isFirst: index == 0,
                        selection: developer, isSelected: developer.isSelected(location.url)
                    )
                }
                .listRowSeparator(.hidden)
            } header: {
                Text("Caches")
            }
        }
        .dimmedWhileBusy(developer.isScanning)
        .safeAreaBar(edge: .bottom) {
            RemovalBar(
                selectedSize: selected.known,
                isSelectionMeasured: selected.isComplete,
                isScanning: developer.isScanning,
                scan: developer.scanRun,
                isEnabled: !selectedLocations.isEmpty && !developer.isRemoving && !developer.isScanning,
                onRemove: requestRemoval
            )
        }
        .fadesInColumn(whenRowsChange: environment.locations.map(\.id))
        .navigationTitle(environment.name)
        .toolbar(removing: .title)
        .confirmationDialog(Text.movingToTrash(selectedLocations.count, selected), isPresented: $isConfirmingRemoval) {
            Button("Move to Trash") {
                Task {
                    let result = await developer.removeSelected(from: environment) { result in
                        await history.record(
                            result,
                            tool: .developer,
                            source: environment.name,
                            sizes: [URL: Int64](measured: environment.locations.map { ($0.url, $0.size) })
                        )
                    }
                    // A nil result means nothing moved: one of the environment's apps was opened in the meantime.
                    guard let result else {
                        askToQuit()
                        return
                    }
                    outcome.report(result)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Quit \(appToQuit) before removing its files.", isPresented: $isShowingQuitAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    private var header: some View {
        PageHeader(systemImage: environment.systemImage) {
            Text(verbatim: environment.name)
                .pageTitle()
        } details: {
            FlowLayout {
                Badge(
                    title: Text("^[\(environment.locations.count) folder](inflect: true)"),
                    systemImage: "folder"
                )
                if keptByDefault > 0 {
                    NoteBadge(
                        title: Text("\(keptByDefault) kept"), systemImage: "hand.raised", tint: .secondary,
                        name: String(localized: "\(keptByDefault) kept"),
                        detail: Text("Archives, model weights, installed environments, downloads kept to install again, and anything Peel couldn’t measure are listed but never selected for you.")
                    )
                }
            }
        } trailing: {
            TotalLabel(total: environment.total, caption: Text("in here"))
                .accessibilityLabel(Text(verbatim: environment.total.text))
        }
    }

    private var keptByDefault: Int {
        environment.locations.count { !$0.isRecommended }
    }

    private var selectedLocations: [DeveloperEnvironment.Location] {
        environment.locations.filter { developer.selectedURLs.contains($0.url) }
    }

    private var selected: SizeTotal {
        SizeTotal(selectedLocations.map(\.size))
    }

    private func requestRemoval() {
        if developer.runningApp(of: environment) != nil {
            askToQuit()
        } else {
            isConfirmingRemoval = true
        }
    }

    private func askToQuit() {
        appToQuit = developer.runningApp(of: environment) ?? environment.name
        isShowingQuitAlert = true
    }
}

extension DeveloperEnvironment.ContentKind {
    var title: LocalizedStringResource {
        switch self {
        case .buildData: "Build data, made again when you build"
        case .downloads: "Packages, downloaded again when needed"
        case .cache: "Cache, made again as you use the tool"
        case .logs: "Logs of what the tool did, which nothing makes again"
        case .deviceSupport: "Device support files, downloaded again when a device connects"
        case .archives: "App archives, needed to read crash reports"
        case .models: "Model weights or datasets, a long download to get back"
        case .environments: "Installed packages, put back by installing them again"
        case .keptDownloads: "Downloads kept so you can install them again"
        }
    }

    var symbolName: String {
        switch self {
        case .buildData: "hammer"
        case .downloads: "arrow.down.circle"
        case .cache: "archivebox"
        case .logs: "doc.text"
        case .deviceSupport: "iphone"
        case .archives: "archivebox.fill"
        case .models: "brain"
        case .environments: "shippingbox.and.arrow.backward"
        case .keptDownloads: "tray.and.arrow.down"
        }
    }
}
