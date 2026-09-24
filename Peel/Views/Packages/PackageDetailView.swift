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
            ExclusionsUnreadableBanner()

            if receipt.items.contains(where: { $0.requiresPrivileges && !$0.isLeftAlone }), !helper.canAct {
                HelperRequiredBanner()
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
                        detail: item.isLeftAlone ? "Left alone: Peel won’t move this, because of where it sits or what is inside it." : nil,
                        size: item.size ?? 0,
                        isMeasured: item.size != nil,
                        isLocked: item.requiresPrivileges && !helper.canAct,
                        isLeftAlone: item.isLeftAlone,
                        isFirst: index == 0,
                        hasNoteColumn: receipt.items.contains(where: \.isLeftAlone),
                        selection: packages, isSelected: packages.isSelected(item.url)
                    )
                }
                .listRowSeparator(.hidden)
            } header: {
                SectionHeaderLine {
                    Text("Installed Items")
                } actions: {
                    SelectAllButton(selectable: selectableURLs, selection: Bindable(packages).selectedURLs)
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
                    .disabled(!helper.canAct)
                    .help(helper.canAct ? Text("The receipt goes to the Trash. Files stay where they are.") : Text("Needs Peel’s helper. Settings says why it can’t act yet."))
                }
            }
        }
        .disabled(packages.isWorking || packages.isScanning)
        .safeAreaBar(edge: .bottom) {
            if !receipt.items.isEmpty {
                RemovalBar(
                    selectedSize: SizeTotal(selectedItems.map(\.size)).known,
                    isSelectionMeasured: SizeTotal(selectedItems.map(\.size)).isComplete,
                    isScanning: packages.isScanning || packages.isWorking,
                    scan: packages.scanRun,
                    isEnabled: !selectedItems.isEmpty && !packages.isWorking,
                    onRemove: { isConfirmingRemoval = true }
                )
            }
        }
        .fadesInColumn(whenRowsChange: receipt.items.map(\.id))
        .navigationTitle(receipt.identifier)
        .toolbar(removing: .title)
        .confirmationDialog(Text.movingToTrash(selectedItems.count, SizeTotal(selectedItems.map(\.size))), isPresented: $isConfirmingRemoval) {
            Button("Move to Trash") {
                Task {
                    let result = await packages.removeSelectedItems { result in
                        await history.record(
                            result,
                            tool: .packages,
                            source: receipt.identifier,
                            sizes: Dictionary(receipt.items.map { ($0.url, $0.size ?? 0) }, uniquingKeysWith: { first, _ in first })
                        )
                    }
                    outcome.report(result)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .forgetReceiptDialog(for: $receiptToForget, forget: packages.forget, rescan: packages.refresh)
    }

    /// Explains why the list is empty. An unknown file list is checked first: it means `pkgutil` gave none,
    /// not that nothing from the package is left.
    private var emptyListReason: LocalizedStringResource {
        if !receipt.isFileListKnown {
            "macOS didn’t say what this package installed, so Peel can’t tell what is left."
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
                if let version = receipt.version {
                    Badge(title: Text("Version \(version)"), systemImage: "number", tint: .secondary)
                }
                if let date = receipt.installDate {
                    Badge(title: Text("Installed \(date, format: .dateTime.day().month().year())"), systemImage: "calendar", tint: .secondary)
                }
                if receipt.nothingLeftOnDisk {
                    NoteBadge(
                        title: Text("Receipt only"), systemImage: "doc.questionmark", tint: .secondary,
                        name: String(localized: "Receipt only"),
                        detail: Text("macOS still counts this package as installed, but nothing it put on disk is left.")
                    )
                }
            }
        } trailing: {
            if movable.known > 0 || !movable.isComplete {
                TotalLabel(total: movable, caption: Text("to remove"))
                    .accessibilityLabel(Text("\(movable.text) can be moved to the Trash"))
            }
        }
    }

    /// The total size that can be moved to the Trash. Items Peel leaves alone are listed but not counted, as
    /// on an app's page.
    private var movable: SizeTotal {
        SizeTotal(receipt.items.filter { !$0.isLeftAlone }.map(\.size))
    }

    /// The selected items of this receipt. `packages.selectedURLs` is one set shared by all receipts, so it is
    /// filtered to this receipt's items.
    private var selectedItems: [PackageReceipt.Item] {
        receipt.items.filter { packages.selectedURLs.contains($0.url) }
    }

    private var selectableURLs: [URL] {
        receipt.items.filter { !$0.isLeftAlone && (helper.canAct || !$0.requiresPrivileges) }.map(\.url)
    }

}
