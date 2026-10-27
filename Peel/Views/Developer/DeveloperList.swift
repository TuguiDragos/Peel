import PeelCore
import SwiftUI

struct DeveloperList: View {
    @Environment(DeveloperLibrary.self) private var developer
    @State private var isRescanning = false
    @State private var searchText = ""

    private var listed: [DeveloperEnvironment] {
        developer.environments(matching: searchText)
    }

    var body: some View {
        @Bindable var developer = developer

        List(listed, selection: $developer.selection) { environment in
            DeveloperRow(environment: environment)
        }
        .accessibilityLabel(Text(Tool.developer.title))
        .columnSearch(text: $searchText, prompt: "Search Developer Caches", when: developer.environments?.isEmpty == false)
        .scanState(phase, isRescanning: isRescanning, scan: developer.scanRun) {
            if developer.environments?.isEmpty == true {
                ContentUnavailableView(
                    "No Developer Caches",
                    systemImage: "hammer",
                    description: Text("Caches of developer tools, browsers, and apps built on Electron appear here.")
                )
            } else if listed.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .fadesInColumn(whenRowsChange: developer.environments?.map(\.id))
        .navigationTitle(Text(Tool.developer.title))
        .announcesScan(developer.isScanning, found: developer.summary, wasStopped: developer.scanRun.wasStopped)
        .toolbar {
            ToolbarItem {
                SelectOnEveryPage(
                    pages: SelectablePages(listed.map { ($0.page, $0.selectableRows) }),
                    selection: developer
                ) { page in
                    guard developer.selection == nil, let environment = listed.first(where: { $0.page == page }) else {
                        return
                    }
                    developer.selection = environment.id
                }
            }
            ToolbarItem {
                RescanButton(isRunning: $isRescanning, isDisabled: developer.isRemoving, scan: developer.scanRun) {
                    await developer.refresh()
                }
            }
        }
        .task {
            guard developer.environments == nil, !developer.scanRun.isWaitedFor, !developer.scanRun.wasStopped else {
                return
            }
            await developer.refresh()
        }
        .rescanOnExclusionChange("DeveloperList") { await developer.refresh() }
        .rescanAfterPutBack(.developer) { await developer.refresh() }
    }

    private var phase: ScanPhase {
        if developer.environments == nil { return developer.scanRun.wasStopped ? .stopped : .scanning(.walk) }
        return listed.isEmpty ? .message : .content
    }
}

private struct DeveloperRow: View {
    let environment: DeveloperEnvironment

    var body: some View {
        ToolRow(systemImage: environment.systemImage) {
            Text(verbatim: environment.name)
                .lineLimit(1)
        } details: {
            Text("^[\(environment.locations.count) item](inflect: true)")
        } trailing: {
            Text(environment.total.text)
                .rowFigure()
        }
    }
}
