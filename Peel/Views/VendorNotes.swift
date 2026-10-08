import AppKit
import PeelCore
import SwiftUI

/// A notice that the app carries system extensions, which macOS installs and removes, not Peel. It sits with
/// the other notices at the top of the page because it changes what removing the app can do. The extensions'
/// names are in its info note rather than on the page.
struct SystemExtensionNotice: View {
    let app: InstalledApp
    let extensions: [String]

    var body: some View {
        if !extensions.isEmpty {
            Notice(
                title: Text("^[\(extensions.count) system extension](inflect: true) inside"),
                detail: Text("macOS manages these, and it isn’t known whether moving the app removes them. Remove \(app.name) in Finder and macOS uninstalls them too. To remove it with Peel instead, turn them off in System Settings first."),
                kind: .note
            ) {
                InfoNote(
                    name: String(localized: "System extensions"),
                    detail: Text("The system extensions \(app.name) carries inside it, whether or not macOS has turned them on."),
                    footnote: Text(verbatim: extensions.joined(separator: "\n"))
                )
                Button("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([app.url])
                }
            }
        }
    }
}

/// What an installer put outside the app, according to the receipt macOS kept.
struct PackageReceiptSection: View {
    @Environment(HelperModel.self) private var helper
    /// How many files are listed per receipt. The rest are counted, and the Package Receipts page lists them all.
    private static let mostListed = 12

    let plan: RemovalPlan
    /// Scans the page again, which reads the receipts again: a receipt forgotten here also leaves its lists.
    let rescan: () async -> Void
    @State private var receiptToForget: PackageReceipt?
    @State private var isForgetting = false

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
                        "macOS keeps a receipt of the files a package installed. The ones outside the app are listed here only to show them: other software may rely on them. If Peel also found one of them for this app, it appears in the lists above as well, and may be selected there. Forgetting a receipt moves it to the Trash: macOS stops counting the package as installed, and the files stay where they are."
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
            HStack(spacing: 8) {
                Text(verbatim: receipt.identifier)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button {
                    receiptToForget = receipt
                } label: {
                    Label("Forget Receipt", systemImage: "doc.badge.ellipsis")
                        .minimumTarget()
                }
                .buttonStyle(.borderless)
                // The page promises that an excluded app's files are left alone, its receipt included.
                .disabled(isForgetting || !helper.canAct || plan.isExcluded)
                .help(plan.isExcluded ? Text(.excludedApp) : helper.canAct ? Text("The receipt goes to the Trash. Files stay where they are.") : Text("Needs Peel’s helper. Settings says why it can’t act yet."))
            }
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
