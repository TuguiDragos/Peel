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
                    Task { await putBack(copy, named: name) }
                }
                .disabled(isOpen)
                .help(isOpen ? Text("Quit \(name) first, or it can write its own settings over these.") : Text("Puts these settings back. Whatever the app set since is cleared first."))
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
        // Asked again at the moment of Put Back: an app opened since the row was drawn would write its own settings
        // over these when it quits.
        refreshOpenApps()
        guard !openApps.contains(copy.bundleIdentifier) else {
            failure = Failure(title: String(localized: "Quit \(name) first, or it can write its own settings over these."), message: "")
            return
        }
        workingOn = copy.id
        defer { workingOn = nil }
        let restored = await PreferenceBackup.restore(from: copy.folder)
        if !restored.isComplete {
            failure = Failure(
                title: String(localized: "Not all of the settings saved for \(name) could be put back."),
                message: restored.clearedSome
                    ? String(localized: "The settings that didn’t go back were cleared first, so the app starts them from scratch. The copy is still here to try again.")
                    : ""
            )
        }
    }

    private func moveToTrash(_ copy: PreferenceBackup.Copy, named name: String) async {
        workingOn = copy.id
        defer { workingOn = nil }
        // Measured before the move, since nothing is left at that path after it.
        let size = await FileSize.allocatedSize(of: copy.folder)
        let result = await TrashService(exclusions: ExclusionsStore.shared.exclusions).trash([copy.folder])
        if let reason = result.failures.first?.reason {
            failure = Failure(title: String(localized: "The copy couldn’t be moved to the Trash."), message: reason.explanation)
        }
        await history.record(result, tool: .applications, source: name, sizes: [URL: Int64](measured: [(copy.folder, size)]))
        reload()
    }

    private var trashQuestion: Text {
        guard let copy = copyToTrash else { return Text(verbatim: "") }
        let name = library.name(forBundleIdentifier: copy.bundleIdentifier)
        return Text("Move the settings saved for \(name) on \(copy.date, format: .dateTime.day().month().year().hour().minute()) to the Trash?")
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
