import AppKit
import PeelCore
import SwiftUI

/// The note on the page of an app carrying system extensions macOS installed, which Peel leaves to Finder.
struct SystemExtensionNotice: View {
    let app: InstalledApp
    let extensions: CarriedSystemExtensions

    var body: some View {
        Notice(
            title: Text("Move It to the Trash in Finder"),
            detail: detail,
            kind: .note
        ) {
            Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            }
        }
    }

    // Each sentence is a literal of its own, so the string catalog finds every one.
    private var detail: Text {
        guard extensions.isKnown else {
            return Text("Peel can’t look inside \(app.name) to see which system extensions it carries, and macOS removes those only when the app goes to the Trash in Finder. So Peel leaves the app and its files where they are: move it to the Trash in Finder, and Orphaned Files then lists what it left.")
        }
        let names = extensions.names.formatted(.list(type: .and))
        let isOne = extensions.names.count == 1
        if #available(macOS 27, *) {
            return switch (isOne, extensions.systemSettingsDeletesThem) {
            case (true, true):
                Text("macOS installed \(names) with \(app.name), and only macOS can remove it. Move the app to the Trash in Finder, which asks macOS to remove the extension too. If it is still listed afterward, open System Settings > General > Login Items & Extensions, choose By Category, click the Info button beside Network Extensions, then click the More button beside it and choose Delete Extension.")
            case (false, true):
                Text("macOS installed \(names) with \(app.name), and only macOS can remove them. Move the app to the Trash in Finder, which asks macOS to remove the extensions too. If they are still listed afterward, open System Settings > General > Login Items & Extensions, choose By Category, click the Info button beside Network Extensions, then click the More button beside each and choose Delete Extension.")
            case (true, false):
                Text("macOS installed \(names) with \(app.name), and only macOS can remove it. Move the app to the Trash in Finder, which asks macOS to remove the extension too.")
            case (false, false):
                Text("macOS installed \(names) with \(app.name), and only macOS can remove them. Move the app to the Trash in Finder, which asks macOS to remove the extensions too.")
            }
        }
        return isOne
            ? Text("macOS installed \(names), a system extension that came with \(app.name), and removes it only when the app goes to the Trash in Finder, sometimes at the next restart. So Peel leaves the app and its files where they are: move it to the Trash in Finder, and Orphaned Files then lists what it left.")
            : Text("macOS installed \(names), system extensions that came with \(app.name), and removes them only when the app goes to the Trash in Finder, sometimes at the next restart. So Peel leaves the app and its files where they are: move it to the Trash in Finder, and Orphaned Files then lists what it left.")
    }
}

/// What an installer put outside the app, according to the receipt macOS kept.
struct PackageReceiptSection: View {
    /// How many files are listed per receipt. The rest are counted, and the Package Receipts page lists them all.
    private static let mostListed = 12

    let plan: RemovalPlan
    /// Scans the page again, which reads the receipts again: a receipt forgotten here also leaves its lists.
    let rescan: () async -> Void
    /// Chosen from the page's More menu.
    @Binding var receiptToForget: PackageReceipt?
    @Binding var isForgetting: Bool

    var body: some View {
        Group {
            if !plan.packageReceipts.isEmpty {
                Section {
                    ForEach(plan.packageReceipts) { receipt in
                        rows(for: receipt)
                    }
                } header: {
                    heading(
                        "Installed by a Package",
                        "macOS keeps a receipt of the files a package installed. The ones outside the app are listed here only to show them: other software may rely on them. If Peel also found one of them for this app, it appears in the lists above as well, and may be selected there. Forgetting a receipt, from the page’s More menu, moves it to the Trash: macOS stops counting the package as installed, and the files stay where they are."
                    )
                }
            }
        }
        .forgetReceiptDialog(for: $receiptToForget, forget: forget)
    }

    @ViewBuilder
    private func rows(for receipt: PackageReceipt) -> some View {
        let files = plan.filesOutside[receipt.id] ?? []
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: receipt.identifier)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            if files.isEmpty {
                Text("Outside the app, Peel found nothing that belongs to this package alone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(files.prefix(Self.mostListed)) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.requiresPrivileges ? "lock.fill" : "doc")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                            // The lock is the only place that says so; the document says nothing.
                            .accessibilityLabel(Text("Needs administrator access"))
                            .accessibilityHidden(!item.requiresPrivileges)
                        Text(item.url.abbreviatedPath)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 12)
                        Text(item.size.byteCount)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: RowColumns.size, alignment: .trailing)
                    }
                }
                if files.count > Self.mostListed {
                    Text("And ^[\(files.count - Self.mostListed) more file](inflect: true). Package Receipts lists them all.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func forget(_ receipt: PackageReceipt, recording record: (TrashResult) async -> Void) async -> TrashResult {
        isForgetting = true
        defer { isForgetting = false }
        let result = await QuitGuard.shared.run {
            let result = await PackageActions.forget(receipt, exclusions: ExclusionsStore.shared.exclusions)
            await record(result)
            return result
        }
        await rescan()
        return result
    }
}
