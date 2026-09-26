import PeelCore
import SwiftUI

struct MultipleAppsView: View {
    @Environment(AppLibrary.self) private var library
    @Environment(HelperModel.self) private var helper
    @Environment(HomeModel.self) private var home
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(HomebrewLibrary.self) private var homebrew
    @State private var plan: BulkRemovalPlan
    @State private var isShowingQuitAlert = false
    @State private var resetsPrivacy = false
    @State private var isRescanning = false
    @Environment(RemovalOutcome.self) private var outcome

    init(apps: [InstalledApp]) {
        _plan = State(initialValue: BulkRemovalPlan(apps: apps))
    }

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)
            ExclusionsUnreadableBanner()

            if plan.bulk != nil {
                if !plan.unreadableLocations.isEmpty {
                    FullDiskAccessBanner()
                }
                if plan.requiresHelper, !helper.canAct {
                    HelperRequiredBanner()
                }

                Section {
                    ForEach(Array(applications.enumerated()), id: \.element.id) { index, item in
                        row(item, isFirst: index == 0)
                    }
                    .listRowSeparator(.hidden)
                } header: {
                    Text("Apps")
                }

                if !files.isEmpty {
                    Section {
                        ForEach(Array(files.enumerated()), id: \.element.id) { index, item in
                            row(item, isFirst: index == 0)
                        }
                        .listRowSeparator(.hidden)
                    } header: {
                        Text("Files They Leave Behind")
                    }
                }

                if plan.apps.contains(where: { PrivacyReset.isAllowed(bundleIdentifier: $0.bundleIdentifier) }) {
                    PrivacyResetRow(isOn: $resetsPrivacy, detail: PrivacyResetRow.beforeTheMove)
                }
            }
        }
        .disabled(plan.isRemoving)
        .scanState(phase, isRescanning: isRescanning || plan.isRemoving, fadesInResults: false, scan: plan.scanRun)
        .safeAreaBar(edge: .bottom) {
            if plan.bulk != nil {
                let selected = plan.request.total
                RemovalBar(
                    selectedSize: selected.known,
                    isSelectionMeasured: selected.isComplete,
                    isScanning: plan.isScanning,
                    scan: plan.scanRun,
                    isEnabled: !plan.selectedURLs.isEmpty && !plan.isRemoving && !plan.isScanning,
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
                    await plan.refresh(installedApps: library.apps, canUseHelper: helper.canAct, casks: homebrew.caskEvidence, receipts: homebrew.receipts)
                }
            }
        }
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
            if !resetting(plan.question.request?.urls ?? []).isEmpty {
                Text("The selected apps’ privacy permissions are cleared first, and History can’t bring them back.")
            }
        }
        .alert("Quit these apps before removing them.", isPresented: $isShowingQuitAlert) {
            Button("Quit Apps") { plan.quitRunningApps() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: plan.runningApps.map(\.name).formatted(.list(type: .and)))
        }
        .task {
            // Selecting apps one by one rebuilds this page after each change, and each build scans every selected
            // app. The short wait lets the selection settle: a newer change cancels this task before it scans.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, !(plan.bulk == nil && plan.scanRun.wasStopped) else { return }
            await rescan()
        }
        .rescanOnExclusionChange("MultipleAppsView") { await rescan() }
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
        await plan.refresh(installedApps: library.apps, canUseHelper: helper.canAct, casks: homebrew.caskEvidence, receipts: homebrew.receipts)
    }

    private var phase: ScanPhase {
        if plan.bulk != nil { return .content }
        return plan.scanRun.wasStopped ? .stopped : .scanning(.walk)
    }

    private var applications: [BulkUninstallation.Item] {
        plan.items.filter(\.isApplication)
    }

    private var files: [BulkUninstallation.Item] {
        plan.items.filter { !$0.isApplication }
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
                Badge(title: Text("^[\(plan.items.count) item](inflect: true)"), systemImage: "doc.on.doc")
                    .padding(.top, 2)
            }
            Spacer(minLength: 8)
            if plan.total.known > 0 || !plan.total.isComplete {
                TotalLabel(total: plan.total, caption: Text("to remove"))
                    .accessibilityLabel(Text("\(plan.total.text) can be moved to the Trash"))
            }
        }
        .padding(.vertical, 8)
    }

    private func row(_ item: BulkUninstallation.Item, isFirst: Bool) -> some View {
        RemovalRow(
            url: item.url,
            icon: item.isApplication ? .file(item.url) : .symbol(item.kind?.symbolName ?? "doc"),
            detail: item.isApplication ? "Application" : item.match?.reason.title,
            warning: warning(for: item),
            size: item.size,
            isMeasured: item.isMeasured,
            isLocked: item.requiresPrivileges && !helper.canAct,
            isExcluded: item.isExcluded,
            isLeftAlone: item.match?.heldBack?.cannotBeMoved == true || item.isBeyondTheHelper || (item.isApplication && item.isKeptByMacOS)
                || item.isPeels,
            appIdentifier: item.isApplication ? item.apps.first : nil,
            isFirst: isFirst,
            selection: plan, isSelected: plan.isSelected(item.url)
        )
    }

    /// The warning in a row's note, in the same words an app's own page uses: which other apps use the item,
    /// and why Peel did not select it or leaves it where it is.
    private func warning(for item: BulkUninstallation.Item) -> String? {
        var lines: [String] = []
        if !item.sharedWithOthers.isEmpty {
            let names = item.sharedWithOthers.map(library.name(forBundleIdentifier:)).formatted(.list(type: .and))
            lines.append(String(localized: "Also used by \(names)"))
        }
        if let heldBack = item.match?.heldBack {
            lines.append(String(localized: heldBack.explanation))
        }
        if item.isApplication, item.isBeyondTheHelper {
            lines.append(String(localized: HoldBack.beyondTheHelper.explanation))
        }
        if item.isPeels {
            lines.append(String(localized: "Left alone: Peel removes itself only from Settings."))
        }
        if item.isKeptByMacOS {
            // Two literals, so the string catalog finds both.
            lines.append(item.isApplication
                ? String(localized: "macOS keeps this app, so it stays where it is.")
                : String(localized: "Not selected: it belongs to an app macOS keeps, so it is in use."))
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }

    /// The apps whose privacy permissions a removal of `urls` resets.
    private func resetting(_ urls: Set<URL>) -> [InstalledApp] {
        resetsPrivacy ? PrivacyReset.apps(among: plan.apps, moving: urls) : []
    }

    private func requestRemoval() {
        if !plan.runningApps.isEmpty {
            isShowingQuitAlert = true
        } else {
            plan.question.ask(plan.request)
        }
    }

    /// One removal, from the privacy reset before the move to the scan after it, with the page busy throughout.
    private func remove(_ request: RemovalRequest) async {
        let plan = plan
        defer { plan.question.finish() }
        // The privacy reset runs before the move, because `tccutil` only finds an app that is still in its place.
        let privacy = await PrivacyReset.reset(resetting(request.urls))
        let result = await plan.move(request)
        outcome.report(result, privacy: privacy)
        if let state = AppManagement.state(after: result, appBundles: Set(plan.apps.map(\.url)), movedByTheHelper: plan.privilegedURLs) {
            home.record(appManagement: state)
        }
        await history.record(result, tool: .applications, source: plan.historySource, sourceKey: plan.historySourceKey, sizes: request.sizes)
        // When an app bundle moved, reloading the library changes the selection, which rebuilds this page. When
        // only files moved, the plan is refreshed here: otherwise they would stay listed, and moving them again
        // would fail for each one.
        let bundles = Set(plan.apps.map(\.url))
        if result.trashed.contains(where: { bundles.contains($0.originalURL) }) {
            await library.load()
        } else {
            await plan.refresh(installedApps: library.apps, canUseHelper: helper.canAct, casks: homebrew.caskEvidence, receipts: homebrew.receipts)
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
