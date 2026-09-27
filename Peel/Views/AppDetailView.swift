import PeelCore
import SwiftUI

struct AppDetailView: View {
    @Environment(AppLibrary.self) private var library
    @Environment(HelperModel.self) private var helper
    @Environment(HomeModel.self) private var home
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(HomebrewLibrary.self) private var homebrew
    @State private var plan: RemovalPlan
    @State private var isShowingQuitAlert = false
    @Environment(RemovalOutcome.self) private var outcome
    @State private var isRescanning = false
    @State private var resetsPrivacy = false
    @State private var isConfirmingPrivacyReset = false
    /// The result of the last privacy reset started from the More menu, shown under the buttons.
    @State private var privacyReset: PrivacyReset.Result?
    @State private var upgrade: Upgrade?
    @State private var upgradeOutput: HomebrewLibrary.CommandResult?
    @Environment(\.notifications) private var notifications
    @State private var isShowingReset = false
    @State private var resetChangedFiles = false

    /// The result of the last upgrade started from this page, shown under the buttons.
    private enum Upgrade: Equatable {
        case done(String?)
        case failed
    }

    init(app: InstalledApp) {
        _plan = State(initialValue: RemovalPlan(app: app))
    }

    var body: some View {
        page
        .confirmationDialog(
            Text.movingToTrash(plan.question.request?.urls.count ?? 0, plan.question.request?.total ?? SizeTotal([])),
            isPresented: Bindable(plan.question).isAsking
        ) {
            Button("Move to Trash") {
                guard let request = plan.question.start() else { return }
                Task { await remove(request) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let removalNote {
                removalNote
            }
        }
        .confirmationDialog(Text("Reset privacy permissions for \(plan.app.name)?"), isPresented: $isConfirmingPrivacyReset) {
            Button("Reset", role: .destructive) {
                Task { privacyReset = await PrivacyReset.reset(bundleIdentifier: plan.app.bundleIdentifier) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("macOS forgets what \(plan.app.name) was allowed to access, such as the camera, the microphone, or your files, and the app asks you again the next time it needs them. History can’t undo this.")
        }
        .alert("Quit \(plan.app.name) before removing it.", isPresented: $isShowingQuitAlert) {
            Button("Quit \(plan.app.name)") { plan.quitApp() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $isShowingReset, onDismiss: {
            guard resetChangedFiles else { return }
            resetChangedFiles = false
            Task { await rescan() }
        }) {
            ResetSheet(app: plan.app, changedFiles: $resetChangedFiles)
        }
        .sheet(item: $upgradeOutput) { result in
            HomebrewOutputView(result: result)
        }
        // Keyed to what Homebrew knows: evidence that arrives after the page opened is a reason to look again.
        .task(id: homebrew.evidenceRevision) {
            // Arrowing down the list puts a page on screen for every row passed. The wait means a row left
            // this quickly never starts its scan.
            try? await Task.sleep(for: .milliseconds(150))
            // A scan stopped with nothing found waits for Scan Again, whatever arrives meanwhile.
            guard !Task.isCancelled, !(plan.scan == nil && plan.scanRun.wasStopped) else { return }
            await rescan()
        }
        .rescanOnExclusionChange("AppDetailView") { await rescan() }
        .onChange(of: helper.canAct) { _, canAct in
            plan.follow(canUseHelper: canAct)
        }
        .onChange(of: plan.selectedURLs) { _, selected in
            plan.question.selectionChanged(to: selected)
        }
        .onChange(of: plan.question.isAsking) {
            if plan.question.hasWaitingScan {
                Task { await rescan() }
            }
        }
    }

    private var phase: ScanPhase {
        if plan.scan != nil { return .content }
        return plan.scanRun.wasStopped ? .stopped : .scanning(.walk)
    }

    private var page: some View {
        List {
            AppHeader(
                app: plan.app,
                updateStatus: library.shownUpdateStatus(of: plan.app),
                isCheckingForUpdates: library.appsCheckingForUpdates.contains(plan.app.id),
                waitingVersion: waitingVersion == nil ? nil : library.updateStatuses[plan.app.id]?.displayVersion,
                lastCheck: library.lastUpdateChecks[plan.app.id],
                total: plan.total
            ) {
                appActions
            }
            .listRowSeparator(.hidden)

            ExclusionsUnreadableBanner()
            if plan.isExcluded {
                Notice(
                    title: Text("This app is excluded"),
                    detail: Text("Peel leaves it and its files alone. Change that in Settings."),
                    kind: .note
                ) {
                    SettingsLink {
                        Text("Open Peel Settings")
                    }
                }
                .listRowSeparator(.hidden)
            }
            if plan.isPeel {
                Notice(
                    title: Text("Peel removes itself in Settings"),
                    detail: Text("Remove Peel, in Settings > General, removes its helper and login item as well. Moved from here, Peel would leave them behind."),
                    kind: .note
                ) {
                    SettingsLink {
                        Text("Open Peel Settings")
                    }
                }
                .listRowSeparator(.hidden)
            }
            if let scan = plan.scan {
                if !scan.unreadableLocations.isEmpty {
                    FullDiskAccessBanner()
                }
                if !scan.cutShortLocations.isEmpty {
                    Notice(
                        title: Text("Peel didn’t look everywhere"),
                        detail: Text("There are more folders in \(scan.cutShortLocations.map(\.url.abbreviatedPath).formatted(.list(type: .and))) than Peel looks inside, so something of this app’s may be in a folder Peel didn’t reach."),
                        kind: .note
                    ) {}
                    .listRowSeparator(.hidden)
                }
                if plan.requiresHelper, !helper.canAct {
                    HelperRequiredBanner()
                }

                Group {
                    if let change = library.teamChanges[plan.app.bundleIdentifier] {
                        Notice(
                            title: change.current.isEmpty ? Text("No developer signs this app anymore") : Text("This app is signed by someone else now"),
                            detail: change.current.isEmpty
                                ? Text("It was first seen signed by \(change.previous). A copy someone has changed looks like this, and so does one built from source.")
                                : Text("It was first seen signed by \(change.previous), and is signed by \(change.current) now."),
                            kind: .caution,
                            systemImage: "exclamationmark.shield.fill"
                        ) {
                            Button("Got It") { Task { await library.acknowledgeTeamChange(for: plan.app) } }
                        }
                        .listRowSeparator(.hidden)
                    }

                    SystemExtensionNotice(app: plan.app, extensions: plan.systemExtensions)
                        .listRowSeparator(.hidden)

                    recommendedSection
                    reviewSection
                    if PrivacyReset.isAllowed(bundleIdentifier: plan.app.bundleIdentifier) {
                        PrivacyResetRow(isOn: $resetsPrivacy, detail: PrivacyResetRow.beforeTheMove)
                    }
                    defaultsSection
                    PackageReceiptSection(app: plan.app, isExcluded: plan.isExcluded)
                }
                .opacity(isAtWork ? Busy.dimmed : 1)
                .disabled(isAtWork)
                .motion(value: isAtWork)
            }
        }
        .scanState(phase, fadesInResults: false, scan: plan.scanRun)
        .safeAreaBar(edge: .bottom) {
            if plan.scan != nil {
                let selected = plan.request.total
                RemovalBar(
                    selectedSize: selected.known,
                    isSelectionMeasured: selected.isComplete,
                    isScanning: isBusy,
                    scan: plan.scanRun,
                    isEnabled: !plan.selectedURLs.isEmpty && !plan.isRemoving,
                    onRemove: requestRemoval
                )
            }
        }
        .navigationTitle(plan.app.name)
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem {
                RescanButton(isRunning: $isRescanning, isDisabled: plan.isRemoving, scan: plan.scanRun) {
                    await plan.refresh(installedApps: library.apps, canUseHelper: helper.canAct, casks: homebrew.caskEvidence, receipts: homebrew.receipts)
                    // In a task of its own, so the page isn't dimmed during the update check, which can take
                    // half a minute. The badge in the header shows that the check is running.
                    let app = plan.app
                    Task { await library.checkForUpdates([app], force: true) }
                }
            }
        }
    }

    /// The kinds of files and links this app opens by default, and which app would open them once it is gone.
    @ViewBuilder
    private var defaultsSection: some View {
        if !plan.defaultRoles.isEmpty {
            Section {
                ForEach(plan.defaultRoles) { role in
                    VStack(alignment: .leading, spacing: 2) {
                        role.kind == .link ? Text("\(role.identifier): links") : Text(verbatim: role.name)
                        if role.others.isEmpty {
                            Text("Nothing else on this Mac opens these.")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Text("Then \(role.others.first ?? "") would open these.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listRowSeparator(.hidden)
            } header: {
                heading(
                    "Opens These by Default",
                    "Peel never changes which app opens what. For a kind of file, choose that in Finder, with Get Info. For a kind of link, choose it in System Settings or in the app itself."
                )
            }
        }
    }

    private var recommendedSection: some View {
        Section {
            RemovalColumnHeaders()
            RemovalRow(
                url: plan.app.url,
                icon: .file(plan.app.url),
                detail: "The app itself. Everything under it is what Peel found for this app elsewhere on this Mac.",
                kind: "Application",
                warning: appWarning,
                size: plan.appSize,
                isMeasured: plan.isAppMeasured,
                isLocked: plan.appRequiresPrivileges && !helper.canAct,
                isExcluded: plan.isExcluded,
                isLeftAlone: plan.app.isSystemProtected || plan.isAppBeyondTheHelper || plan.isPeel,
                appIdentifier: plan.app.bundleIdentifier,
                selection: plan, isSelected: plan.isSelected(plan.app.url)
            )
            .listRowSeparator(.hidden)
            ForEach(plan.recommended) { leftover in
                row(for: leftover)
            }
            .listRowSeparator(.hidden)
        } header: {
            sectionHeader(
                heading(
                    "Recommended",
                    "Everything selected here goes to the Trash together when you click Move to Trash. Nothing is deleted outright: History can put it back while it’s in the Trash."
                ),
                movable: plan.recommendedMovable,
                selectable: recommendedSelectable
            )
        }
    }

    /// The Recommended rows a checkbox can select, for its Select All. Review Before Removing has no Select All,
    /// because nothing there should be selected without being read.
    private var recommendedSelectable: [URL] {
        ([plan.app.url] + plan.recommended.map(\.url)).filter(plan.selectable.contains)
    }

    @ViewBuilder
    private var reviewSection: some View {
        if !plan.needsReview.isEmpty {
            Section {
                RemovalColumnHeaders()
                ForEach(plan.needsReview) { leftover in
                    row(for: leftover)
                }
                .listRowSeparator(.hidden)
            } header: {
                sectionHeader(
                    heading(
                        "Review Before Removing",
                        "These are here because Peel is less sure about them, another app on this Mac uses them too, or Peel held them back for the reason each row gives. Nothing here is selected for you: read each one and select only what you recognize."
                    ),
                    movable: plan.reviewMovable
                )
            }
        }
    }

    private var appWarning: String? {
        if plan.isPeel {
            return String(localized: "Left alone: Peel removes itself only from Settings.")
        }
        if plan.app.isSystemProtected {
            return String(localized: "macOS keeps this app, so it stays where it is.")
        }
        return plan.isAppBeyondTheHelper ? String(localized: HoldBack.beyondTheHelper.explanation) : nil
    }

    /// A section heading with, at its other end, how many of its items can move and their total size, so the
    /// user sees how much is about to move without adding up the rows.
    private func sectionHeader(_ title: some View, movable: (count: Int, size: SizeTotal), selectable: [URL] = []) -> some View {
        SectionHeaderLine {
            title
        } count: {
            Text("^[\(movable.count) item](inflect: true) · \(movable.size.text)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } actions: {
            SelectAllButton(selectable: selectable, selection: $plan.selectedURLs)
        }
    }

    /// The version an update would bring. Nil when there is no update, or when the user muted this app or
    /// this version.
    private var waitingVersion: String? {
        library.hasUpdate(plan.app) ? library.updateStatuses[plan.app.id]?.version : nil
    }

    private var updateSource: UpdateSource? {
        library.updateStatuses[plan.app.id]?.source
    }

    /// What can be done to the app without removing it: update it, open its maker's uninstaller, or reset it.
    /// Less common actions, such as the release notes or muting updates, sit in the More menu.
    private var appActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout {
                if let version = waitingVersion, let source = updateSource {
                    updateAction(for: source, version: version)
                }
                if let uninstaller = plan.vendorUninstaller {
                    Button("Open Uninstaller", systemImage: "arrow.up.forward.app") {
                        NSWorkspace.shared.open(uninstaller)
                    }
                    .buttonStyle(.bordered)
                    .disabled(plan.isExcluded)
                    .help(plan.isExcluded ? Text(.excludedApp) : Text("Run the maker’s uninstaller first: it knows what Peel can only guess at."))
                }
                // Not on Peel's own page: Peel is always open, so the sheet could only ever offer to quit it.
                if plan.app.bundleIdentifier != Bundle.main.bundleIdentifier {
                    Button("Reset\u{2026}") { isShowingReset = true }
                        .buttonStyle(.bordered)
                        .disabled(plan.isExcluded)
                        .help(plan.isExcluded ? Text(.excludedApp) : Text("Make \(plan.app.name) forget its settings without uninstalling it"))
                }
                moreMenu
            }
            if let upgrade {
                outcome(of: upgrade)
            } else if let source = updateSource, waitingVersion != nil {
                Text(updateExplanation(for: source))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let privacyReset {
                outcome(of: privacyReset)
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            if let notes = library.updateStatuses[plan.app.id]?.releaseNotes {
                Button("Release Notes") { NSWorkspace.shared.open(notes) }
            }
            if let version = waitingVersion {
                Button("Skip This Version") { library.skip(version: version, for: plan.app) }
            }
            Toggle("Never Check This App", isOn: Binding(
                get: { library.isIgnored(plan.app) },
                set: { library.setIgnored($0, for: plan.app) }
            ))
            Divider()
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([plan.app.url])
            }
            if PrivacyReset.isAllowed(bundleIdentifier: plan.app.bundleIdentifier) {
                Divider()
                Button("Reset Privacy Permissions\u{2026}") { isConfirmingPrivacyReset = true }
                    .disabled(plan.isExcluded)
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .labelStyle(.iconOnly)
        .fixedSize()
        .help(Text("More options for \(plan.app.name)"))
        .accessibilityLabel(Text("More options for \(plan.app.name)"))
    }

    private func updateExplanation(for source: UpdateSource) -> LocalizedStringResource {
        switch source {
        case .appStore: "The App Store has it. Update from the App Store."
        case .homebrew: "Homebrew has it. Peel can run the upgrade for you."
        case .developer, .automatic: "The maker has it. Update from inside the app."
        }
    }

    @ViewBuilder
    private func updateAction(for source: UpdateSource, version: String) -> some View {
        switch source {
        case .appStore:
            Button("Open App Store", systemImage: "bag") {
                let page = library.updateStatuses[plan.app.id]?.releaseNotes
                NSWorkspace.shared.open(page ?? URL(string: "macappstore://showUpdatesPage")!)
            }
            .buttonStyle(.borderedProminent)
        case .homebrew:
            Button {
                Task { await upgradeWithHomebrew() }
            } label: {
                if isUpgrading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Upgrading\u{2026}")
                    }
                } else {
                    Label("Upgrade with Homebrew", systemImage: "mug")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(homebrew.runningCommand != nil)
        case .developer, .automatic:
            Button("Open \(plan.app.name)", systemImage: "arrow.up.forward.app") {
                NSWorkspace.shared.open(plan.app.url)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// A reset moves files to the Trash, and an exclusion changes what may be listed at all, so after either
    /// one the tables are out of date. A scan asked for while the question is up or a removal runs waits for them.
    private func rescan() async {
        guard plan.question.mayScan() else { return }
        await plan.refresh(installedApps: library.apps, canUseHelper: helper.canAct, casks: homebrew.caskEvidence, receipts: homebrew.receipts)
    }

    private var isUpgrading: Bool {
        guard let cask = library.cask(for: plan.app) else { return false }
        return homebrew.runningCommand == .upgrade(cask.id)
    }

    /// Upgrades the app with Homebrew, which can take a while. The button shows progress while it runs, the
    /// line under it shows the result, and a notification reports it too, in case the user has moved on.
    private func upgradeWithHomebrew() async {
        guard let cask = library.cask(for: plan.app) else { return }
        upgrade = nil
        // Nil when Homebrew is already running a command. The button is disabled then, so this is only a safeguard.
        guard let result = await homebrew.run(.upgrade(cask.id), showsResult: false) else { return }
        let succeeded = result.succeeded
        upgradeOutput = succeeded ? nil : result

        // The bundle on disk is a different one now, so the page is built again around what is there.
        // Homebrew's own answer is read again first: it is what says whether a version is behind, and the
        // copy from before the upgrade still said this one was.
        await library.refresh()
        library.loadHomebrewCasks(homebrew.caskEvidence)
        if let installed = library.apps.first(where: { $0.id == plan.app.id }) {
            plan = RemovalPlan(app: installed)
            await plan.refresh(installedApps: library.apps, canUseHelper: helper.canAct, casks: homebrew.caskEvidence, receipts: homebrew.receipts)
        }
        await library.checkForUpdates([plan.app], force: true)

        upgrade = succeeded ? .done(plan.app.version) : .failed
        // A notification either way, so the user learns how it went even after leaving the page.
        if succeeded {
            notifications?.notify(appUpgraded: plan.app.name, to: plan.app.version, app: plan.app.url)
        } else {
            notifications?.notify(appUpgradeFailed: plan.app.name, app: plan.app.url)
        }
    }

    @ViewBuilder
    private func outcome(of upgrade: Upgrade) -> some View {
        switch upgrade {
        case .done(let version):
            Label {
                if let version {
                    Text("Now on \(version).")
                } else {
                    Text("Homebrew finished the upgrade.")
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .font(.caption)
            .foregroundStyle(.green)
        case .failed:
            Label("Homebrew couldn’t finish the upgrade.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func outcome(of privacyReset: PrivacyReset.Result) -> some View {
        if let problem = privacyReset.explanation {
            Label("Privacy permissions weren’t reset. \(problem)", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        } else {
            Label("Privacy permissions were reset. \(plan.app.name) asks you again the next time it needs them.", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    private func row(for leftover: Leftover) -> some View {
        RemovalRow(
            url: leftover.url,
            icon: .symbol(leftover.kind.symbolName),
            detail: leftover.match.reason.title,
            kind: leftover.kind.title,
            warning: warning(for: leftover),
            size: leftover.size,
            isMeasured: leftover.isMeasured,
            isLocked: leftover.requiresPrivileges && !helper.canAct,
            isExcluded: leftover.match.heldBack == .holdsAnExclusion,
            isLeftAlone: leftover.match.heldBack?.cannotBeMoved == true || plan.isPeel,
            selection: plan, isSelected: plan.isSelected(leftover.url)
        )
    }

    /// What the row has to say for itself beyond the match: who else uses it, and why Peel left the checkmark off.
    private func warning(for leftover: Leftover) -> String? {
        var lines: [String] = []
        if leftover.match.isShared {
            let users = leftover.match.sharedWith.map(library.name(forBundleIdentifier:))
                + leftover.match.otherCopies.map(\.abbreviatedPath)
            lines.append(String(localized: "Also used by \(users.formatted(.list(type: .and)))"))
        }
        if let heldBack = leftover.match.heldBack {
            lines.append(String(localized: heldBack.explanation))
        }
        if plan.isPeel {
            lines.append(String(localized: "Left alone: Peel removes itself only from Settings."))
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }

    private var isBusy: Bool {
        isRescanning || (plan.isScanning && plan.scan != nil)
    }

    /// True while the page scans again or a removal runs, when its rows take no clicks.
    private var isAtWork: Bool {
        isBusy || plan.isRemoving
    }

    /// The app, when a removal of `urls` resets its privacy permissions.
    private func resetting(_ urls: Set<URL>) -> [InstalledApp] {
        resetsPrivacy ? PrivacyReset.apps(among: [plan.app], moving: urls) : []
    }

    /// The confirmation's message: the privacy reset, which History can't undo, and Homebrew's own record
    /// of the app, which the move doesn't touch.
    private var removalNote: Text? {
        let privacy = resetting(plan.question.request?.urls ?? []).isEmpty
            ? nil
            : Text("The app’s privacy permissions are cleared first, and History can’t bring them back.")
        // Homebrew keeps its own record of what it installed, and moving the bundle does not touch it.
        let cask = library.cask(for: plan.app).map {
            Text("Homebrew installed this app and will keep listing it as installed. To take it off that list, run `brew uninstall --cask \($0.name)`: Homebrew then carries out the cask’s own uninstall steps, which can delete files for good.")
        }
        switch (privacy, cask) {
        case let (privacy?, cask?): return Text("\(privacy)\n\n\(cask)")
        case let (privacy?, nil): return privacy
        case let (nil, cask?): return cask
        case (nil, nil): return nil
        }
    }

    private func requestRemoval() {
        if plan.selectedURLs.contains(plan.app.url), plan.isAppRunning {
            isShowingQuitAlert = true
        } else {
            plan.question.ask(plan.request)
        }
    }

    /// One removal, from the privacy reset before the move to the scan after it, with the page busy throughout.
    private func remove(_ request: RemovalRequest) async {
        let plan = plan
        defer { plan.question.finish() }
        // The one step that goes before the move: `tccutil` only finds an app that is still in its place.
        let privacy = await PrivacyReset.reset(resetting(request.urls))
        let result = await plan.move(request)
        outcome.report(result, privacy: privacy)
        if let state = AppManagement.state(after: result, appBundles: [plan.app.url], movedByTheHelper: plan.privilegedURLs) {
            home.record(appManagement: state)
        }
        await history.record(result, tool: .applications, source: plan.app.name, sizes: request.sizes)

        if result.trashed.contains(where: { $0.originalURL == plan.app.url }) {
            await library.load()
        } else {
            await plan.refresh(installedApps: library.apps, canUseHelper: helper.canAct, casks: homebrew.caskEvidence, receipts: homebrew.receipts)
        }
    }
}
