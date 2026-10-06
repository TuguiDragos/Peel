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
                        detail: detail(for: location),
                        warning: warning(for: location),
                        lastWritten: location.lastWritten,
                        size: location.size ?? 0,
                        isMeasured: location.size != nil,
                        isFirst: index == 0,
                        selection: developer, isSelected: developer.isSelected(location.url)
                    )
                }
                .listRowSeparator(.hidden)
            } header: {
                SectionHeaderLine {
                    Text("Caches")
                } actions: {
                    SelectMenu(
                        list: environment.selectableRows,
                        place: Text(verbatim: environment.name),
                        selection: developer
                    )
                }
            }
        }
        .scrollBarBelowSectionHeaders()
        .dimmedWhileBusy(developer.isScanning)
        .edgeBar(.bottom) {
            RemovalBar(
                page: environment.page,
                isScanning: developer.isScanning,
                scan: developer.scanRun
            )
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
                        detail: Text("Archives, symbols from your devices, model weights, installed environments, downloads kept to install again, the build data of a project opened in the last week, an editor’s state for a project that is gone, folders nothing shows the tool made, and anything Peel couldn’t measure are listed but never selected for you.")
                    )
                }
            }
        } trailing: {
            TotalLabel(total: environment.total, caption: Text("in here"))
        }
    }

    private func detail(for location: DeveloperEnvironment.Location) -> LocalizedStringResource {
        if let workspace = location.workspace { return "Build data for \(workspace.name), made again when you build" }
        if let project = location.project { return "Kept for \(project), a project no longer on this Mac" }
        guard let version = location.archive?.label else { return location.kind.title }
        return "Version \(version), needed to read its crash reports"
    }

    private func warning(for location: DeveloperEnvironment.Location) -> String? {
        if location.size == nil {
            return String(
                localized: location.couldNotBeRead
                    ? HoldBack.couldNotBeRead.explanation
                    : HoldBack.notMeasured.explanation
            )
        }
        if !location.isTheTools {
            return String(localized: "Not selected: nothing shows that \(environment.name) made this folder.")
        }
        if let workspace = location.workspace, workspace.mayStillBeInUse {
            return String(localized: "Not selected: \(workspace.name) was opened in the last week, so its build data may be needed again soon.")
        }
        return nil
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
        case .projectState: "An editor’s state for a project that is gone, its chat history included"
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
        case .projectState: "folder.badge.questionmark"
        }
    }
}
