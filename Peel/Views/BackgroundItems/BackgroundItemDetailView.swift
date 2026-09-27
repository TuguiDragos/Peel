import AppKit
import PeelCore
import ServiceManagement
import SwiftUI

struct BackgroundItemDetailView: View {
    @Environment(AppLibrary.self) private var library
    @Environment(BackgroundItemLibrary.self) private var backgroundItems
    @Environment(HelperModel.self) private var helper
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(ExclusionsStore.self) private var exclusions
    @Environment(\.openSettings) private var openSettings
    @State private var isConfirmingTrash = false
    /// Reading this and `ownerIconURL` asks macOS, so both are read once per item rather than on every
    /// evaluation of `body`.
    @State private var legacyStatus: LocalizedStringResource?
    @State private var ownerIconURL: URL?
    let item: BackgroundItem

    var body: some View {
        Form {
            Section {
                header
            }

            Section {
                LabeledContent("Kind") {
                    Text(item.kind == .agent ? "Agent" : "Daemon")
                }
                if let owner = item.ownerBundleIdentifier {
                    LabeledContent("Added by") {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(verbatim: item.ownerName ?? library.name(forBundleIdentifier: owner))
                            if !item.isOwnerInstalled {
                                Text("No longer installed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let legacyStatus {
                    LabeledContent("Login Items & Extensions") {
                        HStack(spacing: 8) {
                            Text(legacyStatus)
                            Button {
                                PrivilegedHelper.openLoginItemsSettings()
                            } label: {
                                Text("Open System Settings")
                                    .minimumTarget()
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
                LabeledContent {
                    Text(item.runsAtLoad ? "Yes" : "No")
                } label: {
                    // A daemon is loaded when the Mac starts up, and an agent when the user logs in.
                    item.kind == .daemon ? Text("Starts at boot") : Text("Starts at login")
                }
                LabeledContent("Restarts itself") {
                    Text(item.keepsAlive ? "Yes" : "No")
                }
                if let program = item.program {
                    LabeledContent("Program") {
                        Text(verbatim: program)
                            .textSelection(.enabled)
                            .help(Text(verbatim: program))
                    }
                    .labeledContentStyle(.oneLine)
                }
                if let plist = item.plistURL {
                    LabeledContent("Configuration file") {
                        Text(verbatim: plist.abbreviatedPath)
                            .textSelection(.enabled)
                            .help(Text(verbatim: plist.path(percentEncoded: false)))
                    }
                    .labeledContentStyle(.oneLine)
                }
            }

            if item.isPeelsHelper {
                Section {
                    Notice(
                        title: Text("This is Peel’s helper"),
                        detail: Text("Peel installs, repairs, and uninstalls it in Settings, so it can’t be started or stopped from here."),
                        kind: .note
                    ) {
                        Button("Open Peel Settings") {
                            openSettings()
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            if item.declaresAnAppleLabel {
                Section {
                    Notice(
                        title: Text("This uses one of Apple’s names"),
                        detail: Text("Its name starts with com.apple, but macOS didn’t install it, so Peel doesn’t start, stop, or remove it here. Look at the file to see what put it there."),
                        kind: .caution
                    ) {}
                }
            }

            if item.state == .unknown {
                Section {
                    Notice(
                        title: Text("Peel can’t tell whether this runs"),
                        detail: Text("Peel asked macOS about it and got no answer it could read, so Peel doesn’t start, stop, enable, or disable it here."),
                        kind: .note
                    ) {}
                }
            }

            if needsHelper {
                Section {
                    HelperRequiredBanner()
                }
            }

            if hasOwnControls || finderURL != nil {
                Section {
                    if item.canMoveToTrash {
                        RemovalsHeldBanner()
                    }
                    controls
                }
            }
        }
        .formStyle(.grouped)
        .motion(value: item.state)
        .motion(value: item.isDisabled)
        .task(id: item.id) {
            legacyStatus = status(ofLegacyPlistOf: item)
            ownerIconURL = iconURL(ofOwnerOf: item)
        }
        .navigationTitle(item.label)
        .toolbar(removing: .title)
        .confirmationDialog(Text("Move \(item.plistURL?.lastPathComponent ?? item.label) to the Trash?"), isPresented: $isConfirmingTrash) {
            Button("Move to Trash") {
                Task {
                    // Read before the move: afterwards nothing is at that path to measure.
                    var sizes: [URL: Int64] = [:]
                    if let plist = item.plistURL {
                        sizes[plist] = await FileSize.reclaimableSize(of: plist)
                    }
                    await backgroundItems.perform(.moveToTrash, on: item) { result in
                        await history.record(result, tool: .backgroundItems, source: item.label, sizes: sizes)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Once the file is in the Trash, the item is stopped.")
        }
    }

    /// Whether this item needs administrator access while the helper can't act. Never true for Peel's own helper
    /// or a job with an Apple label: neither offers an action, so the helper would change nothing.
    private var needsHelper: Bool {
        !item.isPeelsHelper && !item.declaresAnAppleLabel && (item.requiresPrivileges || item.removalRequiresPrivileges) && !helper.canAct
    }

    private var finderURL: URL? {
        item.plistURL ?? item.program.map { URL(filePath: $0) }
    }

    private var isBusy: Bool {
        backgroundItems.runningActionItemIDs.contains(item.id) || backgroundItems.isScanning
    }

    /// Returns the URL of the app that owns `item`, for its icon. That app may sit outside the folders Peel scans,
    /// so macOS is asked where it is when `library` doesn't list it.
    private func iconURL(ofOwnerOf item: BackgroundItem) -> URL? {
        if let app = library.apps.first(where: { $0.bundleIdentifier == item.ownerBundleIdentifier }) {
            return app.url
        }
        guard let identifier = item.ownerBundleIdentifier else { return nil }
        return AppInspector.applicationURL(forBundleIdentifier: identifier)
    }

    /// Returns the job's status in System Settings (Login Items & Extensions), or nil when it has no plist file.
    /// Per `SMAppService.h`, `.requiresApproval` also means the user turned the job off, so the text says both.
    private func status(ofLegacyPlistOf item: BackgroundItem) -> LocalizedStringResource? {
        guard let plistURL = item.plistURL else { return nil }
        return switch SMAppService.statusForLegacyPlist(at: plistURL) {
        case .enabled: "Allowed"
        case .requiresApproval: "Needs approval, or was turned off"
        case .notRegistered: "Not registered"
        case .notFound: "Not found"
        @unknown default: nil
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            if let ownerIconURL {
                AppIcon(url: ownerIconURL)
                    .frame(width: 56, height: 56)
            } else {
                Image(systemName: "gearshape.2")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: item.label)
                    .font(.title.bold())
                    .titleLine()
                    .textSelection(.enabled)
                    .help(Text(verbatim: item.label))
                FlowLayout(spacing: 6) {
                    stateBadge
                    if item.isOrphan {
                        NoteBadge(
                            title: Text("Nothing left to run"), systemImage: "questionmark.circle", tint: .orange,
                            name: String(localized: "Nothing left to run"),
                            detail: Text("The program it starts is gone, and no installed app claims it.")
                        )
                    }
                    if needsHelper {
                        Badge(title: Text("Needs administrator access"), systemImage: "lock", tint: .secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    /// The item's state, as one badge whose text, symbol, and color change with it. A badge per state would swap
    /// without a fade, because a form row shows a newly inserted view at once.
    private var stateBadge: some View {
        let (title, symbol, tint): (Text, String, Color) = switch item.state {
        case .unknown: (Text(.unknownBackgroundItemState), "questionmark.circle.dashed", .secondary)
        case _ where item.isDisabled: (Text("Disabled"), "minus.circle", .orange)
        case .running(let pid): (Text("Running · PID \(String(pid))"), "circle.fill", .green)
        case .loaded: (Text("Not running"), "circle", .secondary)
        case .notLoaded: (Text("Not loaded"), "circle.dashed", .secondary)
        }
        // The state changes right after the user presses a button here, so the text and symbol crossfade.
        return Badge(title: title, systemImage: symbol, tint: tint)
            .contentTransition(.opacity)
    }

    /// Start, Stop, Enable, and Disable, which Peel's own helper, a job under one of Apple's names, and a job whose
    /// state Peel could not read don't have.
    private var hasOwnControls: Bool {
        !item.isPeelsHelper && !item.declaresAnAppleLabel && item.state != .unknown
    }

    private var controls: some View {
        let hasFileControls = finderURL != nil || item.canMoveToTrash
        // With controls on one side only, there is no spacer, so the row is only as wide as its buttons and is
        // centered. When the buttons don't fit on one line, `FlowLayout` wraps them onto the next.
        return ViewThatFits(in: .horizontal) {
            HStack {
                if hasOwnControls { ownControls }
                if hasOwnControls, hasFileControls { Spacer() }
                fileControls
            }
            FlowLayout {
                if hasOwnControls { ownControls }
                fileControls
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var ownControls: some View {
        Group {
            // No Start or Stop for a job an app registered. Peel sees it only while it is loaded, so once stopped
            // it would leave the list, and Peel could not start it again. System Settings also offers only a switch.
            if item.source != .app {
                let isRunning = if case .running = item.state { true } else { false }
                Button(isRunning ? "Stop" : "Start", systemImage: isRunning ? "stop.fill" : "play.fill") {
                    Task { await backgroundItems.perform(isRunning ? .stop : .start, on: item) }
                }
            }
            Button(item.isDisabled ? "Enable" : "Disable", systemImage: item.isDisabled ? "checkmark.circle" : "minus.circle") {
                Task { await backgroundItems.perform(item.isDisabled ? .enable : .disable, on: item) }
            }
        }
        .disabled(isBusy || item.requiresPrivileges && !helper.canAct)
    }

    @ViewBuilder
    private var fileControls: some View {
        if let finderURL {
            Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([finderURL])
            }
        }
        if item.canMoveToTrash {
            Button("Move to Trash", systemImage: "trash") {
                isConfirmingTrash = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy || item.removalRequiresPrivileges && !helper.canAct || !exclusions.exclusions.isKnown || history.isUnreadable)
        }
    }

}
