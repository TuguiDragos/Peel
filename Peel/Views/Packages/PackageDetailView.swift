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
    let receipt: PackageReceipt

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)
            RemovalsHeldBanner()

            // Forget Receipt always needs the helper, whatever the items need.
            if !helper.canAct {
                HelperRequiredBanner(need: .forgettingThisReceipt)
            }
            let forAnAdministrator = receipt.items.filter { $0.heldBack == .beyondTheHelper }
            if !forAnAdministrator.isEmpty {
                Notice(
                    title: Text("Needs an Administrator"),
                    detail: Text("Only an administrator can move these, and Peel’s helper isn’t allowed to move them from where they are. To remove one, show it in Finder, drag it to the Trash, then enter an administrator name and password when macOS asks."),
                    kind: .note,
                    systemImage: "lock.shield"
                ) {
                    Button("Show in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting(forAnAdministrator.map(\.url))
                    }
                }
                .listRowSeparator(.hidden)
            }

            Section {
                if receipt.items.isEmpty {
                    Text(emptyListReason)
                        .foregroundStyle(.secondary)
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
                HStack(spacing: 8) {
                    heading(
                        "Installer Receipt",
                        "Forgetting it moves the receipt to the Trash, so macOS no longer counts the package as installed. What it installed stays where it is."
                    )
                    Spacer(minLength: 8)
                    Button {
                        receiptToForget = receipt
                    } label: {
                        Text("Forget Receipt")
                            .minimumTarget()
                    }
                    .buttonStyle(.borderless)
                    .disabled(!helper.canAct || !history.mayMove || receipt.installedAppIsExcluded)
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
                Task {
                    let result = await packages.removeSelectedItems { result in
                        await history.record(
                            result,
                            tool: .packages,
                            source: receipt.identifier,
                            sizes: [URL: Int64](measured: receipt.items.map { ($0.url, $0.size) })
                        )
                    }
                    outcome.report(result)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let removalNote {
                removalNote
            }
        }
        .forgetReceiptDialog(for: $receiptToForget, forget: packages.forget)
    }

    private var forgetHelp: Text {
        if receipt.installedAppIsExcluded {
            return Text("The app this package installed is excluded in Settings, so Peel leaves its receipt alone too.")
        }
        return helper.canAct
            ? Text("The receipt goes to the Trash. Files stay where they are.")
            : Text(helper.standing.whyItCannotAct(registeredByAnotherCopy: helper.isRegisteredByAnotherCopy))
    }

    /// What an app that uninstalls itself once it moves does then, as its own page warns.
    private var removalNote: Text? {
        let warnings = selectedItems.compactMap(\.uninstallsItself).map(\.warning)
        guard let first = warnings.first else { return nil }
        return warnings.dropFirst().reduce(first) { Text("\($0)\n\n\($1)") }
    }

    /// Explains why the list is empty. An unknown file list is checked first: it means `pkgutil` gave none,
    /// not that nothing from the package is left.
    private var emptyListReason: LocalizedStringResource {
        if !receipt.isFileListKnown {
            "macOS didn’t say what this package installed, so Peel can’t tell what is left."
        } else if receipt.installedThroughItsScripts {
            "This package’s scripts put its files in place, so its receipt doesn’t say where they are."
        } else if receipt.nothingLeftOnDisk {
            "Nothing from this package is left on disk."
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
                if let version = receipt.version {
                    Badge(title: Text("Version \(version)"), systemImage: "number")
                }
                if let date = receipt.installDate {
                    Badge(title: Text("Installed \(date, format: .dateTime.day().month().year())"), systemImage: "calendar")
                }
                if receipt.nothingLeftOnDisk {
                    NoteBadge(
                        title: Text("Receipt only"), systemImage: "doc.questionmark",
                        name: String(localized: "Receipt only"),
                        detail: Text("macOS still counts this package as installed, but nothing it put on disk is left.")
                    )
                } else if !receipt.installedApps.isEmpty {
                    NoteBadge(
                        title: Text("Still installed"), systemImage: "app.badge.checkmark",
                        name: String(localized: "Still installed"),
                        detail: Text("What this package installed is still on this Mac: \(receipt.installedApps.formatted(.list(type: .and))).")
                    )
                }
            }
        } trailing: {
            let movable = receipt.movable(canUseHelper: helper.canAct)
            if movable.known > 0 || !movable.isComplete {
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
        return why + "\n\n"
            + String(localized: "macOS changes the kernel extensions it loads only when the Mac restarts, so restart once this one is in the Trash.")
    }

}
