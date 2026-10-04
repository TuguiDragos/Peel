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

    let app: InstalledApp
    /// True when the app is excluded. Its receipt then can't be forgotten, since the page promises that an
    /// excluded app's files are left alone.
    var isExcluded = false
    @State private var receipts: [PackageReceipt] = []
    /// What each package put outside the app. It is worked out once, with the receipts and off the main
    /// actor, because it takes an `lstat` per file and the page is redrawn whenever a checkbox changes.
    @State private var filesOutside: [PackageReceipt.ID: [PackageReceipt.Item]] = [:]
    @State private var receiptToForget: PackageReceipt?
    @State private var isForgetting = false
    /// The revision of the exclusions the last load read, nil before the first.
    @State private var loadedUnder: Int?

    var body: some View {
        Group {
            if !receipts.isEmpty {
                Section {
                    ForEach(receipts) { receipt in
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
        .task(id: app.id) { await load() }
        .rescanOnExclusionChange(scannedUnder: loadedUnder) { await load() }
        .forgetReceiptDialog(for: $receiptToForget, forget: forget)
    }

    private func load() async {
        let revision = ExclusionsStore.shared.revision
        (receipts, filesOutside) = await Self.receipts(of: app, exclusions: ExclusionsStore.shared.exclusions)
        loadedUnder = revision
    }

    @concurrent
    private nonisolated static func receipts(
        of app: InstalledApp,
        exclusions: Exclusions
    ) async -> ([PackageReceipt], [PackageReceipt.ID: [PackageReceipt.Item]]) {
        let receipts = await PackageReceipts.receipts(installing: app.url, exclusions: exclusions)
        let files = receipts.map {
            ($0.id, VendorRemoval.filesOutsideBundle(of: $0, app: app, otherReceipts: receipts))
        }
        return (receipts, Dictionary(files, uniquingKeysWith: { first, _ in first }))
    }

    @ViewBuilder
    private func rows(for receipt: PackageReceipt) -> some View {
        let files = filesOutside[receipt.id] ?? []
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
                .disabled(isForgetting || !helper.canAct || isExcluded)
                .help(isExcluded ? Text(.excludedApp) : helper.canAct ? Text("The receipt goes to the Trash. Files stay where they are.") : Text("Needs Peel’s helper. Settings says why it can’t act yet."))
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
        await load()
        return result
    }
}
