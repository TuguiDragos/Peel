import PeelCore
import SwiftUI

struct ProjectList: View {
    @Environment(ProjectLibrary.self) private var projects
    @Environment(HomeModel.self) private var home
    @State private var isRescanning = false
    @State private var searchText = ""

    private var isShowingRefusal: Binding<Bool> {
        Binding(
            get: { !projects.refused.isEmpty },
            set: { if !$0 { projects.clearRefusals() } }
        )
    }

    private var listed: [ProjectGroup] {
        let all = projects.groups ?? []
        guard !searchText.isEmpty else { return all }
        return all.filter { group in
            SearchText.matches(group.project.lastPathComponent, searchText)
                || group.artifacts.contains { $0.matches(searchText) }
        }
    }

    var body: some View {
        @Bindable var projects = projects
        let filtered = listed

        List(selection: $projects.selection) {
            if projects.needsFullDiskAccess, !filtered.isEmpty {
                FullDiskAccessBanner()
            } else if !projects.unreadable.isEmpty, !filtered.isEmpty {
                UnreadableFoldersNotice(folders: projects.unreadable)
            }
            ForEach(filtered) { group in
                ProjectRow(group: group)
            }
        }
        .accessibilityLabel(Text(Tool.projects.title))
        .columnSearch(text: $searchText, prompt: "Search Build Artifacts", when: projects.groups?.isEmpty == false)
        .scanState(phase(filtered), isRescanning: isRescanning, scan: projects.scanRun) {
            if projects.folders.isEmpty {
                ContentUnavailableView {
                    Label("No Folders Yet", systemImage: "folder.badge.gearshape")
                } description: {
                    Text("Choose where your projects live. Peel looks for what their builds left behind.")
                } actions: {
                    Button("Choose a Folder…") {
                        Task { await projects.addFolder() }
                    }
                    .buttonStyle(.borderedProminent)
                    ForEach(projects.suggestedFolders, id: \.self) { folder in
                        Button("Add “\(folder.lastPathComponent)”") {
                            Task { await projects.add([folder]) }
                        }
                    }
                }
            } else if !searchText.isEmpty, projects.groups?.isEmpty == false, filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if projects.groups?.isEmpty == true, projects.needsFullDiskAccess {
                ContentUnavailableView {
                    Label("Not Everything Could Be Read", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("No build output was found, but macOS kept Peel out of a folder you chose. Give Peel Full Disk Access to look there too.")
                } actions: {
                    Button("Open System Settings") { home.openFullDiskAccessSettings() }
                }
            } else if projects.groups?.isEmpty == true, !projects.unreadable.isEmpty {
                ContentUnavailableView {
                    Label("Not Everything Could Be Read", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Peel couldn’t look inside \(projects.unreadable.map(\.abbreviatedPath).formatted(.list(type: .and))), so something may be there that isn’t listed here.")
                }
            } else if projects.groups?.isEmpty == true {
                ContentUnavailableView(
                    "Nothing Built Here",
                    systemImage: "checkmark.seal",
                    description: Text("No build output was found in the folders you chose.")
                )
            }
        }
        .edgeBar(.bottom) {
            Group {
                if projects.wasCutShort {
                    Text("There were more folders than Peel looks at in one go, so this list isn’t all of them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
            }
            .motion(.settle, .movement, value: projects.wasCutShort)
        }
        .alert(projects.refused.count == 1 ? "That folder can’t be searched." : "These folders can’t be searched.", isPresented: isShowingRefusal) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: projects.refused.map { "\($0.url.abbreviatedPath)\n\($0.reason.explanation)" }.joined(separator: "\n\n"))
        }
        .fadesInColumn(whenRowsChange: projects.groups?.map(\.id))
        .navigationTitle(Text(Tool.projects.title))
        .announcesScan(
            projects.isScanning,
            found: projects.summary,
            couldNotLook: projects.folders.isEmpty ? "No Folders Yet"
                : !projects.unreadable.isEmpty ? "Not Everything Could Be Read" : nil,
            wasStopped: projects.scanRun.wasStopped
        )
        .toolbar {
            ToolbarItem {
                Menu {
                    // The title says what the item does. A bare path would read as a list of folders, and in macOS 27
                    // and later AppKit typically hides menu item images (`NSMenuItem.h`), so the symbol may not show.
                    ForEach(projects.folders, id: \.self) { folder in
                        Button("Stop Looking in \(folder.abbreviatedPath)", systemImage: "minus.circle") {
                            Task { await projects.removeFolder(folder) }
                        }
                    }
                    if !projects.folders.isEmpty {
                        Divider()
                    }
                    Button("Add Folder…", systemImage: "plus") {
                        Task { await projects.addFolder() }
                    }
                } label: {
                    ToolbarMenuLabel(title: "Folders", systemImage: "folder")
                }
                .help(Text("The folders Peel looks through"))
            }
            ToolbarItem {
                SelectOnEveryPage(
                    pages: SelectablePages(filtered.map { ($0.page, $0.artifacts.selectableRows) }),
                    selection: projects
                )
            }
            ToolbarItem {
                RescanButton(
                    isRunning: $isRescanning,
                    isDisabled: projects.folders.isEmpty || projects.isRemoving,
                    scan: projects.scanRun
                ) {
                    await projects.refresh()
                }
            }
        }
        .task {
            guard projects.groups == nil, !projects.isScanning, !projects.scanRun.wasStopped else { return }
            await projects.refresh()
        }
        .rescanOnExclusionChange("ProjectList") { await projects.refresh() }
    }

    private func phase(_ filtered: [ProjectGroup]) -> ScanPhase {
        if projects.folders.isEmpty { return .message }
        if !searchText.isEmpty, projects.groups?.isEmpty == false, filtered.isEmpty { return .message }
        if projects.groups == nil { return projects.scanRun.wasStopped ? .stopped : .scanning(.walk) }
        if projects.groups?.isEmpty == true { return .message }
        return .content
    }
}

private struct ProjectRow: View {
    let group: ProjectGroup

    var body: some View {
        ToolRow(systemImage: "folder") {
            Text(verbatim: group.project.lastPathComponent)
                .lineLimit(1)
        } details: {
            switch group.lastChange {
            case .recently:
                Text("Changed in the last 7 days")
                    .rowTint(Color.accentColor)
            case .at(let last):
                Text("Last changed \(last, format: .relative(presentation: .named))")
                    .lineLimit(1)
            case .notKnown:
                Text("Too large to tell when it last changed")
            case .none:
                EmptyView()
            }
        } trailing: {
            Text(group.total.text)
                .rowFigure()
        }
    }
}
