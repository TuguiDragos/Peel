import Accessibility
import AppKit
import PeelCore
import SwiftUI

/// The iCloud Drive page, which frees the local copies of files that are safely in iCloud. Nothing here goes to
/// the Trash or into History: each file stays in iCloud and downloads again when it is opened.
struct CloudView: View {
    @Environment(CloudLibrary.self) private var cloud
    @Environment(HomeModel.self) private var home
    @State private var isConfirming = false
    @State private var freed: BarNotice?
    @State private var isRescanning = false
    @State private var searchText = ""

    private var listed: [CloudFile] {
        (cloud.files ?? []).filter { $0.matches(searchText) }
    }

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)
            ExclusionsUnreadableBanner()

            if !listed.isEmpty {
                Section {
                    ForEach(Array(listed.enumerated()), id: \.element.id) { index, file in
                        RemovalRow(
                            url: file.url,
                            icon: .file(file.url),
                            detail: nil,
                            size: file.size,
                            isFirst: index == 0,
                            hasNoteColumn: false,
                            selection: cloud, isSelected: cloud.isSelected(file.url)
                        )
                    }
                    .listRowSeparator(.hidden)
                } header: {
                    SectionHeaderLine {
                        heading(
                            "On This Mac and in iCloud",
                            "Freeing these takes back the room they use here. They stay in iCloud, Finder still shows them, and they download again the moment you open one."
                        )
                    } actions: {
                        SelectAllButton(selectable: listed.map(\.url), selection: Bindable(cloud).selectedURLs)
                    }
                } footer: {
                    if cloud.wasCutShort {
                        Text("There is more in iCloud Drive than Peel could look at in one go, so this list isn’t all of it.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !cloud.refusals.isEmpty {
                Section {
                    ForEach(cloud.refusals) { refusal in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(refusal.url.abbreviatedPath)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(refusal.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    heading("Still Here", "These were left as they are, with the reason beside each one.")
                }
            }
        }
        .dimmedWhileBusy(cloud.isScanning)
        .columnSearch(text: $searchText, prompt: "Search iCloud Drive", when: cloud.files?.isEmpty == false)
        .scanState(phase, scan: cloud.scanRun) {
            if !searchText.isEmpty, cloud.files?.isEmpty == false, listed.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if cloud.couldNotRead {
                ContentUnavailableView {
                    Label("iCloud Drive Couldn’t Be Read", systemImage: "lock")
                } description: {
                    Text("Give Peel Full Disk Access in System Settings to see what iCloud files are kept on this Mac.")
                } actions: {
                    Button("Open System Settings") { home.openFullDiskAccessSettings() }
                }
            } else if cloud.files?.isEmpty == true, cloud.wasCutShort {
                // The scan stopped early, so an empty list does not mean there is nothing to free.
                ContentUnavailableView(
                    "Nothing Found So Far",
                    systemImage: "icloud",
                    description: Text("There is more in iCloud Drive than Peel could look at in one go, and nothing in the part it read is big enough to be worth freeing.")
                )
            } else if cloud.files?.isEmpty == true {
                ContentUnavailableView(
                    "Nothing to Free",
                    systemImage: "checkmark.seal",
                    description: Text("Peel found no file here that is safely in iCloud and big enough to be worth freeing.")
                )
            }
        }
        .safeAreaBar(edge: .bottom) {
            if cloud.files?.isEmpty == false {
                RemovalBar(
                    selectedSize: cloud.selectedSize,
                    isScanning: cloud.isScanning,
                    scan: cloud.scanRun,
                    isEnabled: cloud.selectedSize > 0 && !cloud.isFreeing && !cloud.isScanning,
                    onRemove: { isConfirming = true },
                    title: "Free Up Space",
                    systemImage: "icloud.and.arrow.down",
                    notice: freed
                )
            }
        }
        .fadesInColumn(whenRowsChange: cloud.files?.map(\.id))
        .navigationTitle(Text(Tool.cloud.title))
        .toolbar {
            ToolbarItem {
                RescanButton(isRunning: $isRescanning, isDisabled: cloud.isFreeing, scan: cloud.scanRun) {
                    await cloud.refresh()
                }
            }
        }
        .confirmationDialog(Text("Free up \(cloud.selectedSize.byteCount) on this Mac?"), isPresented: $isConfirming) {
            Button("Free Up Space") {
                Task {
                    let bytes = await cloud.freeSelected()
                    guard bytes > 0 else { return }
                    freed = BarNotice(figure: bytes.byteCount, words: "Freed")
                    AccessibilityNotification.Announcement(AttributedString(localized: "Freed \(bytes.byteCount) on this Mac.")).post()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nothing is deleted. The files stay in iCloud and download again when you open them.")
        }
        .task {
            guard cloud.files == nil, !cloud.isScanning, !cloud.scanRun.wasStopped else { return }
            await cloud.refresh()
        }
        .rescanOnExclusionChange("CloudView") { await cloud.refresh() }
        .task(id: freed) {
            guard freed != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            freed = nil
        }
    }

    private var phase: ScanPhase {
        if cloud.files == nil { return cloud.scanRun.wasStopped ? .stopped : .scanning(.walk) }
        if !searchText.isEmpty, cloud.files?.isEmpty == false, listed.isEmpty { return .message }
        if cloud.couldNotRead { return .message }
        if cloud.files?.isEmpty == true { return .message }
        return .content
    }

    private var header: some View {
        PageHeader(systemImage: "icloud") {
            Text("iCloud Drive")
                .pageTitle()
        } details: {
            Text("Files that are in iCloud and also taking up room here.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } trailing: {
            TotalLabel(bytes: cloud.totalSize, caption: Text("on this Mac"))
        }
    }
}
