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
    @ObservationIgnored private let appsOfCask: (HomebrewPackage) -> [InstalledApp]
    @ObservationIgnored private var exclusionAnswers = ExclusionAnswers()
    /// Waiting for a cask's apps to quit before Homebrew changes them. These are the library's, not a page's: choosing
    /// another row builds another page, and the command the person asked for still has to run.
    let quittingToUpgrade = QuitBeforeRemoving()
    let quittingToUninstall = QuitBeforeRemoving()
    @ObservationIgnored private let ownProgram: () -> OwnProgram

    init(
        appsOfCask: @escaping (HomebrewPackage) -> [InstalledApp] = { _ in [] },
        ownProgram: @escaping () -> OwnProgram = OwnProgram.init
    ) {
        self.appsOfCask = appsOfCask
        self.ownProgram = ownProgram
    }

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

        var changesApps: Bool {
            switch self {
            case .upgrade, .upgradeAll, .uninstall: true
            case .update, .cleanup, .clearOlderDownloads, .clearEveryDownload, .repairTaps, .health,
                 .vulnerabilities: false
            }
        }
    }

    struct CommandResult: Identifiable {
        /// How a command ended: Homebrew finished it, or failed, or Peel stopped before it started Homebrew.
        enum Ending { case finished, failed, notRun }

        let id = UUID()
        let ending: Ending
        let output: String

        var succeeded: Bool { ending == .finished }
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
    /// The command-line tools Homebrew installed: its formulae, none until the packages are read.
    var formulae: [HomebrewPackage] { packages?.filter { $0.kind == .formula } ?? [] }
    /// The installed Homebrew's version and prefix. The version decides what Peel may ask it for.
    private(set) var installation: HomebrewInstallation?
    /// What `brew cleanup` would free, as Homebrew reported it. Nil when it wouldn't say.
    private(set) var reclaimable: Int64?
    /// The formulae `brew cleanup` would uninstall for good because nothing needs them anymore.
    private(set) var autoremovable: [String] = []
    /// What Homebrew's own settings undo of how Peel runs it, or change of what it tells Peel, read with the packages
    /// and again before an upgrade.
    private(set) var overrides: Homebrew.Overrides = []
    private(set) var leavesChangesToTerminal = false
    /// The word that runs this Homebrew in Terminal, for every command a page gives, read with the packages.
    private(set) var wordForTerminal = "brew"
    /// A `brew.env` the person keeps where Homebrew run from Peel doesn't look, read with the packages
    /// (`Homebrew.unreadSettingsFile(prefix:)`).
    private(set) var unreadSettingsFile: URL?
    /// Where the `brew.env` files Homebrew reads when Peel runs it are, read with the packages. Empty until Homebrew
    /// says where it is.
    private(set) var settingsFolders: [URL] = []
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
    /// The apps the known casks were read for, so a reading that finds Homebrew checked for new versions since reads
    /// them again, with what its catalog lists now.
    private var appsOfKnownCasks: [InstalledApp]?
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

    /// Why this account can't change Homebrew, and the command that puts it right where this account can run one.
    struct CantChange {
        let title: LocalizedStringResource
        let detail: LocalizedStringResource
        var command: String?
    }

    /// Nil when this account can change Homebrew. Root can't help, since Homebrew refuses to run as root (`brew.sh`),
    /// and a folder of this account's own only lacks a permission, so only another account's is theirs to change.
    func whyItCantChange(isAdministrator: Bool) -> CantChange? {
        guard let unwritable = installation?.unwritable else { return nil }
        let folder = unwritable.folder.abbreviatedPath
        let command = unwritable.command ?? ""
        switch unwritable.owner {
        case .another(let owner?):
            return CantChange(
                title: "Homebrew Belongs to Another Account",
                detail: "Homebrew on this Mac belongs to \(owner), so only that account can update or change it."
            )
        case .another(nil):
            return CantChange(
                title: "Homebrew Belongs to Another Account",
                detail: "Homebrew on this Mac belongs to another account, so only that account can update or change it."
            )
        case .root where AdministratorCommand.needsAnAdministrator(command, isAdministrator: isAdministrator):
            return CantChange(
                title: "This Account Can’t Change Homebrew",
                detail: "\(folder) belongs to root, so Homebrew can’t change it, and Homebrew doesn’t run as root. To give the folder back to this account, an administrator runs this in Terminal, or you run it after `su` and an administrator’s short name: \(command)",
                command: command
            )
        case .root:
            return CantChange(
                title: "This Account Can’t Change Homebrew",
                detail: "\(folder) belongs to root, so Homebrew can’t change it, and Homebrew doesn’t run as root. Give the folder back to this account by running this in Terminal: \(command)",
                command: command
            )
        case .thisAccount:
            return CantChange(
                title: "This Account Can’t Change Homebrew",
                detail: "\(folder) belongs to this account but can’t be written to, so Homebrew can’t change it. Allow it by running this in Terminal: \(command)",
                command: command
            )
        }
    }

    /// Incremented only when the known casks or receipts change, or Homebrew leaves the Mac. An app's page scans
    /// again when it does, so a page opened before the evidence arrived picks it up, and a page the user is working
    /// on isn't scanned again for nothing.
    private(set) var evidenceRevision = 0

    func loadKnownCasks(for apps: [InstalledApp]) async {
        appsOfKnownCasks = apps
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
    var runningCommand: Command?
    /// The casks the page is forgetting, until Peel has read Homebrew again. No command runs beside it.
    private(set) var forgetting: Set<HomebrewPackage.ID> = []
    var isForgetting: Bool { !forgetting.isEmpty }
    /// True once a command or a Forget has finished and Peel reads Homebrew again to see what it changed.
    private(set) var isReadingWhatChanged = false
    /// The command while Homebrew itself runs it, which is what its spinner, "Running Homebrew…" and Stop stand for.
    var commandHomebrewRuns: Command? { isReadingWhatChanged ? nil : runningCommand }
    private var isChangingHomebrew: Bool {
        !isReadingWhatChanged && (isForgetting || runningCommand?.onlyLooks == false)
    }
    /// The casks while Peel moves their records, which is what Forget's spinner stands for.
    var casksBeingForgotten: Set<HomebrewPackage.ID> { isReadingWhatChanged ? [] : forgetting }
    /// The last lines Homebrew has written in the running upgrade. Nil when no upgrade runs.
    private(set) var progress: String?
    /// True once the person asked the running upgrade to stop.
    private(set) var isStopping = false
    private var runningTask: Task<CommandResult?, Never>?
    var selection: HomebrewRow?
    var result: CommandResult?
    /// The result of a command that replaced Peel while it ran. This process can no longer trust what it reads about
    /// itself, so the window says so above every page.
    var replacedPeel: CommandResult?

    /// Whether Homebrew answered the last reading, so its definitions are on this Mac.
    private(set) var hasAnswered = false
    /// What `brew.sh` told the last reading about where Homebrew is.
    private var answers = Homebrew.Answers()
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

    /// What Upgrade All upgrades, as the page shows it: the rest are shown as out of date and left alone
    /// (`joinsUpgradeAll`, the exclusions), and all of them while Homebrew would clean up after an upgrade, which
    /// deletes old versions for good.
    var upgradable: [HomebrewPackage] {
        guard !overrides.contains(.cleansUp), !leavesChangesToTerminal else { return [] }
        return outdated.filter { $0.joinsUpgradeAll && exclusionAnswer(of: $0) == false }
    }

    /// `upgradable`, asked anew of the exclusions and the disk, for what is about to run.
    var upgradableNow: [HomebrewPackage] {
        guard !overrides.contains(.cleansUp), !Homebrew.leavesChangesToTerminal else { return [] }
        return ExclusionsStore.shared.exclusions.joiningUpgradeAll(
            outdated, appsOf: appsOfCask, installation: installation
        )
    }

    private func exclusionAnswer(of package: HomebrewPackage) -> Bool? {
        exclusionAnswers.answer(
            ExclusionsStore.shared.exclusions, of: package, apps: appsOfCask(package), installation: installation
        )
    }

    /// Why the exclusions keep Homebrew from changing `package`, or nil when they don't: an upgrade deletes the version
    /// it replaces for good, as `brew uninstall` deletes the package.
    func exclusionRefusal(of package: HomebrewPackage) -> LocalizedStringResource? {
        let exclusions = ExclusionsStore.shared.exclusions
        if exclusions.isUnreadable { return "Exclusions can’t be read: see Settings" }
        if !exclusions.hasBeenRead { return "Checking…" }
        switch exclusions.excludes(package, apps: appsOfCask(package), installation: installation) {
        case true?: return "Excluded in Settings"
        case nil: return Self.cantLookInside
        case false?: return nil
        }
    }

    static let cantLookInside: LocalizedStringResource = "Peel couldn’t look inside this package’s folders to check them against your exclusions"

    func isExcluded(_ package: HomebrewPackage) -> Bool {
        ExclusionsStore.shared.exclusions.isKnown && exclusionAnswer(of: package) == true
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

    /// When Homebrew last checked for new versions, from the folders the last reading asked about, so looking starts
    /// no `brew`.
    func lastUpdateCheck() async -> Date? {
        await Homebrew.lastUpdateCheck(asking: answers)
    }

    /// Reads the packages again when Homebrew checked for new versions since they were read, as `brew update` in
    /// Terminal does: `checked` is its last check now (`lastUpdateCheck()`). Returns whether it read them.
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
        // What Homebrew says in the middle of a change is only halfway, and the change's own end reads it again: an
        // upgrade takes the old app away and names its folder `<version>.upgrading` while it unpacks the new one.
        guard !isChangingHomebrew else { return }
        isInstalled = Homebrew.executableURL != nil
        unrunnableChoice = HomebrewChoice().unrunnable()
        refusedBrew = Homebrew.refusedInAUsualPlace()
        guard isInstalled else {
            forgetHomebrew()
            return
        }
        let answers = Homebrew.Answers()
        self.answers = answers
        let checked = await Homebrew.lastUpdateCheck(asking: answers)
        guard let reading = await scanRun.run({
            await self.read(includingReclaimable: includingReclaimable, asking: answers)
        }),
              isInstalled
        else { return }
        let checkedBefore = checkedForUpdates
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
        leavesChangesToTerminal = Homebrew.leavesChangesToTerminal
        wordForTerminal = Homebrew.wordForTerminal
        // Keeps the last figure when this reading brought none: one that was right a moment ago beats none.
        if let preview {
            reclaimable = preview.bytes ?? reclaimable
            autoremovable = preview.autoremoved
        }
        overrides = overridden ?? overrides
        unreadSettingsFile = found.flatMap { Homebrew.unreadSettingsFile(prefix: $0.prefix) }
        settingsFolders = found.map { Homebrew.settingsFolders(prefix: $0.prefix) } ?? []
        // A check for new versions also changes what the catalog lists for the apps Homebrew didn't install.
        if checked != checkedBefore, let apps = appsOfKnownCasks {
            await loadKnownCasks(for: apps)
        }
        revision += 1
        keepSelectionOnItsPage()
    }

    /// Reads the `brew` the person just chose, and keeps nothing the other one said of what it would free.
    func readAnotherBrew() async {
        (reclaimable, autoremovable) = (nil, [])
        await refresh(includingReclaimable: true)
    }

    /// With no Homebrew on the Mac, nothing it said still holds, so the library becomes what it is when Peel starts
    /// without one. The installer receipts stay: they are the Mac's, and an uninstall reads them on their own.
    private func forgetHomebrew() {
        guard packages != nil || installation != nil || !knownCasks.isEmpty else { return }
        let hadEvidence = !caskEvidence.isEmpty
        (packages, installation, hasAnswered, couldNotRead, needsDefinitions) = (nil, nil, false, nil, false)
        (reclaimable, autoremovable, overrides, findings, advisories) = (nil, [], [], nil, nil)
        (leavesChangesToTerminal, wordForTerminal) = (false, "brew")
        (knownCasks, selection, unreadSettingsFile, settingsFolders) = ([], nil, nil, [])
        answers = Homebrew.Answers()
        revision += 1
        if hadEvidence {
            evidenceRevision += 1
        }
    }

    /// Nil while Homebrew has no local definitions to read, as when `brew update` has never run.
    private func read(
        includingReclaimable: Bool, asking answers: Homebrew.Answers
    ) async -> (
        HomebrewInstallation?, Result<[HomebrewPackage], Homebrew.CommandFailure>, Homebrew.CleanupPreview?,
        Homebrew.Overrides?
    )? {
        // The installation is read first: whose Homebrew this is needs no definitions, and it says how to read the
        // figures that follow.
        let found = await Homebrew.installation(asking: answers)
        if let found {
            installation = found
        }
        guard await Homebrew.hasLocalDefinitions(asking: answers) else { return nil }
        needsDefinitions = false
        // The other questions take about as long as each other, so they run at the same time. Only the page shows the
        // cleanup's figure.
        let exclusions = ExclusionsStore.shared.exclusions
        let kept = found.flatMap { try? exclusions.keptFormulae(inCellar: $0.cellar).get() } ?? []
        async let preview = includingReclaimable ? Homebrew.cleanupPreview(asWrittenBy: found, keeping: kept) : nil
        let installed: Result<[HomebrewPackage], Homebrew.CommandFailure>
        var overridden: Homebrew.Overrides?
        do {
            let reading = try await Homebrew.installed(asking: answers)
            installed = .success(reading.packages)
            overridden = reading.overrides
        } catch {
            installed = .failure(error)
        }
        return (found, installed, await preview, overridden)
    }

    /// Runs `command` and returns its result to the caller. Only one command runs at a time: while one runs,
    /// this returns nil at once. `showsResult` is false for a page that shows the result itself, so the
    /// Homebrew page opens no sheet about it later. `reopen` opens what was quit for the command as soon as it ends.
    @discardableResult
    func run(_ command: Command, showsResult: Bool = true, reopening reopen: () -> Void = {}) async -> CommandResult? {
        guard runningCommand == nil, !isForgetting, command.onlyLooks || mayChange else {
            reopen()
            return nil
        }
        runningCommand = command
        defer {
            (runningCommand, isReadingWhatChanged) = (nil, false)
        }
        let program = ownProgram()
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
            // Inside the guard: a quit of Peel asked for meanwhile ends as soon as this does.
            outcome = await QuitGuard.shared.run(stoppingWith: stop) {
                let outcome = await task.value
                reopen()
                return outcome
            }
        }
        (runningTask, progress, isStopping) = (nil, nil, false)
        if let outcome, program.isReplaced {
            replacedPeel = outcome
        } else if showsResult, let outcome {
            result = outcome
        }
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
        return ("\(named.count) casks", "casks.\(named.count)")
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
        let gone = CommandResult(ending: .notRun, output: String(localized: "Homebrew no longer lists this package."))
        if command.isUpgrade, await cleansUpAfterUpgrading() {
            return CommandResult(ending: .notRun, output: String(localized: Self.cleansUp))
        }
        if command.changesApps, Homebrew.leavesChangesToTerminal {
            return CommandResult(ending: .notRun, output: String(localized: FixedSentence.homebrewElsewhere.words))
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
                let packages = upgradableNow
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
                    return CommandResult(ending: report.isEmpty ? .failed : .finished, output: report)
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
            return CommandResult(ending: .finished, output: output)
        } catch {
            return CommandResult(ending: .failed, output: error.output ?? "")
        }
    }

    private var keepsNothing: CommandResult {
        CommandResult(ending: .notRun, output: String(localized: "Peel couldn’t make sure Homebrew keeps the formulae your exclusions cover, so it ran nothing. A brew.env file that sets HOMEBREW_NO_CLEANUP_FORMULAE replaces the list Peel gives it."))
    }

    /// The formulae the exclusions cover, read now, for a command the person runs in Terminal, or none when Peel
    /// can't tell which they are.
    var keptFormulaeNow: [String] {
        installation.flatMap { try? ExclusionsStore.shared.exclusions.keptFormulae(inCellar: $0.cellar).get() } ?? []
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
        let kept: [String]
        switch ExclusionsStore.shared.exclusions.keptFormulae(inCellar: cellar) {
        case .success(let names): kept = names
        case .failure(let closed):
            let folder = closed.folder.abbreviatedPath
            return .nothingRuns(CommandResult(ending: .notRun, output: String(localized: "Peel couldn’t look inside \(folder) to tell which formulae your exclusions cover, so it ran nothing.")))
        }
        return await Homebrew.keepsEvery(kept) ? .formulae(kept) : .nothingRuns(keepsNothing)
    }

    private static func announce(_ words: LocalizedStringResource) {
        AccessibilityNotification.Announcement(AttributedString(localized: words)).post()
    }

    /// Said where Peel leaves upgrades to Terminal because Homebrew would clean up after them.
    static let cleansUp: LocalizedStringResource = "Homebrew cleans up after every upgrade, deleting old versions for good, so Peel leaves upgrades to Terminal."

    static let homebrewElsewhere: LocalizedStringResource = "Peel upgrades and uninstalls only with a Homebrew where Homebrew installs itself, and the one chosen in Settings is elsewhere. Copy the command, then run it in Terminal."

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
            return CommandResult(ending: .finished, output: written.isEmpty ? output : written)
        case .failure(let failure):
            return CommandResult(ending: .failed, output: written.isEmpty ? failure.output ?? "" : written)
        }
    }

    private func package(_ id: HomebrewPackage.ID) -> HomebrewPackage? {
        packages?.first { $0.id == id }
    }
}
