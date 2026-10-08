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
    /// Reading this asks macOS, so it is read once per item and scan rather than on every evaluation of `body`.
    @State private var legacyStatus: LocalizedStringResource?
    let item: BackgroundItem

    /// The id of the task that reads `legacyStatus`: the item, and the scans that finished, so Rescan asks again.
    private struct Look: Hashable {
        let item: BackgroundItem.ID
        let scans: Int
    }

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
                            } else if !item.isOwnerConfirmed {
                                Text("Only its name points to this app.")
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
                            SettingsPane.helper.open(with: openSettings)
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
            } else if item.usesALabelOfMacOS {
                Section {
                    Notice(
                        title: Text("This uses the name of one of macOS’s jobs"),
                        detail: Text("macOS runs a job by this name, but it didn’t install this file, so Peel doesn’t start, stop, or remove it here. Look at the file to see what put it there."),
                        kind: .caution
                    ) {}
                }
            }

            if item.source == .otherFile {
                Section {
                    Notice(
                        title: Text("Loaded from a file elsewhere"),
                        detail: item.kind == .daemon
                            ? Text("Something loaded this from a file outside the folders macOS reads at startup, so macOS forgets it when the Mac restarts. The file is shown above.")
                            : Text("Something loaded this from a file outside the folders macOS reads at login, so macOS forgets it when you log out. The file is shown above."),
                        kind: .note
                    ) {}
                }
            }

            if item.isUnreadable {
                Section {
                    Notice(
                        title: Text("macOS can’t load this file"),
                        detail: Text("It can’t be read as a property list, or it names no job, so macOS never loads it and nothing runs from it."),
                        kind: .note
                    ) {}
                }
            } else if item.state == .unknown {
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
        .task(id: Look(item: item.id, scans: backgroundItems.scans)) {
            legacyStatus = await Self.legacyStatus(of: item)
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
            if item.canBeControlled || item.state == .notLoaded {
                Text("Once the file is in the Trash, the item is stopped.")
            } else {
                Text("macOS won’t start it again: it stops for good when the Mac restarts.")
            }
        }
    }

    /// Whether this item needs administrator access while the helper can't act. Never true for Peel's own helper
    /// or a job under one of macOS's labels: neither offers an action, so the helper would change nothing.
    private var needsHelper: Bool {
        !item.isPeelsHelper && !item.usesALabelOfMacOS && (item.requiresPrivileges || item.removalRequiresPrivileges)
            && !helper.canAct
    }

    private var finderURL: URL? {
        item.plistURL ?? item.program.map { URL(filePath: $0) }
    }

    private var isBusy: Bool {
        backgroundItems.runningActionItemIDs.contains(item.id) || backgroundItems.isScanning
    }

    /// Returns the job's status in System Settings (Login Items & Extensions), or nil when it has no plist file.
    /// Per `SMAppService.h`, `.requiresApproval` also means the user turned the job off, so the text says both.
    /// Off the main thread: `SMAppService` asks Background Task Management over XPC.
    @concurrent
    private static func legacyStatus(of item: BackgroundItem) async -> LocalizedStringResource? {
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
            if let ownerURL = item.ownerURL {
                AppIcon(url: ownerURL)
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
                    .pageTitle()
                    .textSelection(.enabled)
                    .help(Text(verbatim: item.label))
                FlowLayout(spacing: 6) {
                    stateBadge
                    if item.isOrphan, !item.isUnreadable {
                        NoteBadge(
                            title: Text("Nothing left to run"), systemImage: "questionmark.circle", tint: .orange,
                            name: String(localized: "Nothing left to run"),
                            detail: Text("The program it starts is gone, and no installed app claims it.")
                        )
                    }
                    if let unusual = item.unusualCommand {
                        NoteBadge(
                            title: Text("Unusual command"), systemImage: "exclamationmark.magnifyingglass",
                            tint: .orange,
                            name: String(localized: "Unusual command"),
                            detail: Text(unusual.explanation)
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
        let look = item.stateLook(withProcess: true)
        // The state changes right after the user presses a button here, so the text and symbol crossfade.
        return Badge(title: look.title, systemImage: look.symbol, tint: look.tint)
            .contentTransition(.opacity)
    }

    /// Start, Stop, Enable, and Disable, which a job Peel may not control, a job whose state Peel could not read, a
    /// file macOS can't load, and a job loaded from a file elsewhere don't have. Disabled, that last one would leave
    /// the list at the next logout or restart with nothing left to Enable it from.
    private var hasOwnControls: Bool {
        item.canBeControlled && item.state != .unknown && item.source != .otherFile && !item.isUnreadable
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
            // No Start or Stop for a job Peel sees only while it is loaded: once stopped it would leave the list,
            // and Peel could not start it again. For an app's job, System Settings also offers only a switch.
            if !item.isSeenOnlyWhileLoaded {
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
            .disabled(
                isBusy || item.removalRequiresPrivileges && !helper.canAct || !exclusions.exclusions.isKnown
                    || history.isUnreadable
            )
        }
    }

}

extension UnusualCommand {
    var explanation: LocalizedStringResource {
        switch self {
        case .runsFromATemporaryFolder:
            "Its program sits in a temporary folder, where any program on this Mac can write. Software installed on purpose can do this too."
        case .downloads:
            "Its command downloads from the internet each time it runs. Software installed on purpose can do this too."
        case .decodesBase64:
            "Its command decodes base64, which keeps what it runs from being read at a glance. Software installed on purpose can do this too."
        case .runsCodeFromItsSettings:
            "It runs a script written into its own file rather than a program on disk. Software installed on purpose can do this too."
        }
    }
}
