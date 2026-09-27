import PeelCore
import SwiftUI

struct DeveloperDetailView: View {
    @Environment(DeveloperLibrary.self) private var developer
    let environment: DeveloperEnvironment

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)
            RemovalsHeldBanner()

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
            RemovalBar(page: Tool.developer.page(environment.id), isScanning: developer.isScanning, scan: developer.scanRun)
        }
        .fadesInColumn(whenRowsChange: environment.locations.map(\.id))
        .navigationTitle(environment.name)
        .toolbar(removing: .title)
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
                        detail: Text("Archives, symbols from your devices, model weights, installed environments, downloads kept to install again, and anything Peel couldn’t measure are listed but never selected for you.")
                    )
                }
            }
        } trailing: {
            TotalLabel(total: environment.total, caption: Text("in here"))
        }
    }

    private var keptByDefault: Int {
        environment.locations.count { !$0.isRecommended }
    }
}

extension DeveloperEnvironment.ContentKind {
    var title: LocalizedStringResource {
        switch self {
        case .buildData: "Build data, made again when you build"
        case .downloads: "Packages, downloaded again when needed"
        case .cache: "Cache, made again as you use the tool"
        case .logs: "Logs of what the tool did, which nothing makes again"
        case .deviceSupport: "Symbols from your devices, needed to read their crash reports"
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
