import AppKit
import PeelCore
import SwiftUI

/// The section that lists the copies of settings that app resets kept, so the user can put one back later.
/// A copy can hold a license key, so each can also be moved to the Trash.
struct SavedSettingsSection: View {
    @Environment(AppLibrary.self) private var library
    @Environment(RemovalHistoryStore.self) private var history
    @State private var copies: [PreferenceBackup.Copy] = []
    @State private var workingOn: PreferenceBackup.Copy.ID?
    @State private var failure: Failure?
    @State private var copyToTrash: PreferenceBackup.Copy?
    @State private var copyToPutBack: PreferenceBackup.Copy?
    /// The copies whose app, or a copy of it writing the same settings, is running. Stored and read again on every
    /// launch and quit, because a read of the workspace while drawing gives Observation nothing to follow.
    @State private var openApps: Set<String> = []

    var body: some View {
        Group {
            if !copies.isEmpty {
                Section {
                    ForEach(copies) { copy in
                        row(for: copy)
                    }
                } header: {
                    heading(
                        "Saved Settings",
                        "A reset keeps a copy of the settings it clears, and Put Back works from it even after the app has written new ones. A copy can hold a license key or an account, so clear the ones you no longer need."
                    )
                }
            }
        }
        .task { reload() }
        // Put Back waits for the app to quit. The workspace reports every change to the apps that run through
        // key-value observing, while it posts no notice for a menu bar or background app.
        .onReceive(NSWorkspace.shared.publisher(for: \.runningApplications)) { _ in
            refreshOpenApps()
        }
        .confirmationDialog(putBackQuestion, isPresented: isAskingToPutBack, presenting: copyToPutBack) { copy in
            Button("Put Back") {
                Task { await putBack(copy, named: library.name(forBundleIdentifier: copy.bundleIdentifier)) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { copy in
            Text("Peel first saves the settings \(library.name(forBundleIdentifier: copy.bundleIdentifier)) has now, as a copy of their own, then puts these in their place.")
        }
        .confirmationDialog(trashQuestion, isPresented: isAskingToTrash, presenting: copyToTrash) { copy in
            Button("Move to Trash") {
                Task { await moveToTrash(copy, named: library.name(forBundleIdentifier: copy.bundleIdentifier)) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(failure?.title ?? "", isPresented: isShowingFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: failure?.message ?? "")
        }
    }

    private func row(for copy: PreferenceBackup.Copy) -> some View {
        let name = library.name(forBundleIdentifier: copy.bundleIdentifier)
        let isOpen = openApps.contains(copy.bundleIdentifier)
        return LabeledContent {
            HStack(spacing: 8) {
                Button("Put Back") {
                    copyToPutBack = copy
                }
                .disabled(isOpen)
                .help(isOpen ? Text("Quit \(name) first, or it can write its own settings over these.") : Text("Puts these settings back, after saving the ones the app has now."))
                Button("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([copy.folder])
                }
                .labelStyle(.iconOnly)
                .help(Text("Show in Finder"))
                Button("Move to Trash", systemImage: "trash") {
                    copyToTrash = copy
                }
                .labelStyle(.iconOnly)
                .help(Text("Move to Trash"))
            }
            .buttonStyle(.bordered)
            .disabled(workingOn != nil)
        } label: {
            Text(verbatim: name)
            Text(copy.date, format: .dateTime.day().month().year().hour().minute())
        }
    }

    private func reload() {
        copies = PreferenceBackup.copies()
        refreshOpenApps()
    }

    /// Whether the app a copy belongs to is running, by the rule a reset uses: the app, its helpers, and another
    /// copy of it that writes the same settings.
    private func isRunning(_ bundleIdentifier: String) -> Bool {
        guard let app = library.apps.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
        }
        return !RunningCopies.belonging(to: app, among: RunningCopies.current, installedApps: library.apps, sharingItsSettings: true).isEmpty
    }

    private func refreshOpenApps() {
        openApps = Set(copies.map(\.bundleIdentifier).filter(isRunning))
    }

    private func putBack(_ copy: PreferenceBackup.Copy, named name: String) async {
        workingOn = copy.id
        defer { workingOn = nil }
        // Asked again at the moment of Put Back and before the settings in use are cleared: an app opened since the
        // row was drawn would write its own settings over these when it quits.
        let restored = await QuitGuard.shared.run {
            await PreferenceBackup.restore(from: copy.folder, of: copy.bundleIdentifier, exclusions: ExclusionsStore.shared.exclusions) { @MainActor in
                isRunning(copy.bundleIdentifier)
            }
        }
        // The settings the app had until now may have become a copy of their own.
        reload()
        switch restored {
        case .complete:
            break
        case .incomplete(let clearedSome):
            failure = Failure(
                title: String(localized: "Not all of the settings saved for \(name) could be put back."),
                message: clearedSome
                    ? String(localized: "The settings that didn’t go back were cleared first, so the app starts them from scratch. The copy is still here to try again.")
                    : ""
            )
        case .notSaved:
            failure = Failure(title: String(localized: "Peel couldn’t save the settings \(name) has now, so it put nothing back."), message: "")
        case .appIsOpen:
            failure = Failure(title: String(localized: "Quit \(name) first, or it can write its own settings over these."), message: "")
        }
    }

    private func moveToTrash(_ copy: PreferenceBackup.Copy, named name: String) async {
        workingOn = copy.id
        defer { workingOn = nil }
        // Measured before the move, since nothing is left at that path after it.
        let size = await FileSize.reclaimableSize(of: copy.folder)
        await QuitGuard.shared.run {
            let result = await TrashService(exclusions: ExclusionsStore.shared.exclusions).trash([copy.folder])
            if let reason = result.failures.first?.reason {
                failure = Failure(title: String(localized: "The copy couldn’t be moved to the Trash."), message: reason.explanation)
            }
            await history.record(result, tool: .applications, source: name, sizes: [URL: Int64](measured: [(copy.folder, size)]))
        }
        reload()
    }

    private var trashQuestion: Text {
        guard let copy = copyToTrash else { return Text(verbatim: "") }
        let name = library.name(forBundleIdentifier: copy.bundleIdentifier)
        return Text("Move the settings saved for \(name) on \(copy.date, format: .dateTime.day().month().year().hour().minute()) to the Trash?")
    }

    private var putBackQuestion: Text {
        guard let copy = copyToPutBack else { return Text(verbatim: "") }
        let name = library.name(forBundleIdentifier: copy.bundleIdentifier)
        return Text("Put back the settings saved for \(name) on \(copy.date, format: .dateTime.day().month().year().hour().minute())?")
    }

    private var isAskingToPutBack: Binding<Bool> {
        Binding(
            get: { copyToPutBack != nil },
            set: { if !$0 { copyToPutBack = nil } }
        )
    }

    private var isAskingToTrash: Binding<Bool> {
        Binding(
            get: { copyToTrash != nil },
            set: { if !$0 { copyToTrash = nil } }
        )
    }

    private var isShowingFailure: Binding<Bool> {
        Binding(
            get: { failure != nil },
            set: { if !$0 { failure = nil } }
        )
    }

    private struct Failure {
        let title: String
        let message: String
    }
}
