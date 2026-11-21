import AppKit
import PeelCore
import ServiceManagement
import SwiftUI

struct BackgroundItemDetailView: View {
    @Environment(AppLibrary.self) private var library
    @Environment(BackgroundItemLibrary.self) private var backgroundItems
    @Environment(HelperModel.self) private var helper
    @Environment(OrphanLibrary.self) private var orphans
    @Environment(RemovalHistoryStore.self) private var history
    @Environment(\.openSettings) private var openSettings
    @State private var isConfirmingTrash = false
    @State private var isConfirmingDisable = false
    @State private var isEditing = false
    let item: BackgroundItem

    var body: some View {
        Form {
            Section {
                header
            }

            let found = Self.makersUninstaller(of: item, among: library.apps)
            if let found {
                Section {
                    MakersUninstallerNotice(
                        app: found.name, uninstaller: found.uninstaller,
                        saying: Self.makersWarning(for: found).map { Text(verbatim: $0) },
                        isForWhatIsLeft: found.isForWhatIsLeft
                    )
                }
            }

            // An agent a person installed for themselves is its maker's, whose step the note above may give already.
            if let agent = item.managedBy {
                if let uninstaller = agent.makersUninstaller {
                    if found == nil {
                        Section {
                            MakersUninstallerNotice(app: agent.name, uninstaller: uninstaller)
                        }
                    }
                } else {
                    Section {
                        ManagedAgentNotice(agent: agent)
                    }
                }
            }

            if item.noAppOfItsMakerIsInstalled {
                Section {
                    Notice(
                        title: Text("No app from its maker is installed"),
                        detail: Text("Peel lists no app from the team that signed its program. It may be left from an app that is gone, or run for an app kept outside your Applications folders, a driver, or a tool that needs no app."),
                        kind: .note
                    ) { EmptyView() }
                    .padding(.vertical, 6)
                }
            }

            if let app = item.appThatLeft {
                Section {
                    Notice(
                        title: Text("\(app.name) has left this Mac"),
                        detail: Text("This job is from the same maker and is still installed. Orphaned Files lists it with what else \(app.name) left."),
                        kind: .note
                    ) {
                        Button("Open Orphaned Files") {
                            orphans.chooseGroup(listing: item.plistURL, orOf: app.bundleIdentifier)
                            Navigator.shared.requestedTool = .orphans
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            Section {
                LabeledContent("Kind") {
                    Text(item.kind == .daemon ? "Daemon" : item.source == .systemLibrary ? "Agent, for every account" : "Agent")
                }
                if let owner = item.ownerBundleIdentifier {
                    LabeledContent("Comes with") {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(verbatim: item.ownerName ?? library.name(forReference: owner))
                            if item.runsFromTheTrash {
                                Text("In the Trash")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if !item.isOwnerInstalled {
                                Text("No longer installed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if item.isOwnerOnlyItsMaker {
                                Text("Only its maker points to this app.")
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
                if let status = item.loginItemsStatus {
                    LabeledContent("Login Items & Extensions") {
                        FlowLayout {
                            Text(status.words)
                                .foregroundStyle(.secondary)
                            Button {
                                PrivilegedHelper.openLoginItemsSettings()
                            } label: {
                                Text("Open System Settings")
                                    .minimumTarget()
                            }
                            .buttonStyle(.link)
                        }
                    }
                    .labeledContentStyle(.leadingWhenWrapped)
                }
                LabeledContent {
                    answer(item.runsAtLoad)
                } label: {
                    // A daemon is loaded when the Mac starts up, and an agent when the user logs in.
                    item.kind == .daemon ? Text("Starts at boot") : Text("Starts at login")
                }
                LabeledContent("Restarts itself") {
                    answer(item.keepsAlive)
                }
                if let program = item.program {
                    LabeledContent("Program") {
                        Text(verbatim: program)
                            .textSelection(.enabled)
                            .help(Text(verbatim: program))
                        if finderURL?.path(percentEncoded: false) == program {
                            ShowInFinderButton(url: URL(filePath: program))
                        }
                    }
                    .labeledContentStyle(.oneLine)
                }
                if let plist = item.plistURL {
                    LabeledContent("Configuration file") {
                        Text(verbatim: plist.abbreviatedPath)
                            .textSelection(.enabled)
                            .help(Text(verbatim: plist.fullPath))
                        if item.canBeEdited {
                            // On the busy timing, so a quick action doesn't flash it.
                            BusyShown(isBusy: isBusy) { isShown in
                                Button("Edit…") { isEditing = true }
                                    .controlSize(.small)
                                    .disabled(isShown || !history.mayMove)
                            }
                        }
                        if finderURL == plist {
                            ShowInFinderButton(url: plist)
                        }
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

            if ExclusionsStore.shared.exclusions.isUnreadable, !item.canMoveToTrash {
                Section {
                    RemovalsHeldBanner(recordsInHistory: false)
                }
            }

            if item.isExcluded {
                Section {
                    Notice(
                        title: Text("Excluded in Settings"),
                        detail: Text("You excluded the app it is for, so Peel lists it and doesn’t start, stop, enable, disable, or remove it here."),
                        kind: .note
                    ) {
                        Button("Open Exclusions in Settings…") { SettingsPane.exclusions.open(with: openSettings) }
                    }
                    .padding(.vertical, 6)
                }
            }

            if item.declaresAnAppleLabel || item.usesALabelOfMacOS {
                Section {
                    Notice(
                        title: Text(Self.notInstalledByMacOS),
                        detail: Text(item.declaresAnAppleLabel ? Self.appleNameNote : Self.macOSJobNameNote),
                        kind: .caution
                    ) {}
                }
            }

            if item.anotherFileIsLoaded {
                Section {
                    Notice(
                        title: Text("Another file with this name is loaded"),
                        detail: Text(Self.anotherFileNote),
                        kind: .note
                    ) {}
                }
            }

            if let unusable = item.unusableLabel, !item.canBeControlled {
                Section {
                    Notice(
                        title: Text(Self.doesNotChangeIt),
                        detail: Text(Self.whyItsNameIsUnusable(unusable)),
                        kind: .note
                    ) {}
                }
            }

            if item.isSystemExtension {
                Section {
                    Notice(
                        title: Text("This is a system extension"),
                        detail: Text(Self.systemExtensionNote),
                        kind: .note
                    ) {
                        Button("Open Extensions") { Navigator.shared.requestedTool = .extensions }
                        Button("Open Login Items & Extensions") { SMAppService.openSystemSettingsLoginItems() }
                    }
                    .padding(.vertical, 6)
                }
            }

            if item.isManagedByServiceManagement, !item.isPeelsHelper {
                Section {
                    Notice(
                        title: Text("Its switch is in System Settings"),
                        detail: Text("Its app registered it with macOS, so it is turned on or off in System Settings > General > Login Items & Extensions."),
                        kind: .note
                    ) {
                        Button("Open Login Items & Extensions") { SMAppService.openSystemSettingsLoginItems() }
                    }
                    .padding(.vertical, 6)
                }
            }

            if item.isKeptOffBySystemSettings {
                Section {
                    Notice(
                        title: Text("Its switch is in System Settings"),
                        detail: Text(.keptOffBySystemSettings),
                        kind: .note
                    ) {}
                }
            }

            if item.isSubmittedByItsApp {
                Section {
                    Notice(
                        title: Text("Its app added it without a file"),
                        detail: Text("It is not listed in System Settings, and macOS forgets it at the next logout or restart. Apps do this for work such as installing an update."),
                        kind: .note
                    ) {}
                }
            }

            if item.isFileGone {
                Section {
                    Notice(
                        title: Text("Its file is gone"),
                        detail: item.endsAtLogout
                            ? Text("Its file was removed while it was loaded, so macOS runs it until you log out and nothing starts it again. Stop takes it out now.")
                            : Text("Its file was removed while it was loaded, so macOS runs it until the Mac restarts and nothing starts it again. Stop takes it out now."),
                        kind: .note
                    ) {}
                }
            } else if item.source == .otherFile {
                Section {
                    Notice(
                        title: Text("Loaded from a file elsewhere"),
                        detail: item.endsAtLogout
                            ? Text("Something loaded this from a file outside the folders macOS reads at login, so macOS forgets it when you log out. The file is shown above.")
                            : Text("Something loaded this from a file outside the folders macOS reads at startup, so macOS forgets it when the Mac restarts. The file is shown above."),
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
            } else if item.isClosedToPeel {
                Section {
                    Notice(
                        title: Text("Peel can’t read its file"),
                        detail: item.isNamedByItsFile
                            ? Text("macOS lets only its owner read it, so Peel can’t tell what it runs.")
                            : Text("macOS lets only its owner read it, so what Peel shows here is what macOS says of the job it loaded from it."),
                        kind: .note
                    ) {}
                }
            } else if item.loadsOnlyAtTheLoginWindow {
                Section {
                    Notice(
                        title: Text("Loaded only at the login window"),
                        detail: Text("Its file says macOS loads it only at the login window, before anyone logs in, so it is not loaded in your session, and Peel does not load it there."),
                        kind: .note
                    ) {}
                }
            } else if item.state == .unknown {
                Section {
                    Notice(
                        title: Text("Peel can’t tell whether this runs"),
                        detail: Text(Self.whyStateIsNotKnown(item.stateNotKnown)),
                        kind: .note
                    ) {}
                }
            }

            if needsHelper {
                Section {
                    HelperRequiredBanner(
                        need: item.requiresPrivileges && item.offersControls ? .changingThisJob : .moving(1)
                    )
                }
            }

            if item.canMoveToTrash {
                Section {
                    RemovalsHeldBanner()
                }
            }

            if hasOwnControls || item.canMoveToTrash {
                BusyShown(isBusy: isBusy) { isShown in
                    PageActions {
                        if hasOwnControls { ownControls(busyShown: isShown) }
                        moveToTrash(busyShown: isShown)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(item.label)
        .toolbar(removing: .title)
        .sheet(isPresented: $isEditing) {
            LaunchAgentEditor(item: item)
        }
        .confirmationDialog(Text("Move \(item.plistURL?.lastPathComponent ?? item.label) to the Trash?"), isPresented: $isConfirmingTrash) {
            Button("Move to Trash") {
                Task {
                    // Read before the move: afterwards nothing is at that path to measure.
                    var sizes: [URL: Int64] = [:]
                    if let plist = item.plistURL {
                        sizes[plist] = await FileSize.reclaimableSize(of: plist)
                    }
                    await history.moving(tool: .backgroundItems, source: item.label, sizes: sizes) {
                        await backgroundItems.perform(.moveToTrash, on: item) { result in
                            await history.record(result, tool: .backgroundItems, source: item.label, sizes: sizes)
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let warning = item.ownerBundleIdentifier.flatMap { owner in
                item.trashWarning(ownerName: item.ownerName ?? library.name(forReference: owner))
            }
            let maker = Self.makersLine(beforeMoving: Self.makersUninstaller(of: item, among: library.apps))
            Text(verbatim: ([warning, item.whenTrashed].compactMap { $0.map { String(localized: $0) } } + [maker])
                .compactMap(\.self).joined(separator: "\n\n"))
        }
        .confirmationDialog(Text("Disable \(item.label)?"), isPresented: $isConfirmingDisable) {
            Button("Disable") {
                Task { await backgroundItems.perform(.disable, on: item) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let warning = Self.makersWarning(for: Self.makersUninstaller(of: item, among: library.apps)) {
                Text(verbatim: warning)
            }
        }
    }

    typealias MakersStep = (name: String, uninstaller: MakersUninstaller, isForWhatIsLeft: Bool)

    /// The maker's uninstaller for the job's installed app, or for what its app left once gone.
    static func makersUninstaller(of item: BackgroundItem, among apps: [InstalledApp]) -> MakersStep? {
        let place = item.ownerURL.map(PathPattern.comparablePath(of:))
        let app = apps.first { app in
            place.map { $0 == PathPattern.comparablePath(of: app.url) }
                ?? (item.ownerBundleIdentifier != nil && app.bundleIdentifier == item.ownerBundleIdentifier)
        }
        if let app, case .byItsMaker(let uninstaller)? = app.removedElsewhere { return (app.name, uninstaller, false) }
        return item.makersUninstallerForWhatIsLeft.map { (item.appThatLeft?.name ?? $0.maker, $0, true) }
    }

    /// What the questions before Disable and Move to Trash add for a job of an installed app its maker removes. None
    /// for what an app left: no app is there to stop working.
    static func makersWarning(for found: MakersStep?) -> String? {
        guard let found, !found.isForWhatIsLeft else { return nil }
        return String(localized: "\(found.name) is removed with the uninstaller from its maker, which knows everything that goes with it. Changing its job here can keep it from working.")
    }

    /// What the question before Move to Trash adds: the warning for an installed app, or, for what an app left, that
    /// the maker's uninstaller takes more than this job.
    static func makersLine(beforeMoving found: MakersStep?) -> String? {
        guard let found, found.isForWhatIsLeft else { return makersWarning(for: found) }
        return String(localized: "The uninstaller from \(found.uninstaller.maker) also takes what the app kept in the system, which may not all be listed here.")
    }

    private var needsHelper: Bool { item.waitsForTheHelper && !helper.canAct }

    private func answer(_ fact: Bool?) -> Text {
        switch fact {
        case true?: Text("Yes")
        case false?: Text("No")
        case nil: Text("Unknown")
        }
    }

    private var finderURL: URL? {
        (item.isFileGone ? nil : item.plistURL) ?? item.program.map { URL(filePath: $0) }
    }

    private var isBusy: Bool {
        isActing || backgroundItems.isScanning
    }

    private var isActing: Bool {
        backgroundItems.runningActionItemIDs.contains(item.id)
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
                    if let load = item.loadLook() {
                        Badge(title: load.title, systemImage: load.symbol)
                            .contentTransition(.opacity)
                    }
                    if item.isOrphan, !item.isUnreadable {
                        NoteBadge(
                            title: Text("Nothing left to run"), systemImage: "questionmark.circle", tint: .orange,
                            name: String(localized: "Nothing left to run"),
                            detail: Text("The program it starts is gone, or it names none, and no installed app claims it.")
                        )
                    }
                    if item.runsFromTheTrash {
                        NoteBadge(
                            title: Text("Runs from the Trash"), systemImage: "trash", tint: .orange,
                            name: String(localized: "Runs from the Trash"),
                            detail: Text("Its app is in the Trash, and macOS starts it from there each time you log in, until you empty the Trash.")
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
                        Badge(title: Text("Needs administrator access"), systemImage: "lock")
                    }
                }
            }
            Spacer(minLength: 0)
            // The job's own action shows its work beside its buttons.
            BusyShown(isBusy: backgroundItems.isScanning && !isActing) { isShown in
                ZStack {
                    if isShown {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        // Only the badges fade to a new state: the buttons change at once, so two never show in one place.
        .motion(.step, .movement, value: item.state)
        .motion(.step, .movement, value: item.isDisabled)
    }

    /// The item's state, as one badge whose text, symbol, and color change with it. A badge per state would swap
    /// without a fade, because a form row shows a newly inserted view at once.
    private var stateBadge: some View {
        let look = item.stateLook(withProcess: true)
        // The state changes right after the user presses a button here, so the text and symbol crossfade.
        return Badge(title: look.title, systemImage: look.symbol, tint: look.tint)
            .contentTransition(.opacity)
    }

    private var hasOwnControls: Bool { item.offersControls }

    private func ownControls(busyShown: Bool) -> some View {
        Group {
            ForEach(item.controls, id: \.self) { control in
                Button(control.title) {
                    Task { await backgroundItems.perform(control.action, on: item) }
                }
                .help(help(for: control))
            }
            if item.offersEnableOrDisable {
                Button(item.isDisabled ? "Enable" : "Disable") {
                    let found = Self.makersUninstaller(of: item, among: library.apps)
                    if !item.isDisabled, Self.makersWarning(for: found) != nil {
                        isConfirmingDisable = true
                    } else {
                        Task { await backgroundItems.perform(item.isDisabled ? .enable : .disable, on: item) }
                    }
                }
                .help(item.isDisabled ? Text(verbatim: "") : Text("macOS won’t load it again from the next login or restart. If it’s running now, it may keep running until then."))
            }
            if busyShown, isActing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .leadsActionRow()
        .disabled(busyShown || item.requiresPrivileges && !helper.canAct)
    }

    private func help(for control: BackgroundItem.Control) -> Text {
        switch control {
        case .load: Text("Loads it again, and macOS runs it when its file says to.")
        case .runNow: Text("Runs it now, whatever its schedule says.")
        case .restart: Text("Stops it and starts it again at once.")
        case .remove: removeHelp
        case .stop where item.canOnlyBeStopped:
            item.isFileGone ? Text(verbatim: "") : Text("Takes it out of launchd. Its file stays where it is, and it runs again only if something loads it again.")
        case .stop where item.isSeenOnlyWhileLoaded:
            Text("Takes it out of launchd for now. It leaves this list until macOS or its app adds it again.")
        case .stop, .unload:
            Text("Takes it out of launchd until the next login or restart. Its file stays where it is.")
        }
    }

    /// Why Remove is offered, as far as Peel knows where the job's program is.
    private var removeHelp: Text {
        if item.runsFromTheTrash {
            return Text("Takes it out of launchd now. Its app is in the Trash, so macOS starts it again at the next login until you empty the Trash.")
        }
        return item.isOrphan
            ? Text("Takes it out of launchd now: the app that added it is gone, and so is what it ran.")
            : Text("Takes it out of launchd now: the app that added it is no longer installed.")
    }

    @ViewBuilder
    private func moveToTrash(busyShown: Bool) -> some View {
        if item.canMoveToTrash {
            Button("Move to Trash") {
                isConfirmingTrash = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                busyShown || item.removalRequiresPrivileges && !helper.canAct || !history.mayMove
            )
        }
    }

}

private extension BackgroundItem.Control {
    var title: LocalizedStringKey {
        switch self {
        case .stop: "Stop"
        case .restart: "Restart"
        case .runNow: "Run Now"
        case .unload: "Unload"
        case .load: "Load"
        case .remove: "Remove"
        }
    }

    var action: BackgroundItemLibrary.Action {
        switch self {
        case .stop: .stop
        case .restart: .restart
        case .runNow: .runNow
        case .unload: .unload
        case .load: .load
        case .remove: .remove
        }
    }
}

extension LoginItemsStatus {
    var words: LocalizedStringResource {
        switch self {
        case .allowed: "Allowed"
        case .turnedOff: "Needs approval, or was turned off"
        case .notListedYet: "Not listed in System Settings yet"
        case .notFound: "Not found"
        case .unknown: "Unknown"
        }
    }
}

extension UnusualCommand {
    var explanation: LocalizedStringResource {
        switch self {
        case .runsFromATemporaryFolder:
            "Its program sits in a temporary folder, a place for files that aren’t meant to stay. Software installed on purpose can do this too."
        case .runsFromTheSharedFolder:
            "Its program sits in /Users/Shared, where every account on this Mac can write. Software installed on purpose can do this too."
        case .downloads:
            "Its command is `curl` or `wget`, which reaches a network address each time it runs. Software installed on purpose can do this too."
        case .decodesBase64:
            "Its command decodes base64, which keeps what it runs from being read at a glance. Software installed on purpose can do this too."
        case .runsCodeFromItsSettings:
            "A shell or a script interpreter runs code written in the job file itself, so no script on disk shows what it does. Software installed on purpose can do this too."
        }
    }
}

extension BackgroundItem {
    /// What moving the job's file may cost the app that added it, said only of an installed app the job is known to be
    /// part of. "May": Peel can't tell what the app uses the job for.
    func trashWarning(ownerName: String) -> LocalizedStringResource? {
        guard isOwnerInstalled, isOwnerConfirmed, !isOwnerOnlyItsMaker else { return nil }
        return "\(ownerName) uses it to run in the background, and may stop working until you put it back."
    }

    /// Whether launchd forgets the job as the person logs out: an agent's GUI domain ends then, while a daemon's system
    /// domain and an agent's user domain stay (`man launchctl`).
    var endsAtLogout: Bool { kind == .agent && !loadsInTheBackgroundSession }

    /// What becomes of a job launchd still runs once its file is in the Trash.
    var stopsForGood: LocalizedStringResource {
        endsAtLogout
            ? "macOS won’t start it again: it stops for good when you log out."
            : "macOS won’t start it again: it stops for good when the Mac restarts."
    }

    /// What the question before a move says becomes of the job once its file is in the Trash. A row named by its file
    /// has no label Peel read, so nothing is stopped for it.
    var whenTrashed: LocalizedStringResource? {
        // A file launchd doesn't have loaded starts nothing, so its move stops nothing.
        guard !anotherFileIsLoaded, state != .notLoaded else { return nil }
        guard canBeControlled && !isNamedByItsFile else { return stopsForGood }
        // An agent in `/Library/LaunchAgents` runs in every account logged in, and Stop reaches only this one.
        return kind == .agent && source == .systemLibrary
            ? "Peel stops the job for your account once its file is in the Trash. Other accounts logged in now run it until they log out, and none starts it again."
            : "Peel stops the job once its file is in the Trash."
    }
}

extension BackgroundItemDetailView {
    static let notInstalledByMacOS: LocalizedStringResource = "Not installed by macOS"
    static let appleNameNote: LocalizedStringResource = "Its name says Apple, but macOS did not install it. Look at the file to see what put it there."
    static let macOSJobNameNote: LocalizedStringResource = "macOS runs a job by this name, but it did not install this file. Look at the file to see what put it there."
    static let anotherFileNote: LocalizedStringResource = "macOS runs this job from another file with the same name, so this file is not loaded."
    static let systemExtensionNote: LocalizedStringResource = "Only System Settings > General > Login Items & Extensions changes it."
    static let doesNotChangeIt: LocalizedStringResource = "Peel does not change this job"

    static func whyItsNameIsUnusable(_ unusable: BackgroundItem.UnusableLabel) -> LocalizedStringResource {
        switch unusable {
        case .holdsASlash:
            "launchctl reads its name only up to a slash, so a command for it could reach another job."
        case .holdsAControlCharacter:
            "Its name has a control character, which Peel never passes to launchctl."
        case .notTakenByTheHelper:
            "Its name has characters the Peel helper never passes to launchctl."
        }
    }

    static func whyStateIsNotKnown(_ reason: BackgroundItem.StateNotKnown?) -> LocalizedStringResource {
        switch reason {
        case .jobsNotListed, .disabledNotListed:
            "Peel could not read from launchctl which jobs are loaded or turned off."
        case .whichFileNotSaid:
            "Another file declares the same job, and macOS did not say which one it loaded."
        case nil:
            "Peel could not read what macOS answered about this job."
        }
    }
}
