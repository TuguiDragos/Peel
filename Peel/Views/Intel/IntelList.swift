import PeelCore
import SwiftUI

struct IntelList: View {
    @Environment(IntelLibrary.self) private var intel
    @Environment(AppLibrary.self) private var library
    @Environment(BackgroundItemLibrary.self) private var backgroundItems
    @State private var isRescanning = false
    @State private var searchText = ""
    @State private var counted = (unread: ClosedByPermissions(), jobFiles: ClosedByPermissions())

    /// How many of `unread` and of `closedJobFiles` their permissions keep this account from reading.
    private var closed: (unread: Int, jobFiles: Int) {
        (counted.unread.count(of: unread), counted.jobFiles.count(of: closedJobFiles))
    }

    var body: some View {
        @Bindable var intel = intel
        let matching = intel.findings.filter { $0.matches(searchText) }
        let byKind = Dictionary(grouping: matching, by: \.kind)

        List(selection: $intel.selection) {
            if !HostArchitecture.isAppleSilicon, !intel.findings.isEmpty {
                // On an Intel Mac the findings are still listed, because they matter on a future Apple silicon Mac.
                Notice(
                    title: Text("Intel software runs natively here"),
                    detail: Text("This Mac has an Intel processor, so nothing listed needs Rosetta."),
                    kind: .note
                ) {}
                .listRowSeparator(.hidden)
            }
            if !intel.findings.isEmpty, let unread = unreadParts {
                Notice(
                    title: Text("Not everything could be read"), detail: unread,
                    kind: needsFullDiskAccess ? .problem : .note
                ) {
                    unreadActions
                }
                .padding(.vertical, 6)
                .listRowSeparator(.hidden)
            }
            ForEach(IntelFinding.Kind.allCases, id: \.self) { kind in
                if let findings = byKind[kind] {
                    Section {
                        ForEach(findings) { finding in
                            IntelRow(finding: finding)
                                .tag(finding.id)
                        }
                    } header: {
                        Text(kind.title)
                    }
                }
            }
        }
        .accessibilityLabel(Text(Tool.intel.title))
        .scrollBarBelowSectionHeaders(!intel.findings.isEmpty)
        .columnSearch(text: $searchText, prompt: "Search Intel Software", when: !intel.findings.isEmpty)
        .scanState(phase(matching), isRescanning: isRescanning, scan: intel.scanRun) {
            if !searchText.isEmpty, matching.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if intel.findings.isEmpty, let unread = unreadParts {
                ContentUnavailableView {
                    Label("Not Everything Could Be Read", systemImage: "exclamationmark.triangle")
                } description: {
                    unread
                } actions: {
                    EmptyStateActions { unreadActions }
                }
            } else if intel.findings.isEmpty {
                let empty = Self.empty(
                    onAppleSilicon: HostArchitecture.isAppleSilicon,
                    settingsListsIntelApps: DeviceInfo.listsIntelBasedApps
                )
                let note = empty.note.map { Text($0) }
                let info = InfoNote(
                    about: Text(empty.title),
                    detail: note.dropFirst().reduce(note[0]) { Text("\($0)\n\n\($1)") },
                    isAlbum: false
                )
                ContentUnavailableView {
                    Label {
                        // Beside a title that takes one line, under one that takes more, so it never stands apart.
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(empty.title)
                                info
                            }
                            VStack(spacing: 4) {
                                Text(empty.title)
                                info
                            }
                        }
                    } icon: {
                        Image(systemName: "checkmark.seal")
                    }
                } description: {
                    Text("Peel looked at your apps, what they carry, and your command-line tools.")
                } actions: {
                    if DeviceInfo.listsIntelBasedApps {
                        Button("Open System Settings") { NSWorkspace.shared.open(DeviceInfo.aboutURL) }
                    }
                }
            }
        }
        .fadesInColumn(whenRowsChange: intel.scan?.findings.map(\.id))
        .navigationTitle(Text(Tool.intel.title))
        .announcesScan(
            intel.isScanning,
            found: intel.summary,
            couldNotLook: intel.findings.isEmpty && unreadParts != nil ? "Not Everything Could Be Read" : nil,
            wasStopped: intel.scanRun.wasStopped
        )
        .toolbar {
            ToolbarItem {
                RescanButton(isRunning: $isRescanning, isDisabled: !library.hasLoaded, scan: intel.scanRun) {
                    await scan()
                }
            }
        }
        .task(id: unread + closedJobFiles) {
            counted = (await .counting(unread), await .counting(closedJobFiles))
        }
        // What the page lists can change from other pages and other apps, and a scan costs little, so once read it
        // looks again, quietly, each time it is shown and each time Peel comes forward.
        .task(id: library.revision) {
            guard library.hasLoaded else { return }
            guard intel.scan == nil else {
                await intel.readAgain(installedApps: library.apps, knownSizes: library.sizes)
                return
            }
            guard !intel.scanRun.wasStopped else { return }
            await scan()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard library.hasLoaded else { return }
            Task { await intel.readAgain(installedApps: library.apps, knownSizes: library.sizes) }
        }
        .rescanOnExclusionChange("IntelList") { await scan() }
        .rescanAfterPutBack(.intel) { await scan() }
    }

    private func phase(_ matching: [IntelFinding]) -> ScanPhase {
        if intel.scan == nil { return intel.scanRun.wasStopped ? .stopped : .scanning(.walk) }
        if !searchText.isEmpty, matching.isEmpty { return .message }
        if intel.findings.isEmpty { return .message }
        return .content
    }

    private func scan() async {
        await intel.refresh(installedApps: library.apps, knownSizes: library.sizes)
    }

    /// What Peel couldn't read for this page: the apps the Applications list couldn't, and what the scan couldn't.
    private var unread: [URL] {
        library.unreadable + (intel.scan?.unreadable ?? [])
    }

    private var closedJobFiles: [URL] {
        intel.scan?.closedJobs.compactMap(\.plistURL) ?? []
    }

    private var needsFullDiskAccess: Bool {
        library.unreadableNeedsFullDiskAccess || intel.scan?.needsFullDiskAccess == true
    }

    /// What Peel couldn't read, a paragraph for each kind, or nil when it read everything.
    private var unreadParts: Text? {
        let paths = unread.map(\.abbreviatedPath)
        let jobFiles = closedJobFiles.map(\.abbreviatedPath)
        let parts = (library.listOfFoldersUnreadable
                ? [Text(verbatim: library.unreadableListOfFolders(saying: String(localized: "Peel can’t read its list of app folders, so it didn’t look at the apps in the folders you added.")))] : [])
            + (paths.isEmpty ? [] : [Text(Self.unreadFolders(
                count: paths.count, onAppleSilicon: HostArchitecture.isAppleSilicon
            ))])
            + (jobFiles.isEmpty ? [] : [Text(Self.unreadJobFiles(
                count: jobFiles.count, onAppleSilicon: HostArchitecture.isAppleSilicon
            ))])
            + (UnreadableFoldersNotice.reason(
                count: paths.count + jobFiles.count, closed: closed.unread + closed.jobFiles,
                needsFullDiskAccess: needsFullDiskAccess
            ).map { [Text(verbatim: $0)] } ?? [])
            + (intel.scan?.unansweredJobs.missingJobsNote.map { [Text($0)] } ?? [])
        guard let first = parts.first else { return nil }
        return parts.dropFirst().reduce(first) { Text("\($0)\n\n\($1)") }
    }

    /// What may be in folders Peel did not read: Intel code needs Rosetta only on Apple silicon.
    static func unreadFolders(count: Int, onAppleSilicon: Bool) -> LocalizedStringResource {
        switch (count == 1, onAppleSilicon) {
        case (true, true): "Peel did not read a folder, so something there may need Rosetta."
        case (false, true): "Peel did not read \(count) folders, so something there may need Rosetta."
        case (true, false): "Peel did not read a folder, so something there may be built for Intel only."
        case (false, false): "Peel did not read \(count) folders, so something there may be built for Intel only."
        }
    }

    /// The empty page's title, and what its circled i says. It claims only what Peel looked at: Intel plug-ins can be
    /// missed, and the macOS 27 release notes say some may not appear even in System Settings.
    static func empty(
        onAppleSilicon: Bool, settingsListsIntelApps: Bool
    ) -> (title: LocalizedStringResource, note: [LocalizedStringResource]) {
        let places: LocalizedStringResource = onAppleSilicon
            ? "Nothing Peel looked at needs Rosetta: the apps in the Applications folders and the folders you added in Settings, what they carry inside, the plug-ins, the drivers, the background items, the Java runtimes, and the tools in /usr/local, /opt/homebrew, /opt/local, ~/bin, and ~/.local/bin."
            : "Nothing Peel looked at is built for Intel only: the apps in the Applications folders and the folders you added in Settings, what they carry inside, the plug-ins, the drivers, the background items, the Java runtimes, and the tools in /usr/local, /opt/local, ~/bin, and ~/.local/bin."
        let settingsList: LocalizedStringResource =
            "The Intel-based Apps list in System Settings > General > About names the apps macOS 28 won’t run, including some outside the folders Peel looks in."
        return (
            onAppleSilicon ? "Nothing Needs Rosetta" : "Nothing Built for Intel Only",
            settingsListsIntelApps ? [places, settingsList] : [places]
        )
    }

    static func unreadJobFiles(count: Int, onAppleSilicon: Bool) -> LocalizedStringResource {
        switch (count == 1, onAppleSilicon) {
        case (true, true):
            "Peel did not read the file of a background job, so it cannot tell whether what it runs needs Rosetta."
        case (false, true):
            "Peel did not read the files of \(count) background jobs, so it cannot tell whether what they run needs Rosetta."
        case (true, false):
            "Peel did not read the file of a background job, so it cannot tell whether what it runs is built for Intel only."
        case (false, false):
            "Peel did not read the files of \(count) background jobs, so it cannot tell whether what they run is built for Intel only."
        }
    }

    @ViewBuilder
    private var unreadActions: some View {
        if library.listOfFoldersUnreadable {
            StartOverButton(file: library.foldersFile, startedOver: "Started the list of app folders over.") {
                library.startFoldersOver()
            }
        }
        UnreadableFoldersActions(folders: unread + closedJobFiles, needsFullDiskAccess: needsFullDiskAccess)
        if let job = intel.scan?.closedJobs.first {
            Button("Review in Background Items") {
                backgroundItems.selection = job.id
                Navigator.shared.requestedTool = .backgroundItems
            }
        }
    }
}

private struct IntelRow: View {
    let finding: IntelFinding

    var body: some View {
        HStack(spacing: 10) {
            AppIcon(url: finding.url)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: finding.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let caption = finding.rowCaption {
                    Text(verbatim: caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Text(finding.size.byteCount)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
