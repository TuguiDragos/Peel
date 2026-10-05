import PeelCore
import SwiftUI

struct HomebrewList: View {
    @Environment(HomebrewLibrary.self) private var homebrew
    @Environment(\.openSettings) private var openSettings
    @State private var searchText = ""
    @State private var isRescanning = false
    @State private var isConfirmingCleanUp = false
    @State private var isConfirmingUpgradeAll = false

    var body: some View {
        @Bindable var homebrew = homebrew
        let shown = listed
        let byKind = Dictionary(grouping: shown, by: \.kind)
        let outdated = homebrew.outdated

        List(selection: $homebrew.selection) {
            // While searching, the page lists only the matching packages and hides every other section.
            if searchText.isEmpty, homebrew.isInstalled, !homebrew.needsDefinitions {
                installation
                overridden
                maintenance
                health
                vulnerabilities
                retired(homebrew.retired)
                updates(outdated)
                empty
            }
            section(Text("Formulae"), packages: byKind[.formula] ?? [])
            section(Text("Casks"), packages: byKind[.cask] ?? [])
        }
        .scanState(phase(shown), isRescanning: isRescanning, scan: homebrew.scanRun) { placeholder(shown) }
        // A `List` inserts a new section in one frame, with no animation, so the rows below it jump. To soften
        // that, the column fades in when a health or vulnerability report appears or is cleared.
        .fadesInColumn(on: [homebrew.findings == nil, homebrew.advisories == nil])
        .columnSearch(text: $searchText, prompt: "Search Homebrew", when: homebrew.packages?.isEmpty == false)
        .fadesInColumn(whenRowsChange: homebrew.packages?.map(\.id))
        .navigationTitle(Text(Tool.homebrew.title))
        .announcesScan(
            homebrew.isScanning,
            found: homebrew.summary,
            couldNotLook: !homebrew.isInstalled ? "Homebrew Isn’t Installed"
                : homebrew.needsDefinitions ? "Homebrew Has to Update First" : nil,
            wasStopped: homebrew.scanRun.wasStopped
        )
        .toolbar {
            ToolbarItem {
                RescanButton(
                    isRunning: $isRescanning,
                    isDisabled: !homebrew.isInstalled || homebrew.runningCommand != nil,
                    scan: homebrew.scanRun
                ) {
                    await homebrew.refresh(includingReclaimable: true)
                }
            }
        }
        .sheet(item: $homebrew.result) { result in
            HomebrewOutputView(result: result)
        }
        .confirmationDialog(
            Text(verbatim: String(inflecting: "Upgrade ^[\(homebrew.upgradable.count) package](inflect: true)?")),
            isPresented: $isConfirmingUpgradeAll
        ) {
            Button("Upgrade All") { start(.upgradeAll) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can take a long time, since Homebrew builds some packages on this Mac. Its progress shows on this page as it works, and you can stop it there.")
        }
        // Clean Up is confirmed first, like Uninstall on a package's page, because Homebrew deletes these files
        // permanently and History can't put them back.
        .confirmationDialog("Clean up Homebrew?", isPresented: $isConfirmingCleanUp) {
            Button("Clean Up", role: .destructive) { start(.cleanup) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: cleanUpWarning)
        }
        .task {
            // Only this page shows what Clean Up would free, so the figure is asked for here, and only while
            // it's unknown: `brew cleanup --dry-run` has to walk the cache and the Cellar to work it out.
            guard !homebrew.isScanning, !homebrew.scanRun.wasStopped,
                  homebrew.packages == nil || homebrew.reclaimable == nil
            else { return }
            await homebrew.refresh(includingReclaimable: true)
        }
    }

    /// What Clean Up deletes for good, with the formulae it would uninstall named, since those are packages.
    private var cleanUpWarning: String {
        var sentences: [String] = []
        if let reclaimable = homebrew.reclaimable, reclaimable > 0 {
            sentences.append(String(localized: "Homebrew deletes these for good: about \(reclaimable.byteCount) of downloads and old versions, and any formulae that were only there for something now gone, which that figure leaves out. Nothing goes to the Trash, and History can’t put it back."))
        } else {
            sentences.append(String(localized: "Homebrew deletes these for good: the downloads and old versions it kept, and any formulae that were only there for something now gone. Nothing goes to the Trash, and History can’t put it back."))
        }
        let formulae = homebrew.autoremovable
        if !formulae.isEmpty {
            sentences.append(String(inflecting: "It uninstalls ^[\(formulae.count) formula](inflect: true) that nothing needs anymore: \(formulae.formatted(.list(type: .and)))."))
        }
        return sentences.joined(separator: "\n\n")
    }

    // MARK: - Homebrew itself

    /// What Homebrew's own settings undo of how Peel runs it, said before anything is run.
    @ViewBuilder
    private var overridden: some View {
        let overrides = homebrew.overrides
        if !overrides.isEmpty {
            Section {
                Notice(title: Text("Homebrew’s Own Settings Change How Peel Runs It"), detail: Text(verbatim: explanation(of: overrides)), kind: .caution) {}
            }
        }
    }

    private func explanation(of overrides: Homebrew.Overrides) -> String {
        var sentences: [String] = []
        if overrides.contains(.cleansUp) { sentences.append(String(localized: HomebrewLibrary.cleansUp)) }
        if overrides.contains(.sendsAnalytics) { sentences.append(String(localized: "Homebrew sends its makers analytics whenever Peel runs it.")) }
        if overrides.contains(.updatesItself) { sentences.append(String(localized: "Homebrew may download its list of packages when Peel only asks about them.")) }
        let prefix =
            homebrew.installation?.prefix
            ?? Homebrew.executableURL?.deletingLastPathComponent().deletingLastPathComponent()
        let folder = (prefix?.path(percentEncoded: false) ?? "") + "/etc/homebrew"
        sentences.append(String(localized: "A brew.env file sets this, in /etc/homebrew, in \(folder), or in ~/.homebrew."))
        // A line each, since Chinese and Japanese put no space between sentences.
        return sentences.joined(separator: "\n")
    }

    private var installation: some View {
        Section {
            LabeledContent("Version") {
                Text(verbatim: homebrew.installation?.version ?? String(localized: "Unknown (Homebrew version)", defaultValue: "Unknown"))
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
            LabeledContent("Location") {
                let location =
                    homebrew.installation?.prefix.path(percentEncoded: false)
                    ?? String(localized: "Unknown (Homebrew location)", defaultValue: "Unknown")
                Text(verbatim: location)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .help(Text(verbatim: location))
            }
            .labeledContentStyle(.oneLine)
            LabeledContent("Formulae") {
                Text(homebrew.count(of: .formula), format: .number).monospacedDigit()
            }
            LabeledContent("Casks") {
                Text(homebrew.count(of: .cask), format: .number).monospacedDigit()
            }
        } header: {
            heading(
                "Homebrew",
                "Homebrew installs command-line tools as formulae and apps as casks. On this page Peel only runs Homebrew’s own commands and reads what they report."
            )
        }
    }

    private var maintenance: some View {
        Section {
            row(
                title: "Update Homebrew",
                detail: "Gets the newest Homebrew and its newest list of packages, so run it before looking for updates. It upgrades nothing, though Homebrew may move a renamed package to its new name, or reinstall pkgconf after a macOS update.",
                systemImage: "arrow.triangle.2.circlepath",
                command: .update
            ) {
                Button("Update") { start(.update) }
            }
            row(
                title: "Clean Up",
                detail: "Removes what Homebrew kept after installing and upgrading: cached downloads, old versions, and formulae that were only there for something now gone. What you installed yourself stays.",
                systemImage: "sparkles",
                command: .cleanup
            ) {
                if let reclaimable = homebrew.reclaimable, reclaimable > 0 {
                    Text(reclaimable.byteCount)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Button("Clean Up") { isConfirmingCleanUp = true }
            }
            row(
                title: "Check Health",
                detail: "Asks Homebrew to check itself and report anything out of place, such as a broken link. It only looks and changes nothing. It can’t see the PATH your Terminal uses, so problems there don’t show up here.",
                systemImage: "stethoscope",
                command: .health
            ) {
                Button("Check") { start(.health) }
            }
            row(
                title: "Scan for Vulnerabilities",
                detail: "Checks the installed formulae against the OSV.dev list of known vulnerabilities. Homebrew sends the source and version of each one to api.osv.dev, and only when you click Scan. Casks aren’t covered.",
                systemImage: "shield",
                command: .vulnerabilities
            ) {
                if homebrew.installation?.checksVulnerabilities == true {
                    Button("Scan") { start(.vulnerabilities) }
                } else if homebrew.installation != nil {
                    Text("Needs Homebrew 6.0.11 or later")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            heading("Maintenance", "Homebrew’s own housekeeping, run by Homebrew. Peel adds nothing of its own.")
        }
    }

    @ViewBuilder
    private var health: some View {
        if let findings = homebrew.findings {
            Section {
                if findings.isEmpty {
                    Label("Homebrew found nothing out of place.", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    // Findings can't be selected, since the detail pane shows only packages.
                    ForEach(findings) { finding in
                        HomebrewFindingRow(finding: finding)
                            .selectionDisabled()
                    }
                    .listRowSeparator(.hidden)
                }
            } header: {
                HStack(spacing: 8) {
                    heading("What Homebrew Found", "Homebrew’s own report, in its own words. Peel changes none of it: copy a command and run it in Terminal, where you can see what it does.")
                    Spacer(minLength: 8)
                    if !findings.isEmpty {
                        Text("^[\(findings.count) finding](inflect: true)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var vulnerabilities: some View {
        if let report = homebrew.advisories {
            Section {
                if report.advisories.isEmpty {
                    Label("Homebrew found no known vulnerabilities.", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(report.advisories) { advisory in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: advisory.formula)
                                    .lineLimit(1)
                                Text("\(advisory.version) · ^[\(advisory.vulnerabilities.count) vulnerability](inflect: true)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Badge(
                                title: Text(advisory.highestSeverity.title),
                                systemImage: advisory.highestSeverity.symbol,
                                symbolTint: advisory.highestSeverity.color
                            )
                        }
                        .padding(.vertical, 2)
                        .tag(HomebrewRow.vulnerabilities(formula: advisory.formula))
                    }
                }
                if !report.skipped.isEmpty {
                    Text("Homebrew skipped ^[\(report.skipped.count) installed package](inflect: true) with no source to check against.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !report.caveats.isEmpty {
                    Text(verbatim: report.caveats)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                SectionHeaderLine {
                    heading(
                        "Known Vulnerabilities",
                        "Homebrew’s own scan, as it reported it. Peel changes nothing here. A vulnerability clears once Homebrew offers a version with the fix and the package is upgraded to it."
                    )
                } count: {
                    if !report.advisories.isEmpty {
                        Text("^[\(report.advisories.map(\.vulnerabilities.count).reduce(0, +)) vulnerability](inflect: true)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } actions: {}
            }
        }
    }

    @ViewBuilder
    private var empty: some View {
        if let problem = homebrew.couldNotRead {
            Section {
                Notice(
                    title: Text("Homebrew didn’t say what is installed"),
                    detail: Text(
                        verbatim: FixedSentence.translated(problem.trimmingCharacters(in: .whitespacesAndNewlines))
                    ),
                    kind: .note
                ) {}
                .listRowSeparator(.hidden)
            }
        } else if homebrew.packages?.isEmpty == true {
            Section {
                Text("Nothing is installed with Homebrew yet. Tools and apps you install with it will appear here.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Packages

    @ViewBuilder
    private func updates(_ outdated: [HomebrewPackage]) -> some View {
        if !outdated.isEmpty {
            Section {
                ForEach(outdated) { package in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: package.name)
                                .lineLimit(1)
                            if let installed = package.installedVersion, let latest = package.latestVersion {
                                Text(verbatim: "\(installed) → \(latest)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        Spacer(minLength: 4)
                        if package.isPinned {
                            Badge(title: Text("Pinned"), systemImage: "pin", tint: .secondary)
                        } else if package.upgradeNeedsAnAdministrator {
                            Badge(title: Text("Needs Terminal"), systemImage: "terminal", tint: .secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(HomebrewRow.package(package.id))
                }
            } header: {
                SectionHeaderLine {
                    heading("Updates Available", "Homebrew has a newer version of these. A pinned package is held on purpose, so it is listed and left alone.")
                } actions: {
                    BusyShown(isBusy: homebrew.runningCommand == .upgradeAll) { isShown in
                        if isShown {
                            ProgressView().controlSize(.small).transition(.opacity)
                        }
                    }
                    .motion(value: homebrew.runningCommand == .upgradeAll)
                    Button { isConfirmingUpgradeAll = true } label: {
                        Text("Upgrade All")
                            .minimumTarget()
                    }
                        .buttonStyle(.borderless)
                        .disabled(homebrew.upgradable.isEmpty || isBusy)
                }
            }
        }
    }

    /// The section of packages Homebrew has deprecated or disabled. It comes above the updates, since an
    /// upgrade can't fix either state.
    @ViewBuilder
    private func retired(_ packages: [HomebrewPackage]) -> some View {
        if !packages.isEmpty {
            Section {
                ForEach(packages) { package in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: package.name)
                            .lineLimit(1)
                        package.retirement?.caption(now: .now)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .tag(HomebrewRow.package(package.id))
                }
            } header: {
                // `SectionHeaderLine` lets the heading wrap to a second line, which some translations need.
                SectionHeaderLine {
                    heading(
                        "Deprecated or Disabled",
                        "Homebrew deprecates a package it means to stop offering, and disables it when it stops. A disabled package can’t be installed again and gets no more upgrades. What is installed stays until you uninstall it."
                    )
                } actions: {}
            }
        }
    }

    @ViewBuilder
    private func section(_ title: Text, packages: [HomebrewPackage]) -> some View {
        if !packages.isEmpty {
            Section {
                ForEach(packages) { package in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: package.name)
                                .lineLimit(1)
                            Text(verbatim: package.installedVersion ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        if package.isOutdated {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.blue)
                                .accessibilityLabel(Text("Update available"))
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(HomebrewRow.package(package.id))
                }
            } header: {
                title
            }
        }
    }

    // MARK: - Pieces

    private func row(
        title: LocalizedStringResource,
        detail: LocalizedStringResource,
        systemImage: String,
        command: HomebrewLibrary.Command,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 6) {
            Label { Text(title) } icon: { Image(systemName: systemImage) }
            InfoNote(name: String(localized: title), detail: Text(detail))
            Spacer(minLength: 8)
            BusyShown(isBusy: homebrew.runningCommand == command) { isShown in
                if isShown {
                    ProgressView().controlSize(.small).transition(.opacity)
                }
            }
            .motion(value: homebrew.runningCommand == command)
            // Only the controls are disabled while Homebrew is busy, so the info note can still be opened.
            trailing()
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy)
        }
        .padding(.vertical, 1)
    }

    private func start(_ command: HomebrewLibrary.Command) {
        Task { await homebrew.run(command) }
    }

    private var isBusy: Bool {
        homebrew.runningCommand != nil || homebrew.isScanning
    }

    /// The packages for the Formulae and Casks sections. Outdated and retired packages have their own sections
    /// above, so they are left out here, except during a search, which hides those sections.
    private var listed: [HomebrewPackage] {
        guard searchText.isEmpty else { return filteredPackages }
        return (homebrew.packages ?? []).filter { !$0.isOutdated && $0.retirement == nil }
    }

    private func phase(_ shown: [HomebrewPackage]) -> ScanPhase {
        if !homebrew.isInstalled { return .message }
        // With no local package definitions and no packages read, every section is hidden, so the page shows a
        // message, or a spinner while the update runs.
        if homebrew.needsDefinitions, homebrew.packages?.isEmpty != false {
            return homebrew.runningCommand == nil ? .message : .scanning(.homebrewUpdate)
        }
        if homebrew.packages == nil { return homebrew.scanRun.wasStopped ? .stopped : .scanning(.walk) }
        if shown.isEmpty, !searchText.isEmpty { return .message }
        return .content
    }

    @ViewBuilder
    private func placeholder(_ shown: [HomebrewPackage]) -> some View {
        if !homebrew.isInstalled {
            ContentUnavailableView {
                Label("Homebrew Isn’t Installed", systemImage: "mug")
            } description: {
                Text("Install Homebrew to manage command-line tools and apps from Peel.")
            } actions: {
                if let url = URL(string: "https://brew.sh") {
                    Link(destination: url) {
                        Text("Open brew.sh")
                            .minimumTarget()
                    }
                }
                Button("Homebrew Is in Another Folder") { SettingsPane.general.open(with: openSettings) }
            }
        } else if homebrew.needsDefinitions, homebrew.packages?.isEmpty != false, homebrew.runningCommand == nil {
            ContentUnavailableView {
                Label("Homebrew Has to Update First", systemImage: "arrow.down.circle")
            } description: {
                Text("Homebrew’s own list of packages isn’t on this Mac, so asking it about packages would download the list again. Peel doesn’t start that on its own.")
            } actions: {
                Button("Update Homebrew") { start(.update) }
            }
        } else if shown.isEmpty, !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private var filteredPackages: [HomebrewPackage] {
        let packages = homebrew.packages ?? []
        guard !searchText.isEmpty else { return packages }
        return packages.filter {
            SearchText.matches($0.name, searchText)
                || $0.summary.map { summary in SearchText.matches(summary, searchText) } == true
        }
    }
}

struct HomebrewOutputView: View {
    @Environment(\.dismiss) private var dismiss
    let result: HomebrewLibrary.CommandResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(result.succeeded ? "Homebrew finished" : "Homebrew couldn’t finish")
                    .font(.headline)
            } icon: {
                Image(systemName: result.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(result.succeeded ? .green : .red)
            }
            if !result.succeeded {
                Text("If the command needs your password, run it in Terminal.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                (result.output.isEmpty ? Text("No output.") : Text(verbatim: FixedSentence.translated(result.output)))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 160, maxHeight: 320)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
