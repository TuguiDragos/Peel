import PeelCore
import SwiftUI

struct MultipleAppsView: View {
    @Environment(AppLibrary.self) private var library
    @Environment(HelperModel.self) private var helper
    @Environment(HomeModel.self) private var home
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(HomebrewLibrary.self) private var homebrew
    @State private var plan: BulkRemovalPlan
    @State private var quitting = QuitBeforeRemoving()
    @State private var resetsPrivacy = false
    @State private var removesDockTiles = true
    @State private var appsInTheDock: Set<URL> = []
    @State private var isRescanning = false
    @State private var questionTitle = Text(verbatim: "")
    @State private var questionNote = Text(verbatim: "")
    @Environment(RemovalOutcome.self) private var outcome

    init(apps: [InstalledApp]) {
        _plan = State(initialValue: BulkRemovalPlan(apps: apps))
    }

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)
            RemovalsHeldBanner()

            if plan.bulk != nil {
                if plan.bulk?.needsFullDiskAccess == true {
                    FullDiskAccessBanner()
                } else if !plan.unreadableLocations.isEmpty {
                    UnreadableFoldersNotice(folders: plan.unreadableLocations.map(\.url))
                }
                if plan.requiresHelper, !helper.canAct {
                    HelperRequiredBanner()
                }

                Section {
                    RemovalColumnHeaders()
                    ForEach(Array(plan.applications.enumerated()), id: \.element.id) { index, item in
                        row(item, isFirst: index == 0)
                    }
                    .listRowSeparator(.hidden)
                } header: {
                    SectionHeaderLine {
                        Text("Apps")
                    } actions: {
                        SelectMenu(list: list(of: plan.applications), place: Text("Apps"), selection: plan)
                    }
                }

                if !plan.recommendedFiles.isEmpty {
                    Section {
                        RemovalColumnHeaders()
                        ForEach(Array(plan.recommendedFiles.enumerated()), id: \.element.id) { index, item in
                            row(item, isFirst: index == 0)
                        }
                        .listRowSeparator(.hidden)
                    } header: {
                        SectionHeaderLine {
                            Text("Files They Leave Behind")
                        } actions: {
                            SelectMenu(
                                list: list(of: plan.recommendedFiles),
                                place: Text("Files They Leave Behind"),
                                selection: plan
                            )
                        }
                    }
                }

                if !plan.filesToReview.isEmpty {
                    Section {
                        RemovalColumnHeaders()
                        ForEach(Array(plan.filesToReview.enumerated()), id: \.element.id) { index, item in
                            row(item, isFirst: index == 0)
                        }
                        .listRowSeparator(.hidden)
                    } header: {
                        SectionHeaderLine {
                            heading(
                                "Review Before Removing",
                                "These are here because Peel is less sure about them, another app on this Mac uses them too, or Peel held them back for the reason each row gives. Nothing here is selected for you: read each one and select only what you recognize."
                            )
                        } actions: {
                            SelectMenu(
                                list: list(of: plan.filesToReview),
                                place: Text("Review Before Removing"),
                                selection: plan
                            )
                        }
                    }
                }

                if plan.apps.contains(where: {
                    PrivacyReset.isAllowed(bundleIdentifier: $0.bundleIdentifier)
                        && !plan.appsInTheTrash.contains($0.url)
                }) {
                    PrivacyResetRow(isOn: $resetsPrivacy, detail: PrivacyResetRow.beforeTheMove)
                }
                if !appsInTheDock.isEmpty {
                    DockTileRow(isOn: $removesDockTiles)
                }
            }
        }
        .scrollBarBelowSectionHeaders()
        .dimmedWhileBusy(plan.isRemoving)
        .disabled(plan.isRemoving)
        .scanState(phase, isRescanning: isRescanning, fadesInResults: false, scan: plan.scanRun)
        .edgeBar(.bottom) {
            if plan.bulk != nil {
                let selected = plan.request.total
                RemovalBar(
                    selectedSize: selected.known,
                    isSelectionMeasured: selected.isComplete,
                    isScanning: plan.isScanning,
                    scan: plan.scanRun,
                    isEnabled: !plan.selectedURLs.isEmpty && !plan.isRemoving && !quitting.isWaiting,
                    onRemove: requestRemoval
                )
            }
        }
        .navigationTitle(Text("^[\(plan.apps.count) app](inflect: true)"))
        .toolbar(removing: .title)
        // Like an app's own page, this page has Rescan, which turns into Stop while a scan runs: scanning
        // several apps can take a while.
        .toolbar {
            ToolbarItem {
                RescanButton(isRunning: $isRescanning, isDisabled: plan.isRemoving, scan: plan.scanRun) {
                    await plan.refresh(
                        installedApps: library.apps,
                        canUseHelper: helper.canAct,
                        casks: homebrew.caskEvidence,
                        receipts: homebrew.receipts
                    )
                }
            }
        }
        .confirmationDialog(questionTitle, isPresented: Bindable(plan.question).isAsking) {
            Button("Move to Trash") {
                guard let request = plan.question.start() else { return }
                Task { await remove(request) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            questionNote
        }
        .alert("Quit these apps before removing them.", isPresented: Bindable(quitting).isAsking) {
            Button("Quit Apps") { quitting.quit() }
            Button("Cancel", role: .cancel) { quitting.giveUp() }
        } message: {
            Text(verbatim: quitting.names)
        }
        .forceQuitOffer(quitting)
        .onDisappear { quitting.giveUp() }
        .task {
            // Selecting apps one by one rebuilds this page after each change, and each build scans every selected
            // app. The short wait lets the selection settle: a newer change cancels this task before it scans.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, !(plan.bulk == nil && plan.scanRun.wasStopped) else { return }
            await rescan()
        }
        .task(id: plan.apps.map(\.url)) {
            appsInTheDock = await DockTiles().holding(plan.apps.map(\.url))
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

    /// A scan asked for while the question is up or a removal runs waits for them.
    private func rescan() async {
        guard plan.question.mayScan() else { return }
        await plan.refresh(
            installedApps: library.apps,
            canUseHelper: helper.canAct,
            casks: homebrew.caskEvidence,
            receipts: homebrew.receipts
        )
    }

    private var phase: ScanPhase {
        if plan.bulk != nil { return .content }
        return plan.scanRun.wasStopped ? .stopped : .scanning(.walk)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            AppStack(apps: plan.apps)
            VStack(alignment: .leading, spacing: 6) {
                Text("^[\(plan.apps.count) app](inflect: true)")
                    .pageHeading()
                Text(verbatim: plan.apps.map(\.name).formatted(.list(type: .and)))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if plan.bulk != nil {
                    Badge(title: Text("^[\(plan.items.count) item](inflect: true)"), systemImage: "doc.on.doc")
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            if plan.total.known > 0 || !plan.total.isComplete {
                TotalLabel(total: plan.total, caption: Text("to remove"))
                    .accessibilityLabel(Text("\(plan.total.text) can be moved to the Trash"))
            }
        }
        .padding(.vertical, 8)
    }

    private func list(of items: [BulkUninstallation.Item]) -> SelectableRows<URL> {
        let rows = items.map(\.url)
        return SelectableRows(
            rows: rows,
            selectable: rows.filter(plan.selectable.contains),
            recommended: rows.filter(plan.suggested.contains),
            leftToTheClick: items.filter(\.isLeftToTheClick).map(\.url)
        )
    }

    private func row(_ item: BulkUninstallation.Item, isFirst: Bool) -> some View {
        RemovalRow(
            url: item.url,
            icon: item.isApplication ? .file(item.url) : .symbol(item.kind?.symbolName ?? "doc"),
            detail: item.isApplication ? nil : item.match?.reason.title,
            kind: item.isApplication ? "Application" : item.kind?.title,
            warning: warning(for: item),
            foundFor: item.isApplication ? nil : names(of: item.apps),
            size: item.size,
            isMeasured: item.isMeasured,
            isLocked: item.requiresPrivileges && !helper.canAct,
            isExcluded: item.isApplication && item.isExcluded,
            isLeftAlone: item.match?.heldBack?.cannotBeMoved == true || item.isBeyondTheHelper
                || (item.isApplication && item.isKeptByMacOS)
                || item.isPeels || item.isInTheTrash || item.enclosingPackage != nil,
            appIdentifier: item.isApplication ? item.apps.first : nil,
            isFirst: isFirst,
            selection: plan, isSelected: plan.isSelected(item.url)
        )
    }

    /// The names of the apps with these bundle identifiers, as a list.
    private func names(of identifiers: [String]) -> String {
        identifiers.map(library.name(forBundleIdentifier:)).formatted(.list(type: .and))
    }

    /// The warning in a row's note, in the same words an app's own page uses: which other apps use the item,
    /// and why Peel did not select it or leaves it where it is.
    private func warning(for item: BulkUninstallation.Item) -> String? {
        var lines: [String] = []
        let keptBy = item.apps.filter(plan.staying.contains)
        if !item.isApplication, !keptBy.isEmpty, !item.isKeptByMacOS, !item.isPeels, !item.isExcluded {
            lines.append(String(localized: "Not selected: it stays with \(names(of: keptBy))."))
        }
        let users =
            item.sharedWithOthers.map(library.name(forBundleIdentifier:)) + item.otherCopies.map(\.abbreviatedPath)
        if !users.isEmpty {
            lines.append(String(localized: "Also used by \(users.formatted(.list(type: .and)))"))
        }
        if let heldBack = item.match?.heldBack {
            lines.append(String(localized: heldBack.explanation))
        }
        if item.holdsDamagedSettings {
            lines.append(String(localized: "Can’t be read as a property list, so nothing can read these settings."))
        }
        if item.isApplication, item.isBeyondTheHelper {
            lines.append(String(localized: HoldBack.beyondTheHelper.explanation))
        }
        if item.isPeels {
            lines.append(String(localized: "Left alone: Peel removes itself only from Settings."))
        }
        if item.isInTheTrash {
            lines.append(String(localized: "Already in the Trash. What it left behind can still go."))
        }
        if let package = item.enclosingPackage {
            let name = AppInspector.displayName(of: package)
            lines.append(String(localized: "Part of \(name), so it stays where it is."))
        }
        if item.isKeptByMacOS {
            // Two literals, so the string catalog finds both.
            lines.append(item.isApplication
                ? String(localized: "macOS keeps this app, so it stays where it is.")
                : String(localized: "Not selected: it belongs to an app macOS keeps, so it is in use."))
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }

    /// Under the question: which of the chosen apps go and which stay, and the privacy reset, which History can't undo.
    private func note(about urls: Set<URL>) -> Text {
        let going = plan.apps.filter { urls.contains($0.url) }
        let staying = plan.apps.filter { !urls.contains($0.url) && !plan.appsInTheTrash.contains($0.url) }
        var lines: [Text] = []
        if !going.isEmpty {
            lines.append(Text("Apps that go: \(list(going))"))
        }
        if !staying.isEmpty {
            lines.append(Text("Apps that stay: \(list(staying))"))
        }
        if !resetting(urls).isEmpty {
            lines.append(Text("The selected apps’ privacy permissions are cleared first, and History can’t bring them back."))
        }
        lines += UninstallsItself.when(moving: urls, among: plan.apps).map(\.warning)
        return lines.dropFirst().reduce(lines.first ?? Text(verbatim: "")) { Text("\($0)\n\n\($1)") }
    }

    /// These chosen apps as a list: each by its name, or by where it is when another chosen app has the same name.
    private func list(_ apps: [InstalledApp]) -> String {
        apps.map { app in
            plan.apps.contains { $0.name == app.name && $0.url != app.url } ? app.url.abbreviatedPath : app.name
        }.formatted(.list(type: .and))
    }

    /// The apps whose privacy permissions a removal of `urls` resets.
    private func resetting(_ urls: Set<URL>) -> [InstalledApp] {
        resetsPrivacy ? PrivacyReset.apps(among: plan.apps, moving: urls) : []
    }

    /// Asks the question once the apps have quit, since none of their files moves while they run. Its words are
    /// worked out here, once, rather than with every change of the page: the note compares every chosen app with
    /// every other.
    private func requestRemoval() {
        let plan = plan
        quitting.check(plan.runningProcesses) {
            let request = plan.request
            questionTitle = Text.movingToTrash(request.urls.count, request.total)
            questionNote = note(about: request.urls)
            plan.question.ask(request)
        }
    }

    /// One removal, from the privacy reset before the move to the scan after it, with the page busy throughout.
    /// An app opened since the question moves nothing: it is asked to quit again.
    private func remove(_ request: RemovalRequest) async {
        let plan = plan
        defer { plan.question.finish() }
        guard plan.runningProcesses.isEmpty else { return requestRemoval() }
        let result = await QuitGuard.shared.run {
            // The privacy reset runs before the move, because `tccutil` only finds an app that is still in its place.
            let privacy = await PrivacyReset.reset(resetting(request.urls))
            let result = await plan.move(request)
            outcome.report(result, privacy: privacy)
            if removesDockTiles {
                let moved = Set(result.trashed.map(\.originalURL))
                _ = await DockTiles().takeOut(appsInTheDock.filter(moved.contains).sorted { $0.path < $1.path })
            }
            if let state = AppManagement.state(
                after: result,
                appBundles: Set(plan.apps.map(\.url)),
                movedByTheHelper: plan.privilegedURLs
            ) {
                home.record(appManagement: state)
            }
            await history.record(
                result,
                tool: .applications,
                source: plan.historySource,
                sourceKey: plan.historySourceKey,
                sizes: request.sizes
            )
            return result
        }
        // When an app bundle moved, reloading the library changes the selection, which rebuilds this page. When
        // only files moved, the plan is refreshed here: otherwise they would stay listed, and moving them again
        // would fail for each one.
        let bundles = Set(plan.apps.map(\.url))
        if result.trashed.contains(where: { bundles.contains($0.originalURL) }) {
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

/// The icons of the first three chosen apps, stacked with small offsets.
private struct AppStack: View {
    let apps: [InstalledApp]

    var body: some View {
        ZStack {
            ForEach(Array(apps.prefix(3).enumerated()).reversed(), id: \.offset) { index, app in
                AppIcon(url: app.url)
                    .frame(width: 58, height: 58)
                    .offset(x: [0, 9, -10][index], y: [0, -4, 6][index])
                    .zIndex(Double(3 - index))
            }
        }
        .frame(width: 86, height: 76)
        .accessibilityHidden(true)
    }
}
