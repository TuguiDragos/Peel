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
    /// What the last Remove Downloads left as it was, which an alert tells, since the list moves on without it.
    @State private var leftAlone: LeftAlone?
    @State private var isRescanning = false
    @State private var searchText = ""

    var body: some View {
        let listed = cloud.files(matching: searchText)
        List {
            header
                .listRowSeparator(.hidden)
            RemovalsHeldBanner()

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

            if !listed.isEmpty {
                Section {
                    ForEach(Array(listed.enumerated()), id: \.element.id) { index, file in
                        RemovalRow(
                            url: file.url,
                            icon: .file(file.url),
                            detail: file.isDesktopPicture
                                ? "Not selected: it is the desktop picture, which macOS keeps open while it is shown, so its download can’t be removed now."
                                : nil,
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
                            "Once their downloads are removed, Finder still lists these files, with a cloud beside each name. Deleting a file is different: that removes it from iCloud and from your other devices, and Peel never does it here."
                        )
                    } actions: {
                        SelectMenu(
                            list: SelectableRows(
                                rows: listed.map(\.url), selectable: listed.map(\.url),
                                recommended: listed.filter { !$0.isDesktopPicture }.map(\.url),
                                leftToTheClick: listed.filter(\.isDesktopPicture).map(\.url)
                            ),
                            place: Text(Tool.cloud.title),
                            selection: cloud
                        )
                    }
                } footer: {
                    if cloud.wasCutShort {
                        Text("There is more in iCloud Drive than Peel could look at in one go, so this list isn’t all of it.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .dimmedWhileBusy(cloud.isScanning)
        .columnSearch(text: $searchText, prompt: "Search iCloud Drive", when: cloud.files?.isEmpty == false)
        .scanState(phase(listed: listed), scan: cloud.scanRun) {
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
                    isEnabled: cloud.selectedSize > 0 && !cloud.isFreeing,
                    onRemove: { isConfirming = true },
                    title: "Remove Downloads",
                    systemImage: "icloud.and.arrow.down",
                    notice: freed
                )
            }
        }
        .fadesInColumn(whenRowsChange: cloud.files?.map(\.id))
        .announcesScan(
            cloud.isScanning,
            found: cloud.summary,
            couldNotLook: cloud.couldNotRead ? "iCloud Drive Couldn’t Be Read" : nil,
            wasStopped: cloud.scanRun.wasStopped
        )
        .navigationTitle(Text(Tool.cloud.title))
        .toolbar {
            ToolbarItem {
                RescanButton(isRunning: $isRescanning, isDisabled: cloud.isFreeing, scan: cloud.scanRun) {
                    await cloud.refresh()
                }
            }
        }
        .confirmationDialog(Text("Remove the downloads from this Mac?"), isPresented: $isConfirming) {
            Button("Remove Downloads") {
                Task {
                    let bytes = await cloud.freeSelected()
                    if !cloud.refusals.isEmpty {
                        leftAlone = LeftAlone(freed: bytes, refusals: cloud.refusals)
                    }
                    guard bytes > 0 else { return }
                    freed = BarNotice(figure: bytes.byteCount, words: "Freed")
                    AccessibilityNotification.Announcement(AttributedString(localized: "Freed \(bytes.byteCount) on this Mac.")).post()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This frees \(cloud.selectedSize.byteCount). Nothing is deleted from iCloud: the files stay there, Finder still lists them, and they download again when you open them.")
        }
        .alert(
            leftAlone?.freed == 0 ? Text("No downloads were removed.") : Text("Some downloads couldn’t be removed."),
            isPresented: Binding(get: { leftAlone != nil }, set: { if !$0 { leftAlone = nil } }),
            presenting: leftAlone
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { leftAlone in
            Text(verbatim: leftAlone.message)
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

    private func phase(listed: [CloudFile]) -> ScanPhase {
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
            Text("Files in iCloud that are also downloaded to this Mac. Remove Downloads takes away only the copy here, just as it does in Finder: each file stays in iCloud and downloads again when you open it.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } trailing: {
            TotalLabel(total: cloud.total, caption: Text("on this Mac"))
        }
    }
}

/// The files one Remove Downloads left as they were, and what it freed.
private struct LeftAlone {
    let freed: Int64
    let refusals: [CloudRefusal]

    /// The first few files with the reason each stayed, as the alert after a removal lists them. Still Here, at the
    /// top of the page, lists them all.
    var message: String {
        var lines = refusals.prefix(RemovalFailureAlert.mostListed).map { "\($0.url.abbreviatedPath)\n\($0.explanation)" }
        let rest = refusals.count - lines.count
        if rest > 0 {
            lines.append(String(inflecting: "And ^[\(rest) more item](inflect: true)."))
        }
        return lines.joined(separator: "\n\n")
    }
}
