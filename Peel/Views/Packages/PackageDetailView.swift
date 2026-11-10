import AppKit
import PeelCore
import SwiftUI

struct PackageDetailView: View {
    @Environment(PackageLibrary.self) private var packages
    @Environment(HelperModel.self) private var helper
    @Environment(RemovalHistoryStore.self) private var history
    @State private var isConfirmingRemoval = false
    @State private var receiptToForget: PackageReceipt?
    @Environment(RemovalOutcome.self) private var outcome
    @Environment(AppLibrary.self) private var library
    @Environment(\.openSettings) private var openSettings
    @State private var quitting = QuitBeforeRemoving()
    let receipt: PackageReceipt

    /// What runs from the apps selected here, which is asked to quit first, as on an app's own page.
    private var runningProcesses: [NSRunningApplication] {
        receipt.apps.filter { app in selectedItems.contains { $0.url == app.url } }.flatMap { app in
            RunningCopies.belonging(to: app, among: RunningCopies.current, installedApps: library.apps)
                .compactMap { NSRunningApplication(processIdentifier: $0.identifier) }
        }
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
    }

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)
            RemovalsHeldBanner()

            if isForAnExcludedApp {
                Notice(
                    title: Text("This app is excluded"),
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
            let forAnAdministrator = receipt.items.filter {
                $0.heldBack == .beyondTheHelper && $0.removedElsewhere == nil
            }
            if !forAnAdministrator.isEmpty {
                Notice(
                    title: Text("Needs an Administrator"),
                    detail: Text("Only an administrator can move these, and Peel’s helper isn’t allowed to move them from where they are. To remove one, show it in Finder, drag it to the Trash, then enter an administrator name and password when macOS asks."),
                    kind: .note,
                    systemImage: "lock.shield"
                ) {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(forAnAdministrator.map(\.url))
                    }
                }
                .listRowSeparator(.hidden)
            }

            Section {
                if receipt.items.isEmpty {
                    Text(emptyListReason)
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                }
                ForEach(Array(receipt.items.enumerated()), id: \.element.id) { index, item in
                    RemovalRow(
                        url: item.url,
                        icon: item.url.pathExtension == "app" ? .file(item.url) : .symbol("doc"),
                        detail: item.refusal?.explanation,
                        warning: item.refusal == nil ? note(for: item) : nil,
                        size: item.size ?? 0,
                        isMeasured: item.size != nil,
                        isLocked: isLocked(item),
                        isLeftAlone: item.isLeftAlone,
                        isFirst: index == 0,
                        hasNoteColumn: receipt.items.contains { $0.isLeftAlone || $0.heldBack != nil },
                        selection: packages, isSelected: packages.isSelected(item.url)
                    )
                }
                .listRowSeparator(.hidden)
            } header: {
                SectionHeaderLine {
                    Text("Installed Items")
                } actions: {
                    SelectMenu(list: list, place: Text(verbatim: receipt.identifier), selection: packages)
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
            if !receipt.items.isEmpty {
                RemovalBar(
                    selectedSize: SizeTotal(selectedItems.map(\.size)).known,
                    isSelectionMeasured: SizeTotal(selectedItems.map(\.size)).isComplete,
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
                quitting.check(runningProcesses) {
                    Task { await moveSelection() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let removalNote {
                removalNote
            }
        }
        .forgetReceiptDialog(for: $receiptToForget, forget: packages.forget)
        .alert(Text("Quit \(quitting.names) before removing it."), isPresented: Bindable(quitting).isAsking) {
            Button(quitting.namesSeveral ? "Quit Apps" : "Quit \(quitting.names)") { quitting.quit() }
            Button("Cancel", role: .cancel) { quitting.giveUp() }
        }
        .forceQuitOffer(quitting)
        .onDisappear { quitting.giveUp() }
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
            ? Text(helper.standing.whyItCannotAct(registeredByAnotherCopy: helper.isRegisteredByAnotherCopy))
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
            "Nothing on this package’s receipt is left on disk."
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
                        detail: Text("macOS still counts this package as installed, but nothing on its receipt is left on disk.")
                    )
                } else if !receipt.installedApps.isEmpty {
                    NoteBadge(
                        title: Text("Still installed"), systemImage: "app.badge.checkmark",
                        name: String(localized: "Still installed"),
                        detail: Text("What this package installed is still on this Mac: \(RemovalFailureAlert.listed(receipt.installedApps)).")
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
