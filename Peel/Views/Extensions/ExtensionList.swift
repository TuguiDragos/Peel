import PeelCore
import SwiftUI

struct ExtensionList: View {
    @Environment(ExtensionLibrary.self) private var extensions
    @State private var isRescanning = false
    @State private var searchText = ""

    private var listed: [AppExtension] {
        let all = extensions.extensions ?? []
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.matches(searchText) }
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
            let versioned = Set(Dictionary(grouping: extensions.extensions ?? [], by: \.identifier).filter {
                $0.value.count > 1
            }.keys)
            ForEach(filtered) { item in
                ExtensionRow(item: item, showsVersion: versioned.contains(item.identifier))
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
            found: announcement,
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
        // What macOS runs changes in System Settings and with every app installed or removed, so once read the page
        // looks again, quietly, each time it is shown and each time Peel comes forward.
        .task {
            guard extensions.extensions == nil else {
                await extensions.readAgain()
                return
            }
            guard !extensions.scanRun.isWaitedFor, !extensions.scanRun.wasStopped else { return }
            await extensions.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await extensions.readAgain() }
        }
        .rescanOnExclusionChange("ExtensionList") { await extensions.refresh() }
    }

    /// Why an empty list says nothing: the one kind macOS gave no answer about, or both.
    /// What VoiceOver hears when a scan ends: what it found, and that part of the list is missing when it is.
    private var announcement: AttributedString? {
        guard let found = extensions.summary else { return nil }
        guard !extensions.unanswered.isEmpty else { return found }
        return found + " " + AttributedString(localized: "Part of this list is missing.")
    }

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
    /// True when another row has the same identifier, as the old and the new version during an update.
    let showsVersion: Bool

    var body: some View {
        ToolRow(systemImage: item.kind.systemImage, symbolName: item.kind.title) {
            Text(verbatim: item.name)
                .lineLimit(1)
        } details: {
            if showsVersion, let version = item.shownVersion {
                Text("Version \(version)")
                    .lineLimit(1)
            } else if let detail = item.rowDetail {
                Text(verbatim: detail)
                    .lineLimit(1)
            }
        } trailing: {
            if item.showsItsState, item.election != .asItCame {
                Group {
                    if let mark = item.election.mark {
                        StatusLabel(title: Text(item.election.title), systemImage: mark, tint: .accentColor)
                    } else {
                        Text(item.election.title)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
