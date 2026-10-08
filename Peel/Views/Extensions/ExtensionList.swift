import PeelCore
import SwiftUI

struct ExtensionList: View {
    @Environment(ExtensionLibrary.self) private var extensions
    @State private var isRescanning = false
    @State private var searchText = ""

    private var listed: [AppExtension] {
        let all = extensions.extensions ?? []
        guard !searchText.isEmpty else { return all }
        return all.filter {
            SearchText.matches($0.name, searchText)
                || $0.owner.map { owner in SearchText.matches(owner, searchText) } == true
                || $0.point.map { point in SearchText.matches(point, searchText) } == true
                || SearchText.matches($0.identifier, searchText)
        }
    }

    var body: some View {
        @Bindable var extensions = extensions
        let filtered = listed

        List(selection: $extensions.selection) {
            // A list to show means macOS answered about at least one kind, so at most one is missing.
            if let missing = extensions.unanswered.first, !filtered.isEmpty {
                Notice(title: Text("Part of this list is missing"), detail: Text(missing.unansweredNote), kind: .note) {}
                    .padding(.vertical, 6)
                    .listRowSeparator(.hidden)
            }
            ForEach(filtered) { item in
                ExtensionRow(item: item)
            }
        }
        .accessibilityLabel(Text(Tool.extensions.title))
        .columnSearch(text: $searchText, prompt: "Search Extensions", when: extensions.extensions?.isEmpty == false)
        .scanState(phase(filtered), isRescanning: isRescanning, scan: extensions.scanRun) {
            if !extensions.unanswered.isEmpty, extensions.extensions?.isEmpty == true {
                ContentUnavailableView(
                    "macOS Didn’t Answer",
                    systemImage: "exclamationmark.triangle",
                    description: unansweredDescription
                )
            } else if extensions.extensions?.isEmpty == true {
                ContentUnavailableView(
                    "No Extensions",
                    systemImage: "puzzlepiece.extension",
                    description: Text("No app on this Mac has added an app extension or a system extension.")
                )
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .fadesInColumn(whenRowsChange: extensions.extensions?.map(\.id))
        .navigationTitle(Text(Tool.extensions.title))
        .announcesScan(
            extensions.isScanning,
            found: extensions.summary,
            couldNotLook: extensions.unanswered.isEmpty ? nil : "macOS Didn’t Answer",
            wasStopped: extensions.scanRun.wasStopped
        )
        .toolbar {
            ToolbarItem {
                RescanButton(isRunning: $isRescanning, scan: extensions.scanRun) {
                    await extensions.refresh()
                }
            }
        }
        .task {
            guard extensions.extensions == nil, !extensions.isScanning, !extensions.scanRun.wasStopped else { return }
            await extensions.refresh()
        }
        .rescanOnExclusionChange("ExtensionList") { await extensions.refresh() }
    }

    /// Why an empty list says nothing: the one kind macOS gave no answer about, or both.
    private var unansweredDescription: Text {
        if extensions.unanswered.count == 1, let missing = extensions.unanswered.first {
            return Text(missing.unansweredNote)
        }
        return Text("Peel asked macOS which extensions apps have added and got no answer. This list says nothing about what is on this Mac.")
    }

    private func phase(_ filtered: [AppExtension]) -> ScanPhase {
        if extensions.extensions == nil { return extensions.scanRun.wasStopped ? .stopped : .scanning(.walk) }
        return filtered.isEmpty ? .message : .content
    }
}

private struct ExtensionRow: View {
    let item: AppExtension

    var body: some View {
        ToolRow(systemImage: item.kind.systemImage) {
            Text(verbatim: item.name)
                .lineLimit(1)
        } details: {
            if let owner = item.owner {
                Text(verbatim: owner)
                    .lineLimit(1)
            } else if let point = item.pointName {
                Text(verbatim: point)
                    .lineLimit(1)
            }
        } trailing: {
            if item.election != .asItCame {
                HStack(spacing: 3) {
                    if item.election.needsAttention {
                        Image(systemName: "exclamationmark.circle")
                    }
                    Text(item.election.title)
                }
                .font(.caption)
                .rowTint(item.election == .on || item.election.needsAttention ? Color.accentColor : nil)
            }
        }
    }
}
