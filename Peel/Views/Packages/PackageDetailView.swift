import AppKit
import PeelCore
import SwiftUI

struct PackageDetailView: View {
    @Environment(PackageLibrary.self) private var packages
    @Environment(HelperModel.self) private var helper
    @Environment(RemovalHistoryStore.self) private var history
    @State private var isConfirmingRemoval = false
    @State private var receiptToForget: PackageReceipt?
    /// The receipt to ask about once the removal's alert closes, since two questions can't show at once.
    @State private var forgetOnceTheAlertCloses: PackageReceipt?
    @Environment(RemovalOutcome.self) private var outcome
    @Environment(AppLibrary.self) private var library
    @Environment(\.openSettings) private var openSettings
    @State private var quitting = QuitBeforeRemoving()
    let receipt: PackageReceipt

    /// What runs from `apps` and is asked to quit before they move, each once, by the rule an app's own page follows.
    static func toQuit(
        _ apps: [InstalledApp], among running: [RunningCopies.Process], installedApps: [InstalledApp]
    ) async -> [RunningCopies.Process] {
        var asked: [RunningCopies.Process] = []
        for app in apps {
            let processes = await RunningCopies.toQuit(beforeMoving: app, among: running, installedApps: installedApps)
            asked += processes.filter { process in !asked.contains { $0.identifier == process.identifier } }
        }
        return asked
    }

    private func moveSelection() async {
        let sizes = [URL: Int64](measured: receipt.items.map { ($0.url, $0.size) })
        let (result, stayed) = await history.moving(tool: .packages, source: receipt.identifier, sizes: sizes) {
            await packages.removeSelectedItems { result in
                await history.record(
                    result,
                    tool: .packages,
                    source: receipt.identifier,
                    sizes: sizes
                )
            }
        }
        outcome.report(result, dockIcons: RemovalOutcome.DockIcons(stayed) { url in
            receipt.apps.first { $0.url == url }?.name ?? url.deletingPathExtension().lastPathComponent
        })
        guard let left = Self.toForgetNext(
            packages.selectedReceipt, after: receipt,
            mayForget: !forgettingWaitsForTheHelper && history.mayMove && !isForAnExcludedApp
        ) else { return }
        if outcome.isEmpty {
            receiptToForget = left
        } else {
            forgetOnceTheAlertCloses = left
        }
    }

    /// The receipt to ask about forgetting once a move on `receipt`'s page left nothing of it on the disk, since then
    /// forgetting it is all there is left to do.
    static func toForgetNext(
        _ left: PackageReceipt?, after receipt: PackageReceipt, mayForget: Bool
    ) -> PackageReceipt? {
        guard mayForget, let left, left.id == receipt.id, left.nothingLeftOnDisk else { return nil }
        return left
    }

    var body: some View {
        let isOnlyToRead = Self.isOnlyToRead(receipt, canUseHelper: helper.canAct)
        return List {
            header
                .listRowSeparator(.hidden)
            RemovalsHeldBanner()

            if let uninstaller = receipt.makersUninstaller {
                MakersUninstallerNotice(
                    app: receipt.name ?? receipt.identifier, uninstaller: uninstaller, isForWhatIsLeft: true
                )
                .listRowSeparator(.hidden)
            }

            if isForAnExcludedApp {
                Notice(
                    title: Text("An app it installed is excluded"),
                    detail: Text("The app this package installed is excluded in Settings, so Peel leaves its receipt alone too."),
                    kind: .note
                ) {
                    Button("Open Peel Settings") { SettingsPane.exclusions.open(with: openSettings) }
                }
                .listRowSeparator(.hidden)
            }

            // Forget Receipt needs the helper for a disk's receipt, whatever the items need, unless the exclusions
            // leave it alone.
            if !helper.canAct {
                if receipt.itemsWaitingForTheHelper > 0 {
                    HelperRequiredBanner(need: .moving(receipt.itemsWaitingForTheHelper))
                } else if forgettingWaitsForTheHelper, !isForAnExcludedApp {
                    HelperRequiredBanner(need: .forgettingThisReceipt)
                }
            }
            let forAnAdministrator = receipt.itemsLeftForAnAdministrator
            if !forAnAdministrator.isEmpty {
                Notice(
                    title: Text("Needs an Administrator"),
                    detail: nil,
                    kind: .note,
                    systemImage: "lock.shield",
                    step: Text(AdministratorItemsView.howToRemove)
                ) {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(forAnAdministrator.map(\.url))
                    }
                }
                .listRowSeparator(.hidden)
            }

            if isOnlyToRead {
                FoundOnThisMacSection(count: receipt.items.count, size: SizeTotal(receipt.items.map(\.size))) {
                    rows(isReadOnly: true)
                }
            } else {
                Section {
                    if receipt.items.isEmpty {
                        Text(emptyListReason)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                    }
                    rows(isReadOnly: false)
                } header: {
                    SectionHeaderLine {
                        Text("Installed Items")
                    } actions: {
                        SelectMenu(list: list, place: Text(verbatim: receipt.identifier), selection: packages)
                    }
                }
            }

            Section {
            } header: {
                HeadingWithActions {
                    heading(
                        "Installer Receipt",
                        "Forgetting it moves the receipt to the Trash, so macOS no longer counts the package as installed. What it installed stays where it is."
                    )
                } actions: {
                    Button("Forget Receipt") {
                        receiptToForget = receipt
                    }
                    .disabled(forgettingWaitsForTheHelper || !history.mayMove || isForAnExcludedApp)
                    .help(forgetHelp)
                }
            }
        }
        .scrollBarBelowSectionHeaders()
        .disabled(packages.isWorking)
        .dimmedWhileBusy(packages.isScanning)
        .edgeBar(.bottom) {
            if !receipt.items.isEmpty, !isOnlyToRead {
                RemovalBar(
                    selectedSize: SizeTotal(selectedItems.map(\.size)).known,
                    isSelectionMeasured: SizeTotal(selectedItems.map(\.size)).isComplete,
                    hasSelection: !selectedItems.isEmpty,
                    isScanning: packages.isScanning,
                    isWorking: packages.isWorking,
                    scan: packages.scanRun,
                    isEnabled: !selectedItems.isEmpty,
                    onRemove: { isConfirmingRemoval = true }
                )
            }
        }
        .fadesInColumn(whenRowsChange: receipt.items.map(\.id))
        .navigationTitle(receipt.identifier)
        .toolbar(removing: .title)
        .confirmationDialog(
            Text.movingToTrash(selectedItems.count, SizeTotal(selectedItems.map(\.size))),
            isPresented: $isConfirmingRemoval
        ) {
            Button("Move to Trash") {
                let apps = receipt.apps(in: selectedItems.map(\.url))
                Task {
                    let asked = await Self.toQuit(apps, among: RunningCopies.current, installedApps: library.apps)
                    quitting.check(asked.compactMap { NSRunningApplication(processIdentifier: $0.identifier) }) {
                        Task { await moveSelection() }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let removalNote {
                removalNote
            }
        }
        .forgetReceiptDialog(for: $receiptToForget, forget: packages.forget)
        .onChange(of: outcome.isEmpty) { _, isEmpty in
            guard isEmpty, let left = forgetOnceTheAlertCloses else { return }
            forgetOnceTheAlertCloses = nil
            receiptToForget = left
        }
        .alert(
            Text(Self.quitTitle(names: quitting.names, several: quitting.namesSeveral)),
            isPresented: Bindable(quitting).isAsking
        ) {
            Button(quitting.namesSeveral ? "Quit Apps" : "Quit \(quitting.names)") { quitting.quit() }
            Button("Cancel", role: .cancel) { quitting.giveUp() }
        }
        .forceQuitOffer(quitting)
        .onDisappear { quitting.giveUp() }
    }

    static func quitTitle(names: String, several: Bool) -> LocalizedStringResource {
        several ? "Quit these apps before removing them." : "Quit \(names) before removing it."
    }

    /// Read from the exclusions, not the scan, so it holds as soon as they change.
    private var isForAnExcludedApp: Bool {
        receipt.apps.contains(where: ExclusionsStore.shared.exclusions.excludes)
    }

    private var forgettingWaitsForTheHelper: Bool {
        !helper.canAct && PackageActions.forgettingNeedsTheHelper(receipt)
    }

    private var forgetHelp: Text {
        if isForAnExcludedApp {
            return Text("The app this package installed is excluded in Settings, so Peel leaves its receipt alone too.")
        }
        return forgettingWaitsForTheHelper
            ? Text(helper.whyItCannotAct)
            : Text("The receipt goes to the Trash. Files stay where they are.")
    }

    /// What an app the move takes does then that History can't undo, and what it leaves behind, as its own page says.
    private var removalNote: Text? {
        var lines = selectedItems.compactMap(\.uninstallsItself).map(\.warning)
        var said: Set<URL> = []
        for item in selectedItems {
            guard let app = item.app, said.insert(app.url).inserted else { continue }
            if let root = TrustedRoot.of(app) {
                lines.append(Text("\(app.name)’s root certificate stays trusted on this Mac after the app goes."))
                lines.append(root.step(in: app.name))
            }
            if let first = item.commandToRunFirst {
                lines.append(first.note(for: app.name))
            }
            if let left = item.leftInTheSystem {
                lines.append(left.whatStays(after: app.name))
                lines.append(left.step)
            }
        }
        guard let first = lines.first else { return nil }
        return lines.dropFirst().reduce(first) { Text("\($0)\n\n\($1)") }
    }

    /// Explains why the list is empty. An unknown file list is checked first: it means `pkgutil` gave none,
    /// not that nothing from the package is left.
    private var emptyListReason: LocalizedStringResource {
        if !receipt.isFileListKnown {
            "macOS didn’t say what this package installed, so Peel can’t tell what is left."
        } else if receipt.installedThroughItsScripts {
            "This package’s scripts put its files in place, so its receipt doesn’t say where they are."
        } else if receipt.nothingLeftOnDisk {
            "Nothing on the receipt of this package is left on this Mac."
        } else {
            "What this package installed is either excluded in Settings or sits in a folder Peel never touches."
        }
    }

    private var header: some View {
        PageHeader(systemImage: "shippingbox") {
            Text(verbatim: receipt.identifier)
                .pageTitle()
                .textSelection(.enabled)
                .help(Text(verbatim: receipt.identifier))
        } details: {
            FlowLayout {
                if let name = receipt.name {
                    Badge(title: Text(verbatim: name), systemImage: "tag")
                }
                if let version = receipt.shownVersion {
                    Badge(title: Text("Version \(version)"), systemImage: "number")
                }
                if let date = receipt.installDate {
                    Badge(title: Text("Installed \(date, format: .dateTime.day().month().year())"), systemImage: "calendar")
                }
                if receipt.nothingLeftOnDisk {
                    NoteBadge(
                        title: Text("Receipt only"), systemImage: "doc.questionmark",
                        name: String(localized: "Receipt only"),
                        detail: Text("macOS still counts this package as installed, but nothing on its receipt is left on this Mac.")
                    )
                } else if !receipt.installedApps.isEmpty {
                    NoteBadge(
                        title: Text("Still installed"), systemImage: "app.badge.checkmark",
                        name: String(localized: "Still installed"),
                        detail: Text("Still on this Mac from this package: \(RemovalFailureAlert.listed(receipt.installedApps)).")
                    )
                }
            }
        } trailing: {
            let movable = receipt.movable(canUseHelper: helper.canAct)
            if !movable.isNothing {
                TotalLabel(total: movable, caption: Text("to remove"))
                    .accessibilityLabel(Text("\(movable.text) can be moved to the Trash"))
            }
        }
    }

    /// True when the receipt lists items and a click can select none of them: the page is then a list to read.
    static func isOnlyToRead(_ receipt: PackageReceipt, canUseHelper: Bool) -> Bool {
        !receipt.items.isEmpty && receipt.selectableRows(canUseHelper: canUseHelper).selectable.isEmpty
    }

    private func rows(isReadOnly: Bool) -> some View {
        ForEach(Array(receipt.items.enumerated()), id: \.element.id) { index, item in
            RemovalRow(
                url: item.url,
                icon: item.url.isNamedAsAnApp ? .file(item.url) : .symbol("doc"),
                detail: item.refusal?.explanation,
                warning: item.refusal == nil ? note(for: item) : nil,
                size: item.size ?? 0,
                isMeasured: item.size != nil,
                isLocked: isLocked(item),
                isLeftAlone: item.isLeftAlone,
                isFirst: index == 0,
                hasNoteColumn: receipt.items.contains { $0.isLeftAlone || $0.heldBack != nil },
                isReadOnly: isReadOnly,
                selection: packages, isSelected: packages.isSelected(item.url)
            )
        }
        .listRowSeparator(.hidden)
    }

    /// The selected items of this receipt. `packages.selectedURLs` is one set shared by all receipts, so it is
    /// filtered to this receipt's items.
    private var selectedItems: [PackageReceipt.Item] {
        receipt.items.filter { packages.selectedURLs.contains($0.url) }
    }

    private var list: SelectableRows<URL> {
        receipt.selectableRows(canUseHelper: helper.canAct)
    }

    private func isLocked(_ item: PackageReceipt.Item) -> Bool {
        item.isLocked(canUseHelper: helper.canAct)
    }

    private func note(for item: PackageReceipt.Item) -> String? {
        if let removedElsewhere = item.removedElsewhere { return String(localized: removedElsewhere.explanation) }
        guard let heldBack = item.heldBack else { return nil }
        let why = String(localized: heldBack.explanation)
        guard heldBack == .beyondTheHelper, item.url.isKernelExtension else { return why }
        return ([why] + KernelExtensionNotes.lines()).joined(separator: "\n\n")
    }

}
