import AppKit
import PeelCore
import ServiceManagement
import SwiftUI

/// The note on the page of an app carrying system extensions macOS installed, which Peel leaves to Finder.
struct SystemExtensionNotice: View {
    let app: InstalledApp
    let extensions: CarriedSystemExtensions

    static let title: LocalizedStringResource = "Move It to the Trash in Finder"

    var body: some View {
        Notice(
            title: Text(Self.title),
            detail: detail,
            kind: .note
        ) {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            }
        }
    }

    /// What the note says: how macOS removes the extensions, and, where macOS 27 deletes a network extension in System
    /// Settings (`systemSettingsDeletesThem`), the step for one it keeps. Each sentence is a literal of its own, so the
    /// string catalog finds every one.
    static func said(
        names: String, app: String, isOne: Bool, systemSettingsDeletesThem: Bool
    ) -> [LocalizedStringResource] {
        let removal: LocalizedStringResource = isOne
            ? "macOS installed \(names), which came with \(app), and removes it only when the app goes to the Trash in Finder, sometimes at the next restart. Orphaned Files then lists what the app left."
            : "macOS installed \(names), which came with \(app), and removes them only when the app goes to the Trash in Finder, sometimes at the next restart. Orphaned Files then lists what the app left."
        guard systemSettingsDeletesThem else { return [removal] }
        let step: LocalizedStringResource = isOne
            ? "If it is still listed afterward, delete it in System Settings > General > Login Items & Extensions > By Category > Network Extensions."
            : "If they are still listed afterward, delete them in System Settings > General > Login Items & Extensions > By Category > Network Extensions."
        return [removal, step]
    }

    private var detail: Text {
        guard extensions.isKnown else {
            return Text("Peel cannot see which system extensions \(app.name) carries, and macOS removes those only when the app goes to the Trash in Finder. Move it there in Finder, and Orphaned Files then lists what it left.")
        }
        let said = Self.said(
            names: extensions.names.formatted(.list(type: .and)), app: app.name, isOne: extensions.names.count == 1,
            systemSettingsDeletesThem: extensions.systemSettingsDeletesThem
        )
        return Text(verbatim: said.map { String(localized: $0) }.joined(separator: "\n\n"))
    }
}

/// The note on the page of an app carrying system extensions macOS runs for an app inside it, which stay installed
/// whoever moves the app, so Peel moves it once they are turned off.
struct SystemExtensionInsideNotice: View {
    let app: InstalledApp
    let extensions: CarriedSystemExtensions

    static func title(of extensions: CarriedSystemExtensions) -> LocalizedStringResource {
        extensions.inAnAppInside.count == 1 ? "Turn Its System Extension Off First" : "Turn Its System Extensions Off First"
    }

    var body: some View {
        Notice(title: Text(Self.title(of: extensions)), detail: detail, kind: .note) {
            Button("Open Login Items & Extensions") { SMAppService.openSystemSettingsLoginItems() }
        }
    }

    private var detail: Text {
        let names = extensions.inAnAppInside.formatted(.list(type: .and))
        return if extensions.inAnAppInside.count > 1 {
            Text("macOS runs \(names) for an app inside \(app.name), and moving the app does not remove them. Turn them off in System Settings > General > Login Items & Extensions, and Peel then moves the app and its files.")
        } else if extensions.keepsTheAppInPlace {
            Text("While \(names) runs, it keeps \(app.name) from being moved, even by Finder. Turn it off in System Settings > General > Login Items & Extensions, and Peel then moves the app and its files.")
        } else {
            Text("macOS runs \(names) for an app inside \(app.name), and moving the app does not remove it. Turn it off in System Settings > General > Login Items & Extensions, and Peel then moves the app and its files.")
        }
    }
}

/// What an installer put outside the app, according to the receipt macOS kept.
struct PackageReceiptSection: View {
    static let note: LocalizedStringResource = "macOS keeps a receipt of the files a package installed. The ones outside the app are listed only to show them, since other software may rely on them. Forgetting the receipt, from the More menu, moves it to the Trash and leaves the files in place."

    /// How many files are listed per receipt. The rest are counted, and the Package Receipts page lists them all.
    private static let mostListed = 12

    let plan: RemovalPlan

    var body: some View {
        if !plan.packageReceipts.isEmpty {
            Section {
                ForEach(plan.packageReceipts) { receipt in
                    rows(for: receipt)
                }
            } header: {
                heading("Installed by a Package", Self.note)
            }
        }
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
}
