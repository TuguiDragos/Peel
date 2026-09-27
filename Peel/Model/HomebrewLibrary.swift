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

    /// Incremented only when the known casks or receipts change. An app's page scans again when it does, so a
    /// page opened before the evidence arrived picks it up, and a page the user is working on isn't scanned
    /// again for nothing.
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
    var selection: HomebrewPackage.ID?
    var result: CommandResult?

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

    /// What Upgrade All upgrades: the rest are shown as out of date and left alone (`joinsUpgradeAll`).
    var upgradable: [HomebrewPackage] {
        outdated.filter(\.joinsUpgradeAll)
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
        guard isInstalled else { return }
        guard let reading = await scanRun.run({ await self.read(includingReclaimable: includingReclaimable) }) else { return }
        guard let (found, installed, bytes) = reading else {
            needsDefinitions = true
            packages = packages ?? []
            return
        }
        // A failed reading is shown on the page, not stored in `result`, which would open a sheet the next time
        // the page is visited.
        switch installed {
        case .success(let list):
            packages = list
            couldNotRead = nil
        case .failure(let error):
            packages = packages ?? []
            couldNotRead = error.output
        }
        self.installation = found
        // Keeps the last figure when this reading brought none: one that was right a moment ago beats none.
        self.reclaimable = bytes ?? self.reclaimable
        revision += 1
        if let selection, packages?.contains(where: { $0.id == selection }) != true {
            self.selection = nil
        }
    }

    /// Nil while Homebrew has no local definitions to read, as when `brew update` has never run.
    private func read(includingReclaimable: Bool) async -> (HomebrewInstallation?, Result<[HomebrewPackage], Homebrew.CommandFailure>, Int64?)? {
        guard await Homebrew.hasLocalDefinitions() else { return nil }
        needsDefinitions = false
        // The installation is read first, since it says how to read the figures that follow. The other two
        // questions take about as long as each other, so they run at the same time.
        let found = await Homebrew.installation()
        async let reclaimable = includingReclaimable ? Homebrew.reclaimableBytes(asWrittenBy: found) : nil
        let installed: Result<[HomebrewPackage], Homebrew.CommandFailure>
        do {
            installed = .success(try await Homebrew.installedPackages())
        } catch {
            installed = .failure(error)
        }
        return (found, installed, await reclaimable)
    }

    /// Runs `command` and returns its result to the caller. Only one command runs at a time: while one runs,
    /// this returns nil at once. `showsResult` is false for a page that shows the result itself, so the
    /// Homebrew page opens no sheet about it later.
    @discardableResult
    func run(_ command: Command, showsResult: Bool = true) async -> CommandResult? {
        guard runningCommand == nil else { return nil }
        runningCommand = command
        defer { runningCommand = nil }
        let outcome = await outcome(of: command)
        if showsResult, let outcome { result = outcome }
        if !command.onlyLooks { await refresh(includingReclaimable: true) }
        return outcome
    }

    /// Nil for a command that only looks and keeps what it found in `findings` or `advisories`.
    private func outcome(of command: Command) async -> CommandResult? {
        if !command.onlyLooks {
            findings = nil
            advisories = nil
        }
        let gone = CommandResult(succeeded: false, output: String(localized: "Homebrew no longer lists this package."))
        do {
            let output: String
            switch command {
            case .upgrade(let id):
                guard let package = package(id) else { return gone }
                output = try await Homebrew.upgrade(package)
            case .upgradeAll:
                output = try await Homebrew.upgrade(upgradable)
            case .uninstall(let id):
                guard let package = package(id) else { return gone }
                output = try await Homebrew.uninstall(package)
            case .update:
                output = try await Homebrew.updateMetadata()
            case .cleanup:
                output = try await Homebrew.cleanup()
            case .health:
                // An older Homebrew answers only in prose, which is shown as written. `--json` is a hidden
                // switch, so an answer Peel can't read is asked for again in prose rather than shown as an error.
                guard installation?.reportsHealthAsJSON == true, let found = try? await Homebrew.health() else {
                    let report = await Homebrew.healthReport()
                    return CommandResult(succeeded: !report.isEmpty, output: report)
                }
                findings = found
                return nil
            case .vulnerabilities:
                advisories = try await Homebrew.vulnerabilities()
                return nil
            }
            return CommandResult(succeeded: true, output: output)
        } catch {
            return CommandResult(succeeded: false, output: error.output)
        }
    }

    private func package(_ id: HomebrewPackage.ID) -> HomebrewPackage? {
        packages?.first { $0.id == id }
    }
}
