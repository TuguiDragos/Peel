import Accessibility
import Foundation
import Observation
import PeelCore

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
        case health
        case vulnerabilities

        var onlyLooks: Bool {
            switch self {
            case .health, .vulnerabilities: true
            case .upgrade, .upgradeAll, .uninstall, .update, .cleanup: false
            }
        }

        /// An upgrade has no time limit, so its output is shown as it comes and the person can stop it.
        var isUpgrade: Bool {
            switch self {
            case .upgrade, .upgradeAll: true
            case .uninstall, .update, .cleanup, .health, .vulnerabilities: false
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
    /// Homebrew's output when the last reading failed, which is not the same as nothing being installed.
    private(set) var couldNotRead: String?
    private(set) var packages: [HomebrewPackage]?
    /// The installed Homebrew's version and prefix. The version decides what Peel may ask it for.
    private(set) var installation: HomebrewInstallation?
    /// What `brew cleanup` would free, as Homebrew reported it. Nil when it wouldn't say.
    private(set) var reclaimable: Int64?
    /// The formulae `brew cleanup` would uninstall for good because nothing needs them anymore.
    private(set) var autoremovable: [String] = []
    /// What Homebrew's own settings undo of how Peel runs it, read with the page and before an upgrade.
    private(set) var overrides: Homebrew.Overrides = []
    /// Homebrew has no local copy of its package definitions, for example because its cache was cleared (not
    /// by Peel: its Developer page leaves them alone). Any question would make Homebrew download them again,
    /// at launch and on every change in an Applications folder, which would be Peel contacting the network on
    /// its own. So nothing is asked.
    private(set) var needsDefinitions = false
    /// The findings of the last health check. Nil until one runs, and cleared by any command that changes
    /// Homebrew, since they would then describe it as it was.
    private(set) var findings: [HomebrewFinding]?
    private(set) var advisories: HomebrewVulnerabilityReport?
    /// Casks describing installed apps that Homebrew didn't install, read from its local definitions.
    private(set) var knownCasks: [HomebrewPackage] = []
    /// The identifiers of the installer receipts on the Mac. A cask that installs a package proves which app
    /// it is through its receipt.
    private(set) var receipts: Set<String> = []

    /// Everything Peel can use as evidence: what Homebrew installed, plus what it knows about the rest.
    var caskEvidence: [HomebrewPackage] {
        CaskEvidence.combined(installed: packages ?? [], known: knownCasks, receipts: receipts)
    }

    var knowsItsOwnApps: Bool { !isInstalled || hasAnswered }

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
    private(set) var runningCommand: Command?
    /// What Homebrew has written so far in the running upgrade. Nil when no upgrade runs.
    private(set) var progress: String?
    /// True once the person asked the running upgrade to stop.
    private(set) var isStopping = false
    private var runningTask: Task<CommandResult?, Never>?
    var selection: HomebrewPackage.ID?
    var result: CommandResult?

    /// Whether Homebrew answered the last reading, so its definitions are on this Mac.
    private(set) var hasAnswered = false

    var selectedPackage: HomebrewPackage? {
        packages?.first { $0.id == selection }
    }

    var outdated: [HomebrewPackage] {
        (packages ?? []).filter(\.isOutdated)
    }

    /// The packages Homebrew has disabled or deprecated, disabled first, since those can't be installed again.
    var retired: [HomebrewPackage] {
        let retired = (packages ?? []).filter { $0.retirement != nil }
        return retired.filter { $0.retirement?.stage == .disabled } + retired.filter { $0.retirement?.stage == .deprecated }
    }

    /// What Upgrade All upgrades: the rest are shown as out of date and left alone (`joinsUpgradeAll`), and all of
    /// them while Homebrew would clean up after an upgrade, which deletes old versions for good.
    var upgradable: [HomebrewPackage] {
        overrides.contains(.cleansUp) ? [] : outdated.filter(\.joinsUpgradeAll)
    }

    func count(of kind: HomebrewPackage.Kind) -> Int {
        (packages ?? []).count { $0.kind == kind }
    }

    /// Reads the installed packages again. `includingReclaimable` also asks how much `brew cleanup` would
    /// free, which only the Homebrew page shows. That is a Ruby command that walks the cache and the Cellar,
    /// so it is asked for only while that page is open or after a command, never on every change in
    /// `/Applications`.
    func refresh(includingReclaimable: Bool = false) async {
        isInstalled = Homebrew.executableURL != nil
        guard isInstalled else {
            forgetHomebrew()
            return
        }
        guard let reading = await scanRun.run({ await self.read(includingReclaimable: includingReclaimable) }),
              isInstalled
        else { return }
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
            packages = list
            hasAnswered = true
            couldNotRead = nil
        case .failure(let error):
            packages = packages ?? []
            hasAnswered = false
            couldNotRead = error.output
        }
        self.installation = found
        // Keeps the last figure when this reading brought none: one that was right a moment ago beats none.
        if let preview {
            reclaimable = preview.bytes ?? reclaimable
            autoremovable = preview.autoremoved
        }
        overrides = overridden ?? overrides
        revision += 1
        if let selection, packages?.contains(where: { $0.id == selection }) != true {
            self.selection = nil
        }
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
        // take about as long as each other, so they run at the same time. Only the page shows the last two.
        let found = await Homebrew.installation()
        let kept = found.map { ExclusionsStore.shared.exclusions.keptFormulae(inCellarOf: $0.prefix) } ?? []
        async let preview = includingReclaimable ? Homebrew.cleanupPreview(asWrittenBy: found, keeping: kept) : nil
        async let overridden = includingReclaimable ? Homebrew.overrides() : nil
        let installed: Result<[HomebrewPackage], Homebrew.CommandFailure>
        do {
            installed = .success(try await Homebrew.installedPackages())
        } catch {
            installed = .failure(error)
        }
        return (found, installed, await preview, await overridden)
    }

    /// Runs `command` and returns its result to the caller. Only one command runs at a time: while one runs,
    /// this returns nil at once. `showsResult` is false for a page that shows the result itself, so the
    /// Homebrew page opens no sheet about it later.
    @discardableResult
    func run(_ command: Command, showsResult: Bool = true) async -> CommandResult? {
        guard runningCommand == nil else { return nil }
        runningCommand = command
        defer {
            (runningCommand, runningTask, progress, isStopping) = (nil, nil, nil, false)
        }
        let task = Task { await outcome(of: command) }
        runningTask = task
        let outcome = await task.value
        if showsResult, let outcome { result = outcome }
        if !command.onlyLooks { await refresh(includingReclaimable: true) }
        return outcome
    }

    /// Stops the running upgrade: Homebrew is asked to stop, and killed if it does not.
    func stopUpgrade() {
        guard runningCommand?.isUpgrade == true else { return }
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
        do {
            let output: String
            switch command {
            case .upgrade(let id):
                guard let package = package(id) else { return gone }
                return await following { onOutput throws(Homebrew.CommandFailure) in try await Homebrew.upgrade(package, onOutput: onOutput) }
            case .upgradeAll:
                let packages = upgradable
                return await following { onOutput throws(Homebrew.CommandFailure) in try await Homebrew.upgrade(packages, onOutput: onOutput) }
            case .uninstall(let id):
                guard let package = package(id) else { return gone }
                guard let kept = await keptFormulae() else { return keepsNothing }
                output = try await Homebrew.uninstall(package, keeping: kept)
            case .update:
                output = try await Homebrew.updateMetadata()
            case .cleanup:
                guard let kept = await keptFormulae() else { return keepsNothing }
                output = try await Homebrew.cleanup(keeping: kept)
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
            return CommandResult(succeeded: false, output: error.output)
        }
    }

    private var keepsNothing: CommandResult {
        CommandResult(succeeded: false, output: String(localized: "Peel couldn’t make sure Homebrew keeps the formulae your exclusions cover, so it ran nothing. A brew.env file that sets HOMEBREW_NO_CLEANUP_FORMULAE replaces the list Peel gives it."))
    }

    /// The formulae the exclusions cover, which Homebrew is told to keep, asked again right before a command that
    /// deletes for good. Nil when Peel can't tell which they are or Homebrew's own settings replace the list.
    private func keptFormulae() async -> [String]? {
        guard let prefix = installation?.prefix else { return nil }
        let kept = ExclusionsStore.shared.exclusions.keptFormulae(inCellarOf: prefix)
        return await Homebrew.keepsEvery(kept) ? kept : nil
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
        let shown = Task {
            var written = Data()
            for await piece in pieces {
                written.append(piece)
                progress = String(decoding: written, as: UTF8.self)
            }
        }
        let outcome: Result<String, Homebrew.CommandFailure>
        do {
            outcome = .success(try await upgrade { sink.yield($0) })
        } catch {
            outcome = .failure(error)
        }
        sink.finish()
        await shown.value
        let written = progress ?? ""
        switch outcome {
        case .success(let output):
            return CommandResult(succeeded: true, output: written.isEmpty ? output : written)
        case .failure(let failure):
            return CommandResult(succeeded: false, output: written.isEmpty ? failure.output : written)
        }
    }

    private func package(_ id: HomebrewPackage.ID) -> HomebrewPackage? {
        packages?.first { $0.id == id }
    }
}
