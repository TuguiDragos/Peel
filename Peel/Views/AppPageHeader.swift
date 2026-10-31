import PeelCore
import SwiftUI

/// The head of an app's page: the app, its update, and what can be done to it without removing it. A view of its
/// own because what it shows of the update is read from dictionaries every app's check writes into: read in the
/// page's body, any app's answer would build the whole page again.
struct AppPageHeader: View {
    @Environment(AppLibrary.self) private var library
    @Environment(HomebrewLibrary.self) private var homebrew
    @Environment(\.notifications) private var notifications
    @Environment(HelperModel.self) private var helper
    @Environment(RemovalHistoryStore.self) private var history
    let plan: RemovalPlan
    let privacyReset: PrivacyReset.Result?
    @Binding var isShowingReset: Bool
    @Binding var isConfirmingPrivacyReset: Bool
    @Binding var upgradeOutput: HomebrewLibrary.CommandResult?
    @Binding var receiptToForget: PackageReceipt?
    let isForgettingReceipt: Bool
    /// True while the page removes the app or waits for it to quit first, when nothing else is started from here.
    let isRemoving: Bool
    /// Asks the app to quit before Homebrew upgrades it. The page owns it and shows its questions, since a List
    /// takes this header away when it is scrolled out of view, and that would end the wait.
    let quittingToUpgrade: QuitBeforeRemoving

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AppHeader(
                app: plan.app,
                updateStatus: library.shownUpdateStatus(of: plan.app),
                isCheckingForUpdates: library.appsCheckingForUpdates.contains(plan.app.id),
                hasWaitingUpdate: waitingVersion != nil,
                lastCheck: library.lastUpdateChecks[plan.app.id],
                cannotCheck: library.whyItCannotCheck(plan.app),
                total: plan.total,
                sharesStorage: plan.appSharesStorage
            ) {
                appActions
            }
            updatePanel
        }
        .padding(.bottom, 8)
    }

    /// The version an update would bring. Nil when there is no update, or when the user muted this app or
    /// this version.
    private var waitingVersion: String? {
        library.hasUpdate(plan.app) ? library.updateStatuses[plan.app.id]?.version : nil
    }

    /// What can be done to the app without removing it, its update aside: open its maker's uninstaller, or reset
    /// it. Less common actions, such as the release notes or muting updates, sit in the More menu.
    private var appActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout {
                if let uninstaller = plan.vendorUninstaller {
                    Button("Open Uninstaller", systemImage: "arrow.up.forward.app") {
                        NSWorkspace.shared.open(uninstaller)
                    }
                    .buttonStyle(.bordered)
                    .disabled(plan.isExcluded)
                    .help(plan.isExcluded ? Text(.excludedApp) : Text("Run the maker’s uninstaller first: it knows what Peel can only guess at."))
                }
                // Not on Peel's own page, where the sheet could only offer to quit Peel, nor for an app in the Trash,
                // which no longer stays installed: its page offers its files.
                if plan.app.bundleIdentifier != Bundle.main.bundleIdentifier, !library.isInATrash(plan.app) {
                    Button("Reset\u{2026}") { isShowingReset = true }
                        .buttonStyle(.bordered)
                        .disabled(plan.isExcluded)
                        .help(plan.isExcluded ? Text(.excludedApp) : Text("Make \(plan.app.name) forget its settings without uninstalling it"))
                }
                moreMenu
            }
            .disabled(isRemoving)
            // An upgrade that brought the app up to date leaves no panel to say how it went.
            if waitingVersion == nil, let upgrade = library.upgrade(of: plan.app) {
                outcome(of: upgrade)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let privacyReset {
                outcome(of: privacyReset)
            }
        }
    }

    /// The update that waits, how to get it, and what is new in it. The store's page is already the App Store button,
    /// and a cask's homepage is offered as what it is.
    @ViewBuilder
    private var updatePanel: some View {
        if let version = waitingVersion, let status = library.updateStatuses[plan.app.id],
           let source = status.source, let shown = status.displayVersion {
            UpdatePanel(
                version: shown,
                notes: library.releaseNotes(of: plan.app),
                link: source == .appStore ? nil : status.releaseNotes.map {
                    ReleaseNotesLink(url: $0, title: source == .homebrew ? "Homepage" : "Release Notes")
                }
            ) {
                if let upgrade = library.upgrade(of: plan.app) {
                    outcome(of: upgrade)
                } else {
                    Text(updateExplanation(for: source))
                }
            } action: {
                updateAction(for: source, version: version)
                    .disabled(isRemoving)
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            if waitingVersion != nil, let status = library.updateStatuses[plan.app.id], status.source != .appStore,
               let notes = status.releaseNotes {
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
            if PrivacyReset.isAllowed(for: plan.app), !library.isInATrash(plan.app) {
                Divider()
                Button("Reset Privacy Permissions\u{2026}") { isConfirmingPrivacyReset = true }
                    .disabled(!plan.mayResetPrivacy)
            }
            forgetReceiptItems
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

    /// Forgetting a receipt changes what macOS and installers know of the package, which is no common step for an app
    /// the person keeps, so it waits in this menu rather than beside each receipt.
    @ViewBuilder
    private var forgetReceiptItems: some View {
        let receipts = plan.packageReceipts
        // The page promises that an excluded app's files are left alone, its receipt included.
        let mayForget = !isForgettingReceipt && helper.canAct && !plan.isExcluded && history.mayMove
        if let only = receipts.first, receipts.count == 1 {
            Divider()
            Button("Forget Receipt\u{2026}") { receiptToForget = only }
                .disabled(!mayForget)
        } else if !receipts.isEmpty {
            Divider()
            Menu("Forget Receipt") {
                ForEach(receipts) { receipt in
                    Button(receipt.identifier) { receiptToForget = receipt }
                }
            }
            .disabled(!mayForget)
        }
    }

    private func updateExplanation(for source: UpdateSource) -> LocalizedStringResource {
        switch source {
        case .appStore: "The App Store has it. Update from the App Store."
        case .homebrew where library.cask(for: plan.app)?.upgradeNeedsAnAdministrator == true:
            "Homebrew needs an administrator’s password for this, and only Terminal can ask for it. Copy the command, then run it in Terminal."
        case .homebrew where homebrew.overrides.contains(.cleansUp):
            HomebrewLibrary.cleansUp
        case .homebrew: "Homebrew has it. Peel can run the upgrade for you."
        case .developer, .automatic: "The maker has it. Update from inside the app."
        }
    }

    /// Whether the cask's upgrade is left to Terminal: it asks for an administrator's password, which only Terminal
    /// can give, or Homebrew would clean up after it.
    private var upgradeNeedsTerminal: Bool {
        library.cask(for: plan.app)?.upgradeNeedsAnAdministrator == true || homebrew.overrides.contains(.cleansUp)
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
        case .homebrew where upgradeNeedsTerminal:
            if let cask = library.cask(for: plan.app) {
                CopyButton(
                    text: Homebrew.terminalCommand(
                        "brew upgrade --cask \(cask.fullName)", keeping: homebrew.keptFormulaeNow
                    ),
                    title: "Copy Upgrade Command"
                )
            }
        case .homebrew:
            Button {
                upgradeWithHomebrew()
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
            .disabled(homebrew.runningCommand != nil || quittingToUpgrade.isWaiting)
        case .developer, .automatic:
            Button("Open \(plan.app.name)", systemImage: "arrow.up.forward.app") {
                NSWorkspace.shared.open(plan.app.url)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var isUpgrading: Bool {
        guard let cask = library.cask(for: plan.app) else { return false }
        return homebrew.runningCommand == .upgrade(cask.id)
    }

    private func upgradeWithHomebrew() {
        guard let cask = library.cask(for: plan.app) else { return }
        let quit = QuitBeforeHomebrew([cask], library: library)
        quittingToUpgrade.check(quit.processes) {
            Task {
                await upgrade(cask)
                quit.reopen()
            }
        }
    }

    /// Upgrades the app with Homebrew, which can take a while. The button shows progress while it runs, the
    /// line under it shows the result, and a notification reports it too, in case the user has moved on.
    private func upgrade(_ cask: HomebrewPackage) async {
        let app = plan.app
        library.record(nil, of: app)
        // Nil when Homebrew is already running a command. The button is disabled then, so this is only a safeguard.
        guard let result = await homebrew.run(.upgrade(cask.id), showsResult: false) else { return }
        let succeeded = result.succeeded
        upgradeOutput = succeeded ? nil : result

        // Homebrew's own answer is read again first: it is what says whether a version is behind, and the copy from
        // before the upgrade still said this one was. A new build gets a page of its own, which scans it.
        await library.refresh()
        library.loadHomebrewCasks(homebrew.caskEvidence, knowsItsOwnApps: homebrew.knowsItsOwnApps)
        let upgraded = library.apps.first { $0.id == app.id } ?? app
        library.record(AppLibrary.Upgrade(app: upgraded, succeeded: succeeded), of: upgraded)
        await library.checkForUpdates([upgraded], force: true)

        // A notification either way, so the user learns how it went even after leaving the page.
        if succeeded {
            notifications?.notify(appUpgraded: upgraded.name, to: upgraded.version, app: upgraded.url)
        } else {
            notifications?.notify(appUpgradeFailed: upgraded.name, app: upgraded.url)
        }
    }

    @ViewBuilder
    private func outcome(of upgrade: AppLibrary.Upgrade) -> some View {
        if upgrade.succeeded {
            StatusLabel(
                title: upgrade.app.version.map { Text("Now on \($0).") } ?? Text("Homebrew finished the upgrade."),
                systemImage: "checkmark.circle.fill",
                tint: .green
            )
        } else {
            StatusLabel(
                title: Text("Homebrew couldn’t finish the upgrade."),
                systemImage: "exclamationmark.triangle.fill",
                tint: .red
            )
        }
    }

    @ViewBuilder
    private func outcome(of privacyReset: PrivacyReset.Result) -> some View {
        Group {
            if let problem = privacyReset.explanation {
                StatusLabel(
                    title: Text("Privacy permissions weren’t reset. \(problem)"),
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .red
                )
            } else {
                StatusLabel(
                    title: Text("Privacy permissions were reset. \(plan.app.name) asks you again the next time it needs them."),
                    systemImage: "checkmark.circle.fill",
                    tint: .green
                )
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
