import PeelCore
import SwiftUI

struct IntelList: View {
    @Environment(IntelLibrary.self) private var intel
    @Environment(PluginLibrary.self) private var plugins
    @Environment(AppLibrary.self) private var library
    @State private var isRescanning = false
    @State private var searchText = ""

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
        .columnSearch(text: $searchText, prompt: "Search Intel Software", when: !intel.findings.isEmpty)
        .scanState(phase(matching), isRescanning: isRescanning, scan: intel.scanRun) {
            if !searchText.isEmpty, matching.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if intel.findings.isEmpty {
                ContentUnavailableView(
                    "Nothing Needs Rosetta",
                    systemImage: "checkmark.seal",
                    // The description claims only what Peel looked at, since Intel plug-ins can be missed: the
                    // macOS 27 release notes say some may not appear even in System Settings.
                    description: Text("Nothing Peel looked at needs Rosetta: the apps, what they carry inside, the plug-ins, the drivers, the background items, and the tools in /usr/local.")
                )
            }
        }
        .fadesInColumn(whenRowsChange: intel.scan?.findings.map(\.id))
        .navigationTitle(Text(Tool.intel.title))
        .announcesScan(intel.isScanning, found: intel.summary, wasStopped: intel.scanRun.wasStopped)
        .toolbar {
            ToolbarItem {
                RescanButton(isRunning: $isRescanning, scan: intel.scanRun) {
                    await scan()
                }
            }
        }
        .task(id: library.revision) {
            guard library.hasLoaded, intel.scannedRevision != library.revision,
                  !(intel.scan == nil && intel.scanRun.wasStopped)
            else { return }
            await scan()
        }
        .rescanOnExclusionChange("IntelList") { await scan() }
    }

    private func phase(_ matching: [IntelFinding]) -> ScanPhase {
        if intel.scan == nil { return intel.scanRun.wasStopped ? .stopped : .scanning(.walk) }
        if !searchText.isEmpty, matching.isEmpty { return .message }
        if intel.findings.isEmpty { return .message }
        return .content
    }

    private func scan() async {
        await intel.refresh(installedApps: library.apps, revision: library.revision, plugins: plugins.plugins)
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
                if let owner = finding.owner {
                    Text("in \(owner)")
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
