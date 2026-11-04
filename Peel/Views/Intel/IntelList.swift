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
                    title: Text("Not Everything Could Be Read"), detail: unread,
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
                    unreadActions
                }
            } else if intel.findings.isEmpty {
                if #available(macOS 27, *) {
                    ContentUnavailableView {
                        Label("Nothing Needs Rosetta", systemImage: "checkmark.seal")
                    } description: {
                        VStack(spacing: 6) {
                            Text("Nothing Peel looked at needs Rosetta: the apps in the Applications folders and the folders you added in Settings, what they carry inside, the plug-ins, the drivers, the background items, the Java runtimes, and the tools in /usr/local, /opt/local, ~/bin, and ~/.local/bin.")
                            Text("The Intel-based Apps list in System Settings > General > About names the apps macOS 28 won’t run, including some outside the folders Peel looks in.")
                        }
                    } actions: {
                        Button("Open System Settings") { NSWorkspace.shared.open(DeviceInfo.aboutURL) }
                    }
                } else {
                    ContentUnavailableView(
                        HostArchitecture.isAppleSilicon ? "Nothing Needs Rosetta" : "Nothing Built for Intel Only",
                        systemImage: "checkmark.seal",
                        // The description claims only what Peel looked at, since Intel plug-ins can be missed, and the
                        // macOS 27 release notes say some may not appear even in System Settings.
                        description: HostArchitecture.isAppleSilicon
                            ? Text("Nothing Peel looked at needs Rosetta: the apps in the Applications folders and the folders you added in Settings, what they carry inside, the plug-ins, the drivers, the background items, the Java runtimes, and the tools in /usr/local, /opt/local, ~/bin, and ~/.local/bin.")
                            : Text("Nothing Peel looked at is built for Intel only: the apps in the Applications folders and the folders you added in Settings, what they carry inside, the plug-ins, the drivers, the background items, the Java runtimes, and the tools in /usr/local, /opt/local, ~/bin, and ~/.local/bin.")
                    )
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
            + (paths.isEmpty
                ? [] : [Text("Peel couldn’t read \(RemovalFailureAlert.listedItems(paths)), so something there may need Rosetta.")])
            + why(closed.unread, of: paths.count)
            + (jobFiles.isEmpty ? [] : [jobFiles.count == 1
                ? Text("Peel couldn’t read \(RemovalFailureAlert.listedItems(jobFiles)), so it can’t tell whether what this job runs needs Rosetta.")
                : Text("Peel couldn’t read \(RemovalFailureAlert.listedItems(jobFiles)), so it can’t tell whether what these jobs run needs Rosetta.")])
            + why(closed.jobFiles, of: jobFiles.count)
            + (needsFullDiskAccess ? [Text("macOS keeps Peel out of the folders it protects until Peel has Full Disk Access. Turn it on from Home.")] : [])
            + (intel.scan?.unansweredJobs.missingJobsNote.map { [Text($0)] } ?? [])
        guard let first = parts.first else { return nil }
        return parts.dropFirst().reduce(first) { Text("\($0)\n\n\($1)") }
    }

    private func why(_ closed: Int, of count: Int) -> [Text] {
        UnreadableFoldersNotice.whyNotRead(closed: closed, of: count).map { [Text(verbatim: $0)] } ?? []
    }

    @ViewBuilder
    private var unreadActions: some View {
        if library.listOfFoldersUnreadable {
            StartOverButton(file: library.foldersFile, startedOver: "Started the list of app folders over.") {
                library.startFoldersOver()
            }
        }
        UnreadableFoldersActions(folders: unread, needsFullDiskAccess: needsFullDiskAccess)
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
                if let subtitle = finding.subtitle {
                    Text(subtitle)
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
