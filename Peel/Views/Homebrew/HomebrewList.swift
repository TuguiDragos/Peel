import PeelCore
import SwiftUI

struct HomebrewList: View {
    @Environment(HomebrewLibrary.self) private var homebrew
    @Environment(AppLibrary.self) private var library
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(\.openSettings) private var openSettings
    @State private var searchText = ""
    @State private var isRescanning = false
    @State private var isConfirmingCleanUp = false
    /// One of the deeper clean ups, or the repair, waiting for its confirmation.
    @State private var confirming: HomebrewLibrary.Command?
    @State private var isConfirmingUpgradeAll = false
    @State private var casksToForget: [HomebrewPackage]?

    var body: some View {
        // Reading what a command or a Forget changed dims the list as a Rescan does, on the same timing.
        BusyShown(isBusy: homebrew.isReadingWhatChanged) { isReading in
            page(isReading: isReading)
        }
    }

    @ViewBuilder
    private func page(isReading: Bool) -> some View {
        @Bindable var homebrew = homebrew
        let shown = listed
        let byKind = Dictionary(grouping: shown, by: \.kind)
        let outdated = homebrew.outdated

        List(selection: $homebrew.selection) {
            let needsDefinitions = homebrew.needsDefinitions
            if searchText.isEmpty, homebrew.isInstalled,
               Self.asksToUpdateAboveTheLists(needsDefinitions: needsDefinitions, packages: homebrew.packages) {
                updateFirst
            }
            // While searching, the page lists only the matching packages and hides every other section.
            if searchText.isEmpty, homebrew.isInstalled, !homebrew.needsDefinitions {
                if let reason = homebrew.whyItCantChange {
                    cantChange(reason)
                }
                installation
                // On macOS 27 what Homebrew said, or didn't, comes right under its section, before maintenance.
                if #available(macOS 27, *) {
                    empty
                }
                overridden
                maintenance
                health
                vulnerabilities
                retired(homebrew.retired)
                updates(outdated)
                alreadyGone(homebrew.alreadyGone)
                if #unavailable(macOS 27) {
                    empty
                }
            }
            section(Text("Formulae"), packages: byKind[.formula] ?? [])
            section(Text("Casks"), packages: byKind[.cask] ?? [])
        }
        .accessibilityLabel(Text(Tool.homebrew.title))
        .scrollBarBelowSectionHeaders()
        .scanState(phase(shown), isRescanning: isRescanning || isReading, scan: homebrew.scanRun) { placeholder(shown) }
        // A `List` inserts a new section in one frame, with no animation, so the rows below it jump. To soften
        // that, the column fades in when a health or vulnerability report appears or is cleared.
        .fadesInColumn(on: [homebrew.findings == nil, homebrew.advisories == nil])
        .columnSearch(text: $searchText, prompt: "Search Homebrew", when: homebrew.packages?.isEmpty == false)
        .fadesInColumn(whenRowsChange: homebrew.packages?.map(\.id))
        .navigationTitle(Text(Tool.homebrew.title))
        .announcesScan(
            homebrew.isScanning,
            found: homebrew.summary,
            couldNotLook: homebrew.unrunnableChoice != nil ? "Peel Can’t Run the `brew` You Chose"
                : homebrew.refusedBrew != nil ? "Peel Doesn’t Run This Homebrew"
                : !homebrew.isInstalled ? "Homebrew Isn’t Installed"
                : !homebrew.needsDefinitions ? nil
                : homebrew.whyItCantChange?.title ?? "Homebrew Has to Update First",
            wasStopped: homebrew.scanRun.wasStopped
        )
        .toolbar {
            ToolbarItem {
                RescanButton(
                    isRunning: $isRescanning,
                    isDisabled: !homebrew.isInstalled || homebrew.runningCommand != nil || homebrew.isForgetting,
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
            Button("Upgrade All") { upgradeAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can take a long time, since Homebrew builds some packages on this Mac. Its progress shows on this page as it works, and you can stop it there.")
        }
        .forgetCasksDialog(for: $casksToForget)
        // Clean Up is confirmed first, like Uninstall on a package's page, because Homebrew deletes these files
        // permanently and History can't put them back.
        .confirmationDialog("Clean up Homebrew?", isPresented: $isConfirmingCleanUp) {
            Button("Clean Up", role: .destructive) { start(.cleanup) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: cleanUpWarning)
        }
        .confirmationDialog(
            confirming.map(confirmationTitle) ?? Text(verbatim: ""),
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            presenting: confirming
        ) { command in
            Button(command == .repairTaps ? "Repair" : "Clear", role: command == .repairTaps ? nil : .destructive) {
                start(command)
            }
            Button("Cancel", role: .cancel) {}
        } message: { command in
            confirmationMessage(command)
        }
        .task {
            // Only this page shows what Clean Up would free, so the figure is asked for here, and only while
            // it's unknown: `brew cleanup --dry-run` has to walk the cache and the Cellar to work it out.
            guard !homebrew.scanRun.isWaitedFor, !homebrew.scanRun.wasStopped,
                  homebrew.packages == nil || homebrew.reclaimable == nil
            else { return }
            await homebrew.refresh(includingReclaimable: true)
        }
    }

    private func confirmationTitle(_ command: HomebrewLibrary.Command) -> Text {
        switch command {
        case .clearOlderDownloads: Text("Clear Homebrew’s downloads older than 30 days?")
        case .clearEveryDownload: Text("Clear every Homebrew download?")
        default: Text("Repair Homebrew’s taps?")
        }
    }

    private func confirmationMessage(_ command: HomebrewLibrary.Command) -> Text {
        switch command {
        case .clearOlderDownloads:
            Text("Homebrew deletes for good every file in its cache older than 30 days, and what Clean Up deletes. Nothing goes to the Trash, and History can’t put it back.")
        case .clearEveryDownload:
            Text("Homebrew deletes for good every download it keeps, even for the latest versions, except those of what is installed now, and what Clean Up deletes. Nothing goes to the Trash, and History can’t put it back.")
        default:
            Text("Homebrew adds the links missing from its taps’ manual pages and shell completions, and points a tap whose main branch was renamed at the new name. It deletes nothing.")
        }
    }

    private var cleanUpWarning: String {
        Self.cleanUpWarning(
            reclaimable: homebrew.reclaimable, keepsDependencies: homebrew.overrides.contains(.keepsDependencies),
            prefix: homebrew.installation?.prefix, formulae: homebrew.autoremovable
        )
    }

    /// What Clean Up deletes for good, with the formulae it would uninstall named, since those are packages.
    static func cleanUpWarning(
        reclaimable: Int64?, keepsDependencies: Bool, prefix: URL?, formulae: [String]
    ) -> String {
        var sentences: [String] = []
        if let reclaimable, reclaimable > 0 {
            sentences.append(keepsDependencies
                ? String(localized: "Homebrew deletes these for good: about \(reclaimable.byteCount) of downloads and old versions. Nothing goes to the Trash, and History can’t put it back.")
                : String(localized: "Homebrew deletes these for good: about \(reclaimable.byteCount) of downloads and old versions, and the formulae nothing needs anymore, which that figure leaves out. Nothing goes to the Trash, and History can’t put it back."))
        } else {
            sentences.append(keepsDependencies
                ? String(localized: "Homebrew deletes these for good: the downloads and old versions it kept. Nothing goes to the Trash, and History can’t put it back.")
                : String(localized: "Homebrew deletes these for good: the downloads and old versions it kept, and the formulae nothing needs anymore. Nothing goes to the Trash, and History can’t put it back."))
        }
        if let prefix {
            sentences.append(Self.prunes(prefix))
        }
        if !formulae.isEmpty {
            sentences.append(Self.uninstalls(formulae))
        }
        return sentences.joined(separator: "\n\n")
    }

    /// What `brew cleanup` also deletes in the prefix, which on a Mac with an Intel processor other programs share.
    static func prunes(_ prefix: URL) -> String {
        String(localized: "It also deletes the broken links and empty folders it finds in \(prefix.abbreviatedPath).")
    }

    /// The formulae Clean Up uninstalls, the first ones named as an alert names them. The row's note has them all.
    static func uninstalls(_ formulae: [String]) -> String {
        String(inflecting: "Right now that is ^[\(formulae.count) formula](inflect: true): \(RemovalFailureAlert.listedFormulae(formulae)).")
    }

    /// What the Clean Up row's note says: what Clean Up deletes, and every formula it would uninstall now.
    private var cleanUpDetail: Text {
        var removes = homebrew.overrides.contains(.keepsDependencies)
            ? Text("Deletes what Homebrew kept after installing and upgrading: cached downloads and old versions. What you installed yourself stays.")
            : Text("Deletes what Homebrew kept after installing and upgrading: cached downloads, old versions, and the formulae nothing needs anymore. What you installed yourself stays.")
        if let prefix = homebrew.installation?.prefix {
            removes = Text("\(removes)\n\n\(Self.prunes(prefix))")
        }
        let formulae = homebrew.autoremovable
        guard !formulae.isEmpty else { return removes }
        let listed = Text("Formulae it would uninstall now: \(formulae.formatted(.list(type: .and))).")
        return Text("\(removes)\n\n\(listed)")
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
        if homebrew.leavesChangesToTerminal {
            Section {
                Notice(
                    title: Text("Upgrades and Uninstalls Go to Terminal"),
                    detail: Text(HomebrewLibrary.homebrewElsewhere),
                    kind: .note
                ) {}
            }
        }
        if let unread = homebrew.unreadSettingsFile {
            Section {
                Notice(
                    title: Text("Homebrew Run From Peel Doesn’t Read One of Your Settings Files"),
                    detail: Text("Homebrew reads \(unread.abbreviatedPath) only from a shell that sets XDG_CONFIG_HOME to ~/.config. Peel runs Homebrew without your shell’s settings, so there it reads ~/.homebrew/brew.env. Put what you want it to follow from Peel, such as a proxy, in ~/.homebrew/brew.env."),
                    kind: .note
                ) {}
            }
        }
    }

    private func explanation(of overrides: Homebrew.Overrides) -> String {
        var sentences: [String] = []
        if overrides.contains(.cleansUp) { sentences.append(String(localized: HomebrewLibrary.cleansUp)) }
        if overrides.contains(.sendsAnalytics) { sentences.append(String(localized: "Homebrew sends its makers analytics whenever Peel runs it.")) }
        if overrides.contains(.updatesItself) { sentences.append(String(localized: "Homebrew may download its list of packages when Peel only asks about them.")) }
        if overrides.contains(.leavesAppsThatUpdateThemselves) { sentences.append(String(localized: "When Peel runs it, Homebrew doesn’t compare the versions of apps that update themselves, so it can’t say whether they’re behind.")) }
        if overrides.contains(.keepsDependencies) { sentences.append(String(localized: "Homebrew keeps the formulae nothing needs anymore: Uninstall and Clean Up leave them where they are.")) }
        if homebrew.settingsFolders.isEmpty {
            sentences.append(String(localized: "A brew.env file sets this."))
        } else {
            let folders = homebrew.settingsFolders.map(\.abbreviatedPath).formatted(.list(type: .or))
            sentences.append(String(localized: "A brew.env file sets this, in \(folders)."))
        }
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
                    homebrew.installation?.prefix.fullPath
                    ?? String(localized: "Unknown (Homebrew location)", defaultValue: "Unknown")
                Text(verbatim: location)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .help(Text(verbatim: location))
            }
            .labeledContentStyle(.oneLine)
            if homebrew.installation?.isIntelOnAppleSilicon == true {
                LabeledContent("Built For") {
                    Text(Rosetta.isInstalled
                        ? "Intel. Peel runs it through Rosetta."
                        : "Intel. Rosetta isn’t installed, so it can’t run.")
                }
            }
            LabeledContent("Formulae") {
                count(of: .formula)
            }
            LabeledContent("Casks") {
                count(of: .cask)
            }
        } header: {
            heading(
                "Homebrew",
                "Homebrew installs command-line tools as formulae and apps as casks. On this page Peel runs Homebrew’s own commands and reads what they report. Forget, which Peel does itself, moves a cask’s Homebrew receipt to the Trash."
            )
        }
    }

    private var maintenance: some View {
        Section {
            row(
                title: "Update Homebrew",
                detail: Text("Gets the newest Homebrew and its newest list of packages, so run it before looking for updates. It upgrades nothing, though Homebrew may move a renamed package to its new name, reinstall pkgconf after a macOS update, or delete an old copy of its core taps it no longer needs."),
                systemImage: "arrow.triangle.2.circlepath",
                command: .update
            ) {
                Button("Update") { start(.update) }
            }
            row(
                title: "Clean Up",
                detail: cleanUpDetail,
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
                title: "Clear Older Downloads",
                detail: Text("Deletes every file in Homebrew’s cache older than 30 days, as well as what Clean Up deletes."),
                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                command: .clearOlderDownloads
            ) {
                Button("Clear") { confirming = .clearOlderDownloads }
            }
            row(
                title: "Clear Every Download",
                detail: Text("Deletes every download Homebrew keeps, even for the latest versions, as well as what Clean Up deletes. The downloads of what is installed now stay."),
                systemImage: "tray.full",
                command: .clearEveryDownload
            ) {
                Button("Clear") { confirming = .clearEveryDownload }
            }
            row(
                title: "Repair Taps",
                detail: Text("Adds the links missing from your taps’ manual pages and shell completions, and follows a tap whose main branch was renamed. It deletes nothing."),
                systemImage: "wrench.adjustable",
                command: .repairTaps
            ) {
                Button("Repair") { confirming = .repairTaps }
            }
            row(
                title: "Check Health",
                detail: Text("Asks Homebrew to check itself and report anything out of place, such as a broken link. It only looks and changes nothing. It can’t see the PATH your Terminal uses, so problems there don’t show up here."),
                systemImage: "stethoscope",
                command: .health
            ) {
                Button("Check") { start(.health) }
            }
            row(
                title: "Scan for Vulnerabilities",
                detail: Text("Checks the installed formulae against the OSV.dev list of known vulnerabilities. Homebrew sends the source and version of each one to api.osv.dev, and only when you click Scan. Casks aren’t covered."),
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
                    StatusLabel(
                        title: Text("Homebrew found nothing out of place."), systemImage: "checkmark.circle", tint: .green
                    )
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
                                Group {
                                    if advisory.checkedTheCurrentFormula {
                                        Text("^[\(advisory.vulnerabilities.count) vulnerability](inflect: true)")
                                    } else {
                                        Text("\(advisory.version) · ^[\(advisory.vulnerabilities.count) vulnerability](inflect: true)")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Badge(
                                title: Text(advisory.highestSeverity.title),
                                systemImage: advisory.highestSeverity.symbol,
                                tint: advisory.highestSeverity.color
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
                if !report.checkedTheCurrentFormula.isEmpty {
                    Text("For ^[\(report.checkedTheCurrentFormula.count) formula](inflect: true), Homebrew can’t tell which source the installed version came from, so it checked the current formula instead: \(RemovalFailureAlert.listedFormulae(report.checkedTheCurrentFormula)).")
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

    /// Whether the page asks for Update Homebrew above lists it read before Homebrew's own definitions went: with no
    /// list read, the page holds only that question.
    static func asksToUpdateAboveTheLists(needsDefinitions: Bool, packages: [HomebrewPackage]?) -> Bool {
        needsDefinitions && packages?.isEmpty == false
    }

    @ViewBuilder
    private var updateFirst: some View {
        if let reason = homebrew.whyItCantChange {
            cantChange(reason)
        } else {
            Notice(
                title: Text("Homebrew Has to Update First"),
                detail: Text("Homebrew’s own list of packages isn’t on this Mac, so asking it about packages would download the list again. Peel doesn’t start that on its own."),
                kind: .note
            ) {
                Button("Update Homebrew") { start(.update) }
                    .disabled(isBusy)
            }
            .padding(.vertical, 6)
            .listRowSeparator(.hidden)
        }
    }

    private func cantChange(_ reason: HomebrewLibrary.CantChange) -> some View {
        Notice(title: Text(reason.title), detail: Text(reason.detail), kind: .note) {
            if let command = reason.command {
                CopyButton(text: command)
            }
        }
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
    }

    private func count(of kind: HomebrewPackage.Kind) -> Text {
        guard let count = homebrew.count(of: kind) else {
            return Text(verbatim: String(localized: "Unknown (Homebrew count)", defaultValue: "Unknown"))
        }
        return Text(count, format: .number).monospacedDigit()
    }

    @ViewBuilder
    private var empty: some View {
        if let failure = homebrew.couldNotRead {
            Section {
                Notice(
                    title: Text("Homebrew didn’t say what is installed"),
                    detail: failure.output.map {
                        Text(verbatim: FixedSentence.translated($0.trimmingCharacters(in: .whitespacesAndNewlines)))
                    },
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
                            Badge(title: Text("Pinned"), systemImage: "pin")
                        } else if homebrew.isExcluded(package) {
                            Badge(title: Text("Excluded in Settings"), systemImage: "hand.raised.fill")
                        } else if package.upgradeNeedsAnAdministrator || homebrew.leavesChangesToTerminal {
                            Badge(title: Text("Needs Terminal"), systemImage: "terminal")
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(HomebrewRow.package(package.id))
                }
            } header: {
                SectionHeaderLine {
                    heading("Updates Available", "Homebrew has a newer version of these. A pinned package is held on purpose, so it is listed and left alone.")
                } actions: {
                    BusyShown(isBusy: homebrew.commandHomebrewRuns == .upgradeAll) { isShown in
                        if isShown {
                            ProgressView().controlSize(.small).transition(.opacity)
                        }
                    }
                    .motion(value: homebrew.commandHomebrewRuns == .upgradeAll)
                    Button { isConfirmingUpgradeAll = true } label: {
                        Text("Upgrade All")
                            .minimumTarget()
                    }
                        .buttonStyle(.borderless)
                        .disabled(
                            homebrew.upgradable.isEmpty || isBusy || homebrew.quittingToUpgrade.isWaiting
                                || !homebrew.mayChange
                                || homebrew.upgradable.contains { $0.kind == .cask } && !library.knowsHomebrewsApps
                        )
                }
            }
        }
    }

    @ViewBuilder
    private func alreadyGone(_ casks: [HomebrewPackage]) -> some View {
        if !casks.isEmpty {
            Section {
                RemovalsHeldBanner()
                ForEach(casks) { cask in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: cask.name)
                            .lineLimit(1)
                        Text(verbatim: cask.installedVersion ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .tag(HomebrewRow.package(cask.id))
                }
            } header: {
                SectionHeaderLine {
                    heading(
                        "Apps Already Gone",
                        "Homebrew still lists these casks, but their apps aren’t where Homebrew put them anymore, or macOS has no receipt left for the packages they installed. Forgetting a cask moves its Homebrew receipt to the Trash, with the links Homebrew made into it in its command and completion folders, so Homebrew stops listing it. History can put it back."
                    )
                } count: {
                    Text("^[\(casks.count) cask](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } actions: {
                    BusyShown(isBusy: !homebrew.casksBeingForgotten.isEmpty) { isShown in
                        if isShown {
                            ProgressView().controlSize(.small).transition(.opacity)
                        }
                    }
                    .motion(value: homebrew.casksBeingForgotten.isEmpty)
                    Button { casksToForget = casks } label: {
                        Text("Forget All")
                            .minimumTarget()
                    }
                        .buttonStyle(.borderless)
                        .disabled(isBusy || !history.mayMove || !homebrew.mayChange)
                        .help(Text(verbatim: history.holdingReason?.explanation ?? ""))
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
                        if package.waitsForAnUpgrade {
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
        detail: Text,
        systemImage: String,
        command: HomebrewLibrary.Command,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 6) {
            Label { Text(title) } icon: { Image(systemName: systemImage) }
            InfoNote(name: String(localized: title), detail: detail)
            Spacer(minLength: 8)
            BusyShown(isBusy: homebrew.commandHomebrewRuns == command) { isShown in
                if isShown {
                    ProgressView().controlSize(.small).transition(.opacity)
                }
            }
            .motion(value: homebrew.commandHomebrewRuns == command)
            // Only the controls are disabled while Homebrew is busy, so the info note can still be opened.
            trailing()
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy || !command.onlyLooks && !homebrew.mayChange)
        }
        .padding(.vertical, 1)
    }

    private func start(_ command: HomebrewLibrary.Command) {
        Task { await homebrew.run(command) }
    }

    private func upgradeAll() {
        let quit = QuitBeforeHomebrew(homebrew.upgradableNow, library: library)
        homebrew.quittingToUpgrade.check(quit.processes) {
            Task { await homebrew.run(.upgradeAll, reopening: quit.reopen) }
        }
    }

    private var isBusy: Bool {
        homebrew.runningCommand != nil || homebrew.isForgetting || homebrew.isScanning
    }

    /// The packages for the Formulae and Casks sections. Outdated and retired packages, and casks whose apps are
    /// gone, have their own sections above, so they are left out here, except during a search, which hides those
    /// sections.
    private var listed: [HomebrewPackage] {
        guard searchText.isEmpty else { return filteredPackages }
        return (homebrew.packages ?? []).filter {
            !$0.waitsForAnUpgrade && $0.retirement == nil && !$0.isMissingWhatItInstalled
        }
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
        if let chosen = homebrew.unrunnableChoice {
            ContentUnavailableView {
                Label("Peel Can’t Run the `brew` You Chose", systemImage: "mug")
            } description: {
                VStack(spacing: 6) {
                    if let brew = chosen.brew {
                        Text("Peel runs only the `brew` you chose in Settings, \(brew.abbreviatedPath), and that one can’t be run now.")
                    }
                    chosen.refusal.explanation
                }
            } actions: {
                Button("Open Peel Settings") { SettingsPane.general.open(with: openSettings) }
            }
        } else if let refused = homebrew.refusedBrew {
            ContentUnavailableView {
                Label("Peel Doesn’t Run This Homebrew", systemImage: "mug")
            } description: {
                VStack(spacing: 6) {
                    if let brew = refused.brew {
                        Text("Homebrew’s `brew` is in \(brew.abbreviatedPath), and Peel doesn’t run it.")
                    }
                    refused.refusal.explanation
                }
            } actions: {
                Button("Homebrew Is in Another Folder") { SettingsPane.general.open(with: openSettings) }
            }
        } else if !homebrew.isInstalled {
            ContentUnavailableView {
                Label("Homebrew Isn’t Installed", systemImage: "mug")
            } description: {
                Text("Install Homebrew to manage command-line tools and apps from Peel.")
            } actions: {
                EmptyStateActions {
                    if let url = URL(string: "https://brew.sh") {
                        Link(destination: url) {
                            Text("Open brew.sh")
                                .minimumTarget()
                        }
                    }
                    Button("Homebrew Is in Another Folder") { SettingsPane.general.open(with: openSettings) }
                }
            }
        } else if homebrew.needsDefinitions, homebrew.packages?.isEmpty != false, homebrew.runningCommand == nil,
                  let reason = homebrew.whyItCantChange {
            ContentUnavailableView {
                Label(reason.title, systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text(reason.detail)
            } actions: {
                if let command = reason.command {
                    CopyButton(text: command)
                }
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
    @Environment(HomeModel.self) private var home
    let result: HomebrewLibrary.CommandResult
    /// True when the command replaced Peel, so the only way on is the new copy.
    var replacedPeel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                switch result.ending {
                case .finished: Text("Homebrew finished").font(.headline)
                case .failed: Text("Homebrew couldn’t finish").font(.headline)
                case .notRun: Text("Peel didn’t run Homebrew").font(.headline)
                }
            } icon: {
                switch result.ending {
                case .finished: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                case .notRun: Image(systemName: "info.circle.fill").foregroundStyle(.secondary)
                }
            }
            if replacedPeel {
                Text("Homebrew updated Peel while it was open. Reopen Peel to finish.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !result.succeeded, Homebrew.askedForAPassword(in: result.output) {
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
                if replacedPeel {
                    Button("Reopen Peel") {
                        dismiss()
                        home.relaunch()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 560)
        .interactiveDismissDisabled(replacedPeel)
    }
}
