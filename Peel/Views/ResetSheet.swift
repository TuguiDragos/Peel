import AppKit
import PeelCore
import SwiftUI

/// Makes an app forget its settings without uninstalling it. What is selected goes to the Trash, and the
/// preference domains are saved first, because cfprefsd is told to forget them afterwards.
struct ResetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLibrary.self) private var library
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(ExclusionsStore.self) private var exclusions
    @State private var plan: ResetPlan
    @State private var isConfirming = false
    @State private var isPuttingBack = false
    /// The result of Put Settings Back, or nil before it is pressed. A result is shown either way, so a success
    /// doesn't look like a click that did nothing.
    @State private var settingsWentBack: Bool?

    init(app: InstalledApp) {
        _plan = State(initialValue: ResetPlan(app: app))
    }

    var body: some View {
        VStack(spacing: 0) {
            if plan.didReset {
                outcome
            } else {
                choices
            }
        }
        .frame(width: 560, height: 520)
        .motion(value: plan.didReset)
        .confirmationDialog("Reset \(plan.app.name)?", isPresented: $isConfirming) {
            Button("Reset", role: .destructive) {
                Task {
                    let result = await plan.performReset()
                    await history.record(result, tool: .applications, source: plan.app.name, sizes: sizes)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            confirmation
        }
        // Runs again when the exclusions change, because an item the user excludes must drop out of the reset.
        .task(id: exclusions.revision) {
            await plan.refresh(installedApps: library.apps)
        }
        // A reset needs the app quit, so the sheet follows the app launching or quitting while it is open.
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            plan.refreshRunningState()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            plan.refreshRunningState()
        }
    }

    private var phase: ScanPhase {
        if plan.reset == nil { return .scanning(.walk) }
        return plan.items.isEmpty && !plan.canResetPrivacy ? .message : .content
    }

    /// What the reset does, and what History can't undo.
    private var confirmation: Text {
        let resetsPrivacy = plan.resetsPrivacy && plan.canResetPrivacy
        switch (plan.selectedURLs.isEmpty, resetsPrivacy) {
        case (false, true):
            return Text("Everything selected goes to the Trash, and the settings are copied first. \(plan.app.name) opens without what was selected. Its privacy permissions are reset too, and History can’t bring them back.")
        case (true, _):
            return Text("\(plan.app.name) asks you again for what it was allowed to access. History can’t undo this.")
        case (false, false):
            return Text("Everything selected goes to the Trash, and the settings are copied first. \(plan.app.name) opens without what was selected.")
        }
    }

    private var choices: some View {
        List {
            header
                .listRowSeparator(.hidden)

            if plan.needsFullDiskAccess {
                FullDiskAccessBanner()
            }

            if plan.couldNotSaveSettings {
                Notice(
                    title: Text("Nothing was reset"),
                    detail: Text("Peel couldn’t save a copy of the settings first, so it moved nothing.")
                ) { EmptyView() }
                .listRowSeparator(.hidden)
            }

            if plan.isAppRunning {
                Section {
                    HStack(spacing: 10) {
                        Text("\(plan.app.name) is open. Quit it first, or it can write its settings again.")
                            .font(.callout)
                        Spacer(minLength: 8)
                        Button("Quit \(plan.app.name)") { plan.quitApp() }
                            .buttonStyle(.bordered)
                    }
                    .listRowSeparator(.hidden)
                }
            }

            ForEach(AppReset.Group.allCases, id: \.self) { group in
                let items = plan.items(in: group)
                if !items.isEmpty {
                    Section {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            RemovalRow(
                                url: item.url,
                                icon: .symbol(item.kind.symbolName),
                                detail: nil,
                                size: item.size ?? 0,
                                isMeasured: item.size != nil,
                                isFirst: index == 0,
                                hasNoteColumn: false,
                                selection: plan, isSelected: plan.isSelected(item.url)
                            )
                        }
                        .listRowSeparator(.hidden)
                    } header: {
                        heading(group.title, group.explanation)
                    }
                }
            }

            if plan.canResetPrivacy {
                PrivacyResetRow(
                    isOn: $plan.resetsPrivacy,
                    detail: Text("macOS remembers what an app was allowed to access, such as the camera or the microphone. If this is selected, Peel clears that too, so \(plan.app.name) asks you again the next time it needs them. History can’t bring them back.")
                )
            }

            if plan.keepsAppData {
                Section {
                    Text("Peel never offers to remove what \(plan.app.name) keeps for you, whether that is mail, messages, notes, or photos.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                } header: {
                    Text("What Stays")
                }
            }
        }
        .scanState(phase, scan: plan.scanRun) {
            ContentUnavailableView(
                "Nothing to Reset",
                systemImage: "sparkles",
                description: Text("Peel found no settings on this Mac that are certainly \(plan.app.name)’s own.")
            )
        }
        .safeAreaBar(edge: .bottom) { bar }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(nsImage: IconCache.icon(for: plan.app.url))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .accessibilityIgnoresInvertColors()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Reset \(plan.app.name)")
                    .font(.title.bold())
                Text("\(plan.app.name) stays installed and forgets what is selected below. What is selected goes to the Trash, and the settings are copied first.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 6)
    }

    private var bar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(plan.selected.text)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text("^[\(plan.selectedURLs.count) item](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            // Closing the sheet during the reset would lose the Put Settings Back button that follows it.
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .disabled(plan.isResetting)
            // Reset is not the default action, so pressing Return can't start the one step here that changes
            // something.
            Button("Reset") { isConfirming = true }
                .buttonStyle(.borderedProminent)
                .disabled(!plan.hasAnythingToReset || plan.isResetting || plan.isAppRunning)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var outcome: some View {
        List {
            VStack(alignment: .leading, spacing: 10) {
                outcomeTitle
                    .font(.title.bold())
                // Two paragraphs, not one sentence joined in code: languages build sentences differently.
                Group {
                    if plan.askedToMove > 0 {
                        filesDetail
                    }
                    if let privacyDetail {
                        privacyDetail
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .listRowSeparator(.hidden)

            if !plan.failures.isEmpty {
                Section {
                    ForEach(plan.failures, id: \.url) { failure in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(failure.url.abbreviatedPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .font(.callout)
                            Text(verbatim: failure.reason.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Not Moved")
                }
            }

            if let backup = plan.backup {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Button("Put Settings Back") {
                                Task {
                                    isPuttingBack = true
                                    settingsWentBack = await plan.putSettingsBack()
                                    isPuttingBack = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isPuttingBack || plan.isAppRunning)
                            Button("Show in Finder", systemImage: "folder") {
                                NSWorkspace.shared.activateFileViewerSelecting([backup])
                            }
                            .buttonStyle(.bordered)
                        }
                        if let settingsWentBack {
                            Text(settingsWentBack ? "The settings are back as they were." : "Not all of the saved settings could be put back.")
                                .font(.callout)
                                .foregroundStyle(settingsWentBack ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                        }
                    }
                    .padding(.vertical, 2)
                    .listRowSeparator(.hidden)
                } header: {
                    heading(
                        "If You Change Your Mind",
                        "The old settings were saved before they were cleared. Put them back from here: once the app opens again, it writes new settings where the old ones were, and History won’t put the old files back over them."
                    )
                }
            }
        }
        .safeAreaBar(edge: .bottom) {
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    /// The outcome's title, based on what really happened: reset, partly reset, or nothing reset.
    private var outcomeTitle: Text {
        let privacyWasReset = plan.privacy == .reset
        let privacyFailed = plan.privacy.map { $0 != .reset } ?? false
        if plan.movedCount == 0, !privacyWasReset { return Text("Nothing was reset.") }
        return plan.failures.isEmpty && !privacyFailed ? Text("\(plan.app.name) was reset.") : Text("\(plan.app.name) was partly reset.")
    }

    private var privacyDetail: Text? {
        guard let privacy = plan.privacy else { return nil }
        guard let problem = privacy.explanation else {
            return Text("Its privacy permissions were reset, so it asks you again the next time it needs them.")
        }
        return Text("Its privacy permissions weren’t reset. \(problem)")
    }

    private var filesDetail: Text {
        guard plan.movedCount > 0 else {
            return Text("None of what you selected could be moved to the Trash. The reasons are below.")
        }
        switch (plan.failures.isEmpty, plan.didClearSettings) {
        case (true, false):
            return Text("Everything went to the Trash. History can put it back until the app writes new files in its place.")
        case (true, true):
            return Text("Everything went to the Trash. History can put it back until the app writes new files in its place. Peel also told macOS to drop any copy of these settings it still held.")
        case (false, false):
            return Text("What could be moved went to the Trash. History can put it back until the app writes new files in its place.")
        case (false, true):
            return Text("What could be moved went to the Trash. History can put it back until the app writes new files in its place. Peel also told macOS to drop any copy of these settings it still held.")
        }
    }

    private var sizes: [URL: Int64] {
        [URL: Int64](measured: plan.items.map { ($0.url, $0.size) })
    }
}
