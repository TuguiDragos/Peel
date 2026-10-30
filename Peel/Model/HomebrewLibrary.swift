import Accessibility
import Foundation
import Observation
import PeelCore

/// A row of the Homebrew page: a package, or a formula's row under Known Vulnerabilities, which leads to the same
/// package's page.
enum HomebrewRow: Hashable {
    case package(HomebrewPackage.ID)
    case vulnerabilities(formula: String)
}

@Observable
final class HomebrewLibrary {
    /// Incremented every time the packages are read, so a view can key work to it. Their count stays the same
    /// through an upgrade, but their versions change.
    private(set) var revision = 0

    enum Command: Equatable {
        case upgrade(HomebrewPackage.ID)
        case upgradeAll
        case uninstall(HomebrewPackage.ID)
        case update
        case cleanup
        case clearOlderDownloads
        case clearEveryDownload
        case repairTaps
        case health
        case vulnerabilities

        var onlyLooks: Bool {
            switch self {
            case .health, .vulnerabilities: true
            case .upgrade, .upgradeAll, .uninstall, .update, .cleanup, .clearOlderDownloads, .clearEveryDownload,
                 .repairTaps: false
            }
        }

        /// An upgrade has no time limit, so its output is shown as it comes and the person can stop it.
        var isUpgrade: Bool {
            switch self {
            case .upgrade, .upgradeAll: true
            case .uninstall, .update, .cleanup, .clearOlderDownloads, .clearEveryDownload, .repairTaps, .health,
                 .vulnerabilities: false
            }
        }

        var deletesFormulae: Bool {
            switch self {
            case .uninstall, .cleanup, .clearOlderDownloads, .clearEveryDownload: true
            case .upgrade, .upgradeAll, .update, .repairTaps, .health, .vulnerabilities: false
            }
        }
    }

    struct CommandResult: Identifiable {
        let id = UUID()
        let succeeded: Bool
        let output: String
    }

    /// Checked again on every refresh, so Homebrew installed while Peel is open is found without a relaunch.
    private(set) var isInstalled = Homebrew.executableURL != nil
    /// The `brew` chosen in Settings when it can no longer be run, in which case Peel runs none.
    private(set) var unrunnableChoice = HomebrewChoice().unrunnable()
    /// A `brew` where Homebrew installs itself that another account owns or anyone can change, which Peel doesn't run.
    private(set) var refusedBrew = Homebrew.refusedInAUsualPlace()
    /// How the last reading failed, which is not the same as nothing being installed.
    private(set) var couldNotRead: Homebrew.CommandFailure?
    private(set) var packages: [HomebrewPackage]?
    /// The installed Homebrew's version and prefix. The version decides what Peel may ask it for.
    private(set) var installation: HomebrewInstallation?
    /// What `brew cleanup` would free, as Homebrew reported it. Nil when it wouldn't say.
    private(set) var reclaimable: Int64?
    /// The formulae `brew cleanup` would uninstall for good because nothing needs them anymore.
    private(set) var autoremovable: [String] = []
    /// What Homebrew's own settings undo of how Peel runs it, or change of what it tells Peel, read with the packages
    /// and again before an upgrade.
    private(set) var overrides: Homebrew.Overrides = []
    /// A `brew.env` the person keeps where Homebrew run from Peel doesn't look (`Homebrew.unreadSettingsFile()`).
    private(set) var unreadSettingsFile = Homebrew.unreadSettingsFile()
    /// Homebrew has no local copy of its package definitions, for example because its cache was cleared (not
    /// by Peel: its Developer page leaves them alone). Any question would make Homebrew download them again,
    /// at launch and on every change in an Applications folder, which would be Peel contacting the network on
    /// its own. So nothing is asked.
    private(set) var needsDefinitions = false
    /// The findings of the last health check. Nil until one runs, and cleared, with the vulnerability report, by
    /// any command that changes Homebrew and by a reading that finds other packages installed, since they would
    /// then describe it as it was.
    private(set) var findings: [HomebrewFinding]?
    private(set) var advisories: HomebrewVulnerabilityReport? {
        didSet { keepSelectionOnItsPage() }
    }
    /// Casks describing installed apps that Homebrew didn't install, read from its local definitions.
    private(set) var knownCasks: [HomebrewPackage] = []
    /// The identifiers of the installer receipts on the Mac. A cask that installs a package proves which app
    /// it is through its receipt.
    private(set) var receipts: Set<String> = []

    /// Everything Peel can use as evidence: what Homebrew installed, plus what it knows about the rest.
    var caskEvidence: [HomebrewPackage] {
        CaskEvidence.combined(installed: packages ?? [], known: knownCasks)
    }

    var knowsItsOwnApps: Bool {
        Self.knowsItsOwnApps(isInstalled: isInstalled, hasAnswered: hasAnswered, isNotRun: isNotRun)
    }

    /// Whether a Homebrew is on this Mac that Peel doesn't run: the `brew` chosen in Settings can't be run, or one
    /// where Homebrew installs itself is refused. Peel then knows nothing of what that Homebrew installed.
    var isNotRun: Bool { unrunnableChoice != nil || refusedBrew != nil }

    /// Whether Homebrew's packages say of every app whether Homebrew installed it: with no Homebrew, or once it
    /// answered, and never while there is one Peel doesn't run.
    static func knowsItsOwnApps(isInstalled: Bool, hasAnswered: Bool, isNotRun: Bool) -> Bool {
        hasAnswered || (!isInstalled && !isNotRun)
    }

    /// Whether Homebrew says whether it installed this copy of Peel: as it says it of any app, or, while Peel doesn't
    /// run the Homebrew on this Mac, once no Caskroom Peel knows holds Peel's cask.
    var knowsWhetherItInstalledPeel: Bool {
        Self.knowsWhetherItInstalledPeel(
            knowsItsOwnApps: knowsItsOwnApps, isNotRun: isNotRun,
            mayHaveInstalledPeel: isNotRun && Homebrew.mayHaveInstalledPeel()
        )
    }

    static func knowsWhetherItInstalledPeel(knowsItsOwnApps: Bool, isNotRun: Bool, mayHaveInstalledPeel: Bool) -> Bool {
        knowsItsOwnApps || isNotRun && !mayHaveInstalledPeel
    }

    static func unanswered(
        isInstalled: Bool, hasAnswered: Bool, couldNotRead: Bool, needsDefinitions: Bool, isNotRun: Bool
    ) -> Unanswered? {
        if isNotRun { return .notRun }
        guard isInstalled, !hasAnswered else { return nil }
        if couldNotRead { return .readingFailed }
        return needsDefinitions ? .hasToUpdate : nil
    }

    /// Why Homebrew's last reading ended without saying what is installed, as its page says it.
    enum Unanswered: Equatable {
        /// Homebrew answered with an error.
        case readingFailed
        /// Homebrew has no local list of its packages, and asking would download it again.
        case hasToUpdate
        /// Peel doesn't run the Homebrew on this Mac, as its page says.
        case notRun
    }

    /// Nil while Homebrew hasn't answered yet, and once it has.
    var unanswered: Unanswered? {
        Self.unanswered(
            isInstalled: isInstalled, hasAnswered: hasAnswered, couldNotRead: couldNotRead != nil,
            needsDefinitions: needsDefinitions, isNotRun: isNotRun
        )
    }

    /// Whether this account may change Homebrew, true until Homebrew has been read. On another account of the Mac its
    /// lists can be read, and what changes it is left to the account it belongs to.
    var mayChange: Bool { installation?.mayBeChangedByThisAccount ?? true }

    /// Why this account can't change Homebrew, or nil when it can.
    var belongsToAnotherAccount: LocalizedStringResource? {
        guard !mayChange else { return nil }
        if let owner = installation?.owner {
            return "Homebrew on this Mac belongs to \(owner), so only that account can update or change it."
        }
        return "Homebrew on this Mac belongs to another account, so only that account can update or change it."
    }

    /// Incremented only when the known casks or receipts change, or Homebrew leaves the Mac. An app's page scans
    /// again when it does, so a page opened before the evidence arrived picks it up, and a page the user is working
    /// on isn't scanned again for nothing.
    private(set) var evidenceRevision = 0

    func loadKnownCasks(for apps: [InstalledApp]) async {
        let found = await PackageReceipts.identifiers()
        let known = await CaskEvidence.knownCasks(for: apps, receipts: found)
        guard known != knownCasks || found != receipts else { return }
        (receipts, knownCasks) = (found, known)
        evidenceRevision += 1
    }
    /// The scan this page runs, which a newer one or the Stop button ends. A command is not a scan, so Stop
    /// doesn't end it.
    let scanRun = ScanRun()
    var isScanning: Bool { scanRun.isRunning }
    /// The command the page is busy with: Homebrew runs it, then Peel reads what it changed, and nothing else starts
    /// until both are done.
    private(set) var runningCommand: Command?
    /// The casks the page is forgetting, until Peel has read Homebrew again. No command runs beside it.
    private(set) var forgetting: Set<HomebrewPackage.ID> = []
    var isForgetting: Bool { !forgetting.isEmpty }
    /// True once a command or a Forget has finished and Peel reads Homebrew again to see what it changed.
    private(set) var isReadingWhatChanged = false
    /// The command while Homebrew itself runs it, which is what its spinner, "Running Homebrew…" and Stop stand for.
    var commandHomebrewRuns: Command? { isReadingWhatChanged ? nil : runningCommand }
    /// The casks while Peel moves their records, which is what Forget's spinner stands for.
    var casksBeingForgotten: Set<HomebrewPackage.ID> { isReadingWhatChanged ? [] : forgetting }
    /// The last lines Homebrew has written in the running upgrade. Nil when no upgrade runs.
    private(set) var progress: String?
    /// True once the person asked the running upgrade to stop.
    private(set) var isStopping = false
    private var runningTask: Task<CommandResult?, Never>?
    var selection: HomebrewRow?
    var result: CommandResult?

    /// Whether Homebrew answered the last reading, so its definitions are on this Mac.
    private(set) var hasAnswered = false
    /// Homebrew's last check for new versions as the last reading found it (`Homebrew.lastUpdateCheck()`).
    private var checkedForUpdates: Date?

    var selectedPackage: HomebrewPackage? {
        switch selection {
        case .package(let id): packages?.first { $0.id == id }
        case .vulnerabilities(let formula): packages?.first { $0.kind == .formula && $0.name == formula }
        case nil: nil
        }
    }

    /// What the last vulnerability scan found in `package`. The scan covers formulae only.
    func advisory(for package: HomebrewPackage) -> HomebrewAdvisory? {
        guard package.kind == .formula else { return nil }
        return advisories?.advisories.first { $0.formula == package.name }
    }

    /// Keeps the page that shows: a row under Known Vulnerabilities whose report went gives way to its package's own
    /// row, and a row whose package went leaves nothing chosen.
    private func keepSelectionOnItsPage() {
        if case .vulnerabilities(let formula) = selection,
           advisories?.advisories.contains(where: { $0.formula == formula }) != true {
            selection = selectedPackage.map { .package($0.id) }
        }
        if selection != nil, selectedPackage == nil {
            selection = nil
        }
    }

    var outdated: [HomebrewPackage] {
        (packages ?? []).filter(\.waitsForAnUpgrade)
    }

    /// The casks Homebrew still lists that left nothing on this Mac: their apps, or with none, their packages.
    var alreadyGone: [HomebrewPackage] {
        (packages ?? []).filter(\.isMissingWhatItInstalled)
    }

    /// The packages Homebrew has disabled or deprecated, disabled first, since those can't be installed again.
    var retired: [HomebrewPackage] {
        let retired = (packages ?? []).filter { $0.retirement != nil && !$0.isMissingWhatItInstalled }
        return retired.filter { $0.retirement?.stage == .disabled }
            + retired.filter { $0.retirement?.stage == .deprecated }
    }

    /// What Upgrade All upgrades: the rest are shown as out of date and left alone (`joinsUpgradeAll`), and all of
    /// them while Homebrew would clean up after an upgrade, which deletes old versions for good.
    var upgradable: [HomebrewPackage] {
        overrides.contains(.cleansUp) ? [] : outdated.filter(\.joinsUpgradeAll)
    }

    /// How many packages of `kind` are installed, or nil while Homebrew hasn't said what is installed.
    func count(of kind: HomebrewPackage.Kind) -> Int? {
        guard hasAnswered else { return nil }
        return (packages ?? []).count { $0.kind == kind }
    }

    /// Reads again whether Homebrew is installed, which the sidebar's default for the Homebrew page follows.
    func checkInstalled() {
        isInstalled = Homebrew.executableURL != nil
        unrunnableChoice = HomebrewChoice().unrunnable()
        refusedBrew = Homebrew.refusedInAUsualPlace()
    }

    /// Whether the sidebar shows the Homebrew page by default: also while Peel won't run the `brew` it found, so the
    /// page can say why.
    var isOnThisMac: Bool {
        isInstalled || isNotRun
    }

    /// Reads the packages again when Homebrew checked for new versions since they were read, as `brew update` in
    /// Terminal does: `checked` is its last check now (`Homebrew.lastUpdateCheck()`). Returns whether it read them.
    func readAgain(ifHomebrewCheckedAt checked: Date?) async -> Bool {
        guard packages != nil, runningCommand == nil, checked != checkedForUpdates else { return false }
        await refresh()
        return true
    }

    /// Reads the installed packages again. `includingReclaimable` also asks how much `brew cleanup` would
    /// free, which only the Homebrew page shows. That is a Ruby command that walks the cache and the Cellar,
    /// so it is asked for only while that page is open or after a command, never on every change in
    /// `/Applications`.
    func refresh(includingReclaimable: Bool = false) async {
        isInstalled = Homebrew.executableURL != nil
        unrunnableChoice = HomebrewChoice().unrunnable()
        refusedBrew = Homebrew.refusedInAUsualPlace()
        guard isInstalled else {
            forgetHomebrew()
            return
        }
        let checked = await Homebrew.lastUpdateCheck()
        guard let reading = await scanRun.run({ await self.read(includingReclaimable: includingReclaimable) }),
              isInstalled
        else { return }
        checkedForUpdates = checked
        guard let (found, installed, preview, overridden) = reading else {
            needsDefinitions = true
            hasAnswered = false
            packages = packages ?? []
            return
        }
        // A failed reading is shown on the page, not stored in `result`, which would open a sheet the next time
        // the page is visited.
        switch installed {
        case .success(let list):
            if let packages, !packages.installsTheSame(as: list) {
                (findings, advisories) = (nil, nil)
            }
            packages = list
            hasAnswered = true
            couldNotRead = nil
        case .failure(let error):
            packages = packages ?? []
            hasAnswered = false
            couldNotRead = error
        }
        self.installation = found
        // Keeps the last figure when this reading brought none: one that was right a moment ago beats none.
        if let preview {
            reclaimable = preview.bytes ?? reclaimable
            autoremovable = preview.autoremoved
        }
        overrides = overridden ?? overrides
        unreadSettingsFile = Homebrew.unreadSettingsFile()
        revision += 1
        keepSelectionOnItsPage()
    }

    /// With no Homebrew on the Mac, nothing it said still holds, so the library becomes what it is when Peel starts
    /// without one. The installer receipts stay: they are the Mac's, and an uninstall reads them on their own.
    private func forgetHomebrew() {
        guard packages != nil || installation != nil || !knownCasks.isEmpty else { return }
        let hadEvidence = !caskEvidence.isEmpty
        (packages, installation, hasAnswered, couldNotRead, needsDefinitions) = (nil, nil, false, nil, false)
        (reclaimable, autoremovable, overrides, findings, advisories) = (nil, [], [], nil, nil)
        (knownCasks, selection) = ([], nil)
        revision += 1
        if hadEvidence {
            evidenceRevision += 1
        }
    }

    /// Nil while Homebrew has no local definitions to read, as when `brew update` has never run.
    private func read(
        includingReclaimable: Bool
    ) async -> (
        HomebrewInstallation?, Result<[HomebrewPackage], Homebrew.CommandFailure>, Homebrew.CleanupPreview?,
        Homebrew.Overrides?
    )? {
        guard await Homebrew.hasLocalDefinitions() else { return nil }
        needsDefinitions = false
        // The installation is read first, since it says how to read the figures that follow. The other questions
        // take about as long as each other, so they run at the same time. Only the page shows the cleanup's figure.
        let found = await Homebrew.installation()
        let kept = found.flatMap { ExclusionsStore.shared.exclusions.keptFormulae(inCellar: $0.cellar) } ?? []
        async let preview = includingReclaimable ? Homebrew.cleanupPreview(asWrittenBy: found, keeping: kept) : nil
        let installed: Result<[HomebrewPackage], Homebrew.CommandFailure>
        var overridden: Homebrew.Overrides?
        do {
            let reading = try await Homebrew.installed()
            installed = .success(reading.packages)
            overridden = reading.overrides
        } catch {
            installed = .failure(error)
        }
        return (found, installed, await preview, overridden)
    }

    /// Runs `command` and returns its result to the caller. Only one command runs at a time: while one runs,
    /// this returns nil at once. `showsResult` is false for a page that shows the result itself, so the
    /// Homebrew page opens no sheet about it later.
    @discardableResult
    func run(_ command: Command, showsResult: Bool = true) async -> CommandResult? {
        guard runningCommand == nil, !isForgetting, command.onlyLooks || mayChange else { return nil }
        runningCommand = command
        defer {
            (runningCommand, isReadingWhatChanged) = (nil, false)
        }
        let task = Task { await outcome(of: command) }
        runningTask = task
        // A quit waits for what changes something, and asks before it stops an upgrade, which can take long.
        var stop: (@MainActor () -> Void)?
        if command.isUpgrade {
            stop = { [weak self] in self?.stopUpgrade() }
        }
        let outcome: CommandResult?
        if command.onlyLooks {
            outcome = await task.value
        } else {
            outcome = await QuitGuard.shared.run(stoppingWith: stop) { await task.value }
        }
        (runningTask, progress, isStopping) = (nil, nil, false)
        if showsResult, let outcome { result = outcome }
        if !command.onlyLooks {
            isReadingWhatChanged = true
            await refresh(includingReclaimable: true)
        }
        return outcome
    }

    /// Moves the Homebrew receipt of each of `casks` whose apps are gone to the Trash, records it with `record`, and
    /// reads the packages again, so Homebrew no longer lists them. Nil while Homebrew is busy.
    func forget(_ casks: [HomebrewPackage], recording record: (TrashResult) async -> Void) async -> TrashResult? {
        guard runningCommand == nil, !isForgetting, mayChange else { return nil }
        forgetting = Set(casks.map(\.id))
        defer { (forgetting, isReadingWhatChanged) = ([], false) }
        let result = await QuitGuard.shared.run {
            let result = await HomebrewReceipt.forget(casks, exclusions: ExclusionsStore.shared.exclusions)
            // Written down before Homebrew is read again, which can take a while: History is the way back.
            await record(result)
            return result
        }
        isReadingWhatChanged = true
        await refresh(includingReclaimable: true)
        return result
    }

    /// How History names a removal of `casks`: by the casks whose record `result` moved, or all of them when none
    /// moved, up to three names, or a count in English that History shows in the user's language through the key.
    static func source(of casks: [HomebrewPackage], after result: TrashResult) -> (source: String, key: String?) {
        let moved = Set(result.trashed.map { PathPattern.comparablePath(of: $0.originalURL) })
        let forgotten = casks.filter { cask in
            cask.caskroomFolder.map { moved.contains(PathPattern.comparablePath(of: $0)) } == true
        }
        let named = forgotten.isEmpty ? casks : forgotten
        guard named.count > 3 else { return (named.map(\.name).joined(separator: ", "), nil) }
        let count = AttributedString(localized: "^[\(named.count) cask](inflect: true)", locale: Locale(identifier: "en"))
        return (String(count.characters), "casks.\(named.count)")
    }

    /// Stops the running upgrade: Homebrew is asked to stop, and killed if it does not.
    func stopUpgrade() {
        guard commandHomebrewRuns?.isUpgrade == true else { return }
        isStopping = true
        runningTask?.cancel()
    }

    /// Nil for a command that only looks and keeps what it found in `findings` or `advisories`.
    private func outcome(of command: Command) async -> CommandResult? {
        if !command.onlyLooks {
            findings = nil
            advisories = nil
        }
        let gone = CommandResult(succeeded: false, output: String(localized: "Homebrew no longer lists this package."))
        if command.isUpgrade, await cleansUpAfterUpgrading() {
            return CommandResult(succeeded: false, output: String(localized: Self.cleansUp))
        }
        var kept: [String] = []
        if command.deletesFormulae {
            switch await keptFormulae() {
            case .formulae(let formulae): kept = formulae
            case .nothingRuns(let result): return result
            }
        }
        do {
            let output: String
            switch command {
            case .upgrade(let id):
                guard let package = package(id) else { return gone }
                return await following { onOutput throws(Homebrew.CommandFailure) in
                    try await Homebrew.upgrade(package, onOutput: onOutput)
                }
            case .upgradeAll:
                let packages = upgradable
                return await following { onOutput throws(Homebrew.CommandFailure) in
                    try await Homebrew.upgrade(packages, onOutput: onOutput)
                }
            case .uninstall(let id):
                guard let package = package(id) else { return gone }
                output = try await Homebrew.uninstall(package, keeping: kept)
            case .update:
                output = try await Homebrew.updateMetadata()
            case .cleanup:
                output = try await Homebrew.cleanup(keeping: kept)
            case .clearOlderDownloads:
                output = try await Homebrew.cleanup(.olderThan(days: 30), keeping: kept)
            case .clearEveryDownload:
                output = try await Homebrew.cleanup(.everyDownload, keeping: kept)
            case .repairTaps:
                output = try await Homebrew.repairTaps()
            case .health:
                // An older Homebrew answers only in prose, which is shown as written. `--json` is a hidden
                // switch, so an answer Peel can't read is asked for again in prose rather than shown as an error.
                guard installation?.reportsHealthAsJSON == true, let found = try? await Homebrew.health() else {
                    let report = await Homebrew.healthReport()
                    return CommandResult(succeeded: !report.isEmpty, output: report)
                }
                findings = found
                // The report fills in a section of the page, which VoiceOver would not notice.
                Self.announce(found.isEmpty
                    ? "Homebrew found nothing out of place."
                    : "^[\(found.count) finding](inflect: true)")
                return nil
            case .vulnerabilities:
                let report = try await Homebrew.vulnerabilities()
                advisories = report
                Self.announce(report.advisories.isEmpty
                    ? "Homebrew found no known vulnerabilities."
                    : "Known vulnerabilities in ^[\(report.advisories.count) package](inflect: true).")
                return nil
            }
            return CommandResult(succeeded: true, output: output)
        } catch {
            return CommandResult(succeeded: false, output: error.output ?? "")
        }
    }

    private var keepsNothing: CommandResult {
        CommandResult(succeeded: false, output: String(localized: "Peel couldn’t make sure Homebrew keeps the formulae your exclusions cover, so it ran nothing. A brew.env file that sets HOMEBREW_NO_CLEANUP_FORMULAE replaces the list Peel gives it."))
    }

    /// The formulae the exclusions cover, read now, for a command the person runs in Terminal, or none when Peel
    /// can't tell which they are.
    var keptFormulaeNow: [String] {
        installation.flatMap { ExclusionsStore.shared.exclusions.keptFormulae(inCellar: $0.cellar) } ?? []
    }

    /// The formulae Homebrew is told to keep, or what Peel says when it runs nothing.
    private enum Keeping {
        case formulae([String])
        case nothingRuns(CommandResult)
    }

    /// The formulae the exclusions cover, which Homebrew is told to keep, asked again right before a command that
    /// deletes for good. Nothing runs when Peel can't tell which they are or Homebrew's own settings replace the list.
    private func keptFormulae() async -> Keeping {
        guard let cellar = installation?.cellar else { return .nothingRuns(keepsNothing) }
        guard let kept = ExclusionsStore.shared.exclusions.keptFormulae(inCellar: cellar) else {
            return .nothingRuns(CommandResult(succeeded: false, output: String(localized: "Peel couldn’t read Homebrew’s Cellar to tell which formulae your exclusions cover, so it ran nothing.")))
        }
        return await Homebrew.keepsEvery(kept) ? .formulae(kept) : .nothingRuns(keepsNothing)
    }

    private static func announce(_ words: LocalizedStringResource) {
        AccessibilityNotification.Announcement(AttributedString(localized: words)).post()
    }

    /// Said where Peel leaves upgrades to Terminal because Homebrew would clean up after them.
    static let cleansUp: LocalizedStringResource = "Homebrew cleans up after every upgrade, deleting old versions for good, so Peel leaves upgrades to Terminal."

    /// Asks Homebrew again right before an upgrade, since its settings can change while the page is open.
    private func cleansUpAfterUpgrading() async -> Bool {
        overrides = await Homebrew.overrides() ?? overrides
        return overrides.contains(.cleansUp)
    }

    /// Runs an upgrade while `progress` shows what Homebrew writes, in the order it writes it, with Peel's own
    /// sentence where a stop or a failure to start happened. That whole transcript is the result, a stopped run's
    /// included, since it is where Homebrew says what it had done.
    private func following(
        _ upgrade: (@escaping @Sendable (Data) -> Void) async throws(Homebrew.CommandFailure) -> String
    ) async -> CommandResult {
        progress = ""
        let (pieces, sink) = AsyncStream.makeStream(of: Data.self)
        // The page shows the last lines, at most ten times a second: a long upgrade writes thousands of lines, and
        // showing all of it on every piece would cost more with each piece.
        let shown = Task {
            var written = Data()
            var shownAt = ContinuousClock.now - .seconds(1)
            for await piece in pieces {
                written.append(piece)
                guard ContinuousClock.now - shownAt >= .milliseconds(100) else { continue }
                progress = OutputTail.lastLines(of: written, count: 400)
                shownAt = .now
            }
            progress = OutputTail.lastLines(of: written, count: 400)
            return String(decoding: written, as: UTF8.self)
        }
        let outcome: Result<String, Homebrew.CommandFailure>
        do {
            outcome = .success(try await upgrade { sink.yield($0) })
        } catch {
            outcome = .failure(error)
        }
        sink.finish()
        let written = await shown.value
        switch outcome {
        case .success(let output):
            return CommandResult(succeeded: true, output: written.isEmpty ? output : written)
        case .failure(let failure):
            return CommandResult(succeeded: false, output: written.isEmpty ? failure.output ?? "" : written)
        }
    }

    private func package(_ id: HomebrewPackage.ID) -> HomebrewPackage? {
        packages?.first { $0.id == id }
    }
}
