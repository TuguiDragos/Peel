import PeelCore
import SwiftUI

struct DeveloperList: View {
    @Environment(DeveloperLibrary.self) private var developer
    @State private var isRescanning = false
    @State private var searchText = ""

    private var listed: [DeveloperEnvironment] {
        let all = developer.environments ?? []
        guard !searchText.isEmpty else { return all }
        return all.filter { SearchText.matches($0.name, searchText) }
    }

    var body: some View {
        @Bindable var developer = developer

        List(listed, selection: $developer.selection) { environment in
            DeveloperRow(environment: environment)
        }
        .columnSearch(text: $searchText, prompt: "Search Developer Caches", when: developer.environments?.isEmpty == false)
        .scanState(phase, isRescanning: isRescanning, scan: developer.scanRun) {
            if developer.environments?.isEmpty == true {
                ContentUnavailableView(
                    "No Developer Caches",
                    systemImage: "hammer",
                    description: Text("Caches from developer tools will appear here.")
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
                RescanButton(isRunning: $isRescanning, isDisabled: developer.isRemoving, scan: developer.scanRun) {
                    await developer.refresh()
                }
            }
        }
        .task {
            guard developer.environments == nil, !developer.isScanning, !developer.scanRun.wasStopped else { return }
            await developer.refresh()
        }
        .rescanOnExclusionChange("DeveloperList") { await developer.refresh() }
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
            Text("^[\(environment.locations.count) folder](inflect: true)")
        } trailing: {
            Text(environment.total.text)
                .rowFigure()
        }
    }
}
