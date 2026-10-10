import PeelCore
import SwiftUI

struct AppDetailView: View {
    @Environment(AppLibrary.self) private var library
    @Environment(HelperModel.self) private var helper
    @Environment(HomeModel.self) private var home
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(HomebrewLibrary.self) private var homebrew
    @State private var plan: RemovalPlan
    @State private var quitting = QuitBeforeRemoving()
    @Environment(RemovalOutcome.self) private var outcome
    @State private var isRescanning = false
    @State private var resetsPrivacy = false
    @State private var progress = MoveProgress()
    @State private var removesDockTile = true
    @State private var isConfirmingPrivacyReset = false
    /// The result of the last privacy reset started from the More menu, shown under the buttons.
    @State private var privacyReset: PrivacyReset.Result?
    @State private var upgradeOutput: HomebrewLibrary.CommandResult?
    @Environment(\.openSettings) private var openSettings
    @State private var isShowingReset = false
    @State private var resetChangedFiles = false

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
                if let identifier = plan.app.bundleIdentifier {
                    Task { privacyReset = await PrivacyReset.reset(bundleIdentifier: identifier) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("macOS forgets what \(plan.app.name) was allowed to access, such as the camera, the microphone, or your files, and the app asks you again the next time it needs them. History can’t undo this.")
        }
        .alert(quitTitle, isPresented: Bindable(quitting).isAsking) {
            Button("Quit \(plan.app.name)") { quitting.quit() }
            Button("Cancel", role: .cancel) { quitting.giveUp() }
        } message: {
            Text(verbatim: quitting.names)
        }
        .forceQuitOffer(quitting)
        .onDisappear { quitting.giveUp() }
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
        .rescanOnExclusionChange(scannedUnder: plan.exclusionsRevision) { await rescan() }
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
            AppPageHeader(
                plan: plan,
                privacyReset: privacyReset,
                isShowingReset: $isShowingReset,
                isConfirmingPrivacyReset: $isConfirmingPrivacyReset,
                upgradeOutput: $upgradeOutput
            )
            .listRowSeparator(.hidden)

            RemovalsHeldBanner()
            if plan.isExcluded {
                Notice(
                    title: Text("This app is excluded"),
                    detail: Text("Peel leaves it and its files alone. Change that in Settings."),
                    kind: .note
                ) {
                    Button("Open Peel Settings") { SettingsPane.exclusions.open(with: openSettings) }
                }
                .listRowSeparator(.hidden)
            }
            if plan.removedElsewhere == .byRemovePeel {
                Notice(
                    title: Text("Peel removes itself in Settings"),
                    detail: Text("Remove Peel, in Settings > General, removes its helper and login item as well. Moved from here, Peel would leave them behind."),
                    kind: .note
                ) {
                    Button("Open Peel Settings") { SettingsPane.general.open(with: openSettings) }
                }
                .listRowSeparator(.hidden)
            }
            if case .byItsMaker(let uninstaller) = plan.removedElsewhere {
                MakersUninstallerNotice(app: plan.app.name, uninstaller: uninstaller)
                    .listRowSeparator(.hidden)
            }
            if case .browser(let identifier) = plan.app.webApp {
                let browser = library.name(forReference: identifier)
                Notice(
                    title: Text("A web app of \(browser)"),
                    detail: Text("Moving it to the Trash takes away only this shortcut, and the app stays in \(browser), which can make the shortcut again. To remove the app itself, uninstall it in \(browser), which takes the shortcut away too."),
                    kind: .note
                ) {}
                .listRowSeparator(.hidden)
            }
            if let change = plan.app.bundleIdentifier.flatMap({ library.teamChanges[$0] }) {
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
            if let scan = plan.scan {
                if scan.needsFullDiskAccess {
                    FullDiskAccessBanner()
                } else if !scan.unreadableLocations.isEmpty {
                    UnreadableFoldersNotice(folders: scan.unreadableLocations.map(\.url))
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
                    SystemExtensionNotice(app: plan.app, extensions: plan.systemExtensions)
                        .listRowSeparator(.hidden)

                    recommendedSection
                    reviewSection
                    if !PrivacyReset.apps(among: [plan.app], moving: plan.selectable).isEmpty {
                        PrivacyResetRow(isOn: $resetsPrivacy, detail: PrivacyResetRow.beforeTheMove)
                    }
                    if plan.hasDockTile, plan.selectable.contains(plan.app.url) {
                        DockTileRow(isOn: $removesDockTile)
                    }
                    defaultsSection
                    PackageReceiptSection(plan: plan, rescan: rescan)
                }
                .dimmedWhileBusy(isAtWork)
                .disabled(plan.isRemoving)
            }
        }
        .scrollBarBelowSectionHeaders()
        .scanState(phase, fadesInResults: false, scan: plan.scanRun)
        .edgeBar(.bottom) {
            if plan.scan != nil {
                let selected = plan.request.total
                RemovalBar(
                    selectedSize: selected.known,
                    isSelectionMeasured: selected.isComplete,
                    isScanning: isBusy,
                    scan: plan.scanRun,
                    isEnabled: !plan.selectedURLs.isEmpty && !plan.isRemoving && !quitting.isWaiting,
                    onRemove: requestRemoval,
                    progress: progress,
                    waitingToQuit: quitting.isWaiting ? quitting.names : nil
                )
            }
        }
        .navigationTitle(plan.app.name)
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem {
                RescanButton(isRunning: $isRescanning, isDisabled: plan.isRemoving, scan: plan.scanRun) {
                    await plan.refresh(
                        installedApps: library.apps,
                        canUseHelper: helper.canAct,
                        casks: homebrew.caskEvidence,
                        receipts: homebrew.receipts
                    )
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
                            StatusLabel(title: Text("Nothing else on this Mac opens these."), tint: .accentColor)
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                isLeftAlone: plan.app.isSystemProtected || plan.app.enclosingPackage != nil || plan.isAppBeyondTheHelper
                    || plan.isAppInTheTrash || plan.removedElsewhere != nil,
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
                list: SelectableRows(
                    rows: recommendedRows, selectable: recommendedSelectable, recommended: recommendedSelectable
                ),
                place: Text("Recommended")
            )
        }
    }

    /// The Recommended rows a checkbox can select, all of them recommended.
    private var recommendedSelectable: [URL] {
        recommendedRows.filter(plan.selectable.contains)
    }

    private var recommendedRows: [URL] {
        [plan.app.url] + plan.recommended.map(\.url)
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
                    movable: plan.reviewMovable,
                    list: SelectableRows(
                        rows: plan.needsReview.map(\.url),
                        selectable: plan.needsReview.map(\.url).filter(plan.selectable.contains),
                        recommended: []
                    ),
                    place: Text("Review Before Removing")
                )
            }
        }
    }

    private var appWarning: String? {
        if let removedElsewhere = plan.removedElsewhere {
            return String(localized: removedElsewhere.explanation)
        }
        if plan.app.isSystemProtected {
            return String(localized: "macOS keeps this app, so it stays where it is.")
        }
        if let package = plan.app.enclosingPackage {
            let name = AppInspector.displayName(of: package)
            return String(localized: "Part of \(name), so it stays where it is.")
        }
        if plan.isAppInTheTrash {
            return String(localized: "Already in the Trash. What it left behind can still go.")
        }
        return plan.isAppBeyondTheHelper ? String(localized: HoldBack.beyondTheHelper.explanation) : nil
    }

    /// A section heading with, at its other end, how many of its items can move and their total size, so the
    /// user sees how much is about to move without adding up the rows.
    private func sectionHeader(
        _ title: some View, movable: (count: Int, size: SizeTotal), list: SelectableRows<URL>? = nil, place: Text? = nil
    ) -> some View {
        SectionHeaderLine {
            title
        } count: {
            Text("^[\(movable.count) item](inflect: true) · \(movable.size.text)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } actions: {
            if let list, let place {
                SelectMenu(list: list, place: place, selection: plan)
            }
        }
    }

    /// A reset moves files to the Trash, and an exclusion changes what may be listed at all, so after either
    /// one the tables are out of date. A scan asked for while the question is up or a removal runs waits for them.
    private func rescan() async {
        guard plan.question.mayScan() else { return }
        await plan.refresh(
            installedApps: library.apps,
            canUseHelper: helper.canAct,
            casks: homebrew.caskEvidence,
            receipts: homebrew.receipts
        )
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
            isLeftAlone: leftover.match.heldBack?.cannotBeMoved == true || plan.removedElsewhere != nil,
            selection: plan, isSelected: plan.isSelected(leftover.url)
        )
    }

    /// What the row has to say for itself beyond the match: who else uses it, and why Peel left the checkmark off.
    private func warning(for leftover: Leftover) -> String? {
        var lines: [String] = []
        if leftover.match.isShared {
            let users = leftover.match.sharedWith.map(library.name(forReference:))
                + leftover.match.otherCopies.map(\.abbreviatedPath)
            lines.append(String(localized: "Also used by \(users.formatted(.list(type: .and)))"))
        }
        if let heldBack = leftover.match.heldBack {
            lines.append(String(localized: heldBack.explanation))
        }
        if leftover.holdsDamagedSettings {
            lines.append(String(localized: "Can’t be read as a property list, so nothing can read these settings."))
        }
        if let removedElsewhere = plan.removedElsewhere {
            lines.append(String(localized: removedElsewhere.explanation))
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }

    private var isBusy: Bool {
        isRescanning || (plan.isScanning && plan.scan != nil)
    }

    /// True while the page scans again or a removal runs, when its rows dim on the `Busy` timing.
    private var isAtWork: Bool {
        isBusy || plan.isRemoving
    }

    /// The app, when a removal of `urls` resets its privacy permissions.
    private func resetting(_ urls: Set<URL>) -> [InstalledApp] {
        resetsPrivacy ? PrivacyReset.apps(among: [plan.app], moving: urls) : []
    }

    /// The confirmation's message: the privacy reset, which History can't undo, an app that uninstalls itself once
    /// it moves, and Homebrew's own record of the app when it stays.
    private var removalNote: Text? {
        let urls = plan.question.request?.urls ?? []
        var lines: [Text] = []
        if !resetting(urls).isEmpty {
            lines.append(Text("The app’s privacy permissions are cleared first, and History can’t bring them back."))
        }
        lines += UninstallsItself.when(moving: urls, among: [plan.app]).map(\.warning)
        let movesItsReceipt = plan.uninstallation?.scan.leftovers.contains {
            $0.kind == .homebrewReceipt && urls.contains($0.url)
        } == true
        if urls.contains(plan.app.url), !movesItsReceipt, let cask = library.cask(for: plan.app) {
            lines.append(Text("Homebrew installed this app and will keep listing it as installed. To take it off that list, run `brew uninstall --cask \(cask.name)`: Homebrew then carries out the cask’s own uninstall steps, which can delete files for good."))
        }
        guard let first = lines.first else { return nil }
        return lines.dropFirst().reduce(first) { Text("\($0)\n\n\($1)") }
    }

    /// Asks the question once the app has quit, since none of its files moves while it runs, and after scanning again
    /// if it had to quit: what it wrote until then was not there when the page scanned.
    private func requestRemoval() {
        let plan = plan
        let running = plan.runningProcesses
        quitting.check(running) {
            Task {
                if !running.isEmpty {
                    await rescan()
                    guard !plan.scanRun.wasStopped else { return }
                }
                plan.question.ask(plan.request)
            }
        }
    }

    /// Quitting the app before removing it, or only its files when it stays.
    private var quitTitle: Text {
        plan.selectedURLs.contains(plan.app.url)
            ? Text("Quit \(plan.app.name) before removing it.")
            : Text("Quit \(plan.app.name) before removing its files.")
    }

    /// One removal, from the privacy reset before the move to the scan after it, with the page busy throughout.
    /// An app opened since the question moves nothing: it is asked to quit again.
    private func remove(_ request: RemovalRequest) async {
        let plan = plan
        defer { plan.question.finish() }
        guard plan.runningProcesses.isEmpty else { return requestRemoval() }
        let result = await progress.run(toMove: request.urls.count) {
            await QuitGuard.shared.run {
                // The one step that goes before the move: `tccutil` only finds an app that is still in its place.
                let service = TrashService(exclusions: ExclusionsStore.shared.exclusions)
                let privacy = await PrivacyReset.reset(resetting(request.urls), beforeMovingWith: service)
                let result = await plan.move(request)
                let keptItsFiles = plan.uninstallation?.keptItsFiles(after: result, selection: request.urls) == true
                outcome.report(result, privacy: privacy, keptTheirFiles: keptItsFiles ? [plan.app.name] : [])
                if removesDockTile, result.trashed.contains(where: { $0.originalURL == plan.app.url }) {
                    _ = await DockTiles().takeOut([plan.app.url])
                }
                if let state = AppManagement.state(
                    after: result,
                    appBundles: [plan.app.url],
                    movedByTheHelper: plan.privilegedURLs
                ) {
                    home.record(appManagement: state)
                }
                await history.record(result, tool: .applications, source: plan.app.name, sizes: request.sizes)
                return result
            }
        }

        if result.trashed.contains(where: { $0.originalURL == plan.app.url }) {
            await library.checkAgain(await library.refresh())
        } else {
            await plan.refresh(
                installedApps: library.apps,
                canUseHelper: helper.canAct,
                casks: homebrew.caskEvidence,
                receipts: homebrew.receipts
            )
        }
    }
}
