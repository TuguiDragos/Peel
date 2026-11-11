import AppKit
import ArgumentParser
import Foundation
import PeelCore

struct AppsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "apps", abstract: "List installed apps.")

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let catalog = await AppCatalog.scan()
        let apps = catalog.apps
        if output.json {
            try Output.json(apps.map(AppRecord.init))
        } else {
            Output.table([["NAME", "VERSION", "IDENTIFIER", "PATH"]] + apps.map {
                [$0.name, $0.version ?? "", $0.bundleIdentifier ?? "", Output.path($0.url)]
            })
        }
        if let note = Output.unreadableNote(for: catalog) { Output.note(note) }
    }
}

struct InventoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inventory",
        abstract: "Write out what is installed and where each app came from.",
        discussion: "A Brewfile only lists what Homebrew can install again; everything else would be a line that doesn't work."
    )

    /// An enum, so `--help` lists the formats and the shell can complete them.
    @Option(help: "What to write. Without it, \(FormatArgument.text.rawValue).")
    var format: FormatArgument?

    var chosen: Inventory.Format { (format ?? .text).format }

    func run() async throws {
        guard chosen != .brewfile else {
            Output.write(try Inventory.build(apps: [], brewfile: try await Self.brewfile()).written(as: chosen))
            return
        }
        let catalog = await AppCatalog.scan()
        let inventory = Inventory.build(apps: catalog.apps, casks: await Self.casks(), origins: .onThisMac)
        Output.write(try inventory.written(as: chosen))
        if let note = Output.unreadableNote(for: catalog) { Output.note(note) }
    }

    /// Returns Homebrew's own Brewfile, or fails with why: an empty one would look like a success until someone
    /// uses it.
    private static func brewfile() async throws -> String {
        let why: String?
        if !(await Homebrew.hasLocalDefinitions()) {
            why = noDefinitions(
                isInstalled: Homebrew.executableURL != nil, unrunnable: HomebrewChoice().unrunnable(),
                refused: Homebrew.refusedInAUsualPlace()
            )
        } else if let installation = await Homebrew.installation() {
            do {
                return try await Homebrew.brewfile(from: installation)
            } catch {
                why = error.output
            }
        } else {
            why = "Homebrew didn't say which version it is."
        }
        throw CommandFailure(
            ["Homebrew didn't answer, so there is nothing to write a Brewfile from.", why].compactMap(\.self)
                .joined(separator: "\n")
        )
    }

    /// Returns the packages Homebrew installed, so an app it installed says so. When Homebrew can't answer, the
    /// list goes on without it and says why.
    private static func casks() async -> [HomebrewPackage] {
        let why: String?
        if await Homebrew.hasLocalDefinitions() {
            do {
                return try await Homebrew.installedPackages()
            } catch {
                why = error.output
            }
        } else {
            why = noDefinitions(
                isInstalled: Homebrew.executableURL != nil, unrunnable: HomebrewChoice().unrunnable(),
                refused: Homebrew.refusedInAUsualPlace()
            )
        }
        let isThere = HomebrewChoice().reading() != .nothingChosen || Homebrew.refusedInAUsualPlace() != nil
        if let note = homebrewNote(isInstalled: Homebrew.executableURL != nil || isThere, why: why) {
            Output.note(note)
        }
        return []
    }

    /// What a list other than a Brewfile says when Homebrew gave no packages: nothing on a Mac without Homebrew,
    /// and why otherwise.
    static func homebrewNote(isInstalled: Bool, why: String?) -> String? {
        guard isInstalled else { return nil }
        return ["Homebrew didn't answer, so no app is marked as installed by it.", why].compactMap(\.self)
            .joined(separator: "\n")
    }

    /// Why Homebrew was not asked: without its local copy of the definitions it would download them. The copy is
    /// missing because Homebrew isn't installed, or because it never fetched one.
    static func noDefinitions(
        isInstalled: Bool, unrunnable: HomebrewChoice.Unrunnable? = nil, refused: HomebrewChoice.Unrunnable? = nil
    ) -> String {
        if let unrunnable {
            guard let brew = unrunnable.brew else {
                return "Peel can't read which brew is chosen in its Settings, so it runs none."
            }
            return "Peel runs only the brew chosen in its Settings, \(brew.path(percentEncoded: false)), and that one can't be run."
        }
        if let refused, let brew = refused.brew {
            let owner = switch refused.refusal {
            case .ownedByAnotherAccount(let owner?): "the account \(Output.plain(owner)) owns it"
            case .ownedByAnotherAccount(nil): "another account owns it"
            default: "anyone on this Mac can change it"
            }
            return "Peel doesn't run the brew in \(brew.path(percentEncoded: false)): \(owner)."
        }
        return isInstalled ? "Homebrew has no list of packages on this Mac. Run `brew update` first." : "Homebrew isn't installed."
    }
}

struct LeftoversCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "leftovers",
        abstract: "Show the files an app leaves behind.",
        discussion: "APP can be the path to the app, its bundle identifier, or its name. A bundle in the current folder is written ./Name.app."
    )

    @Argument(help: "The app to inspect.")
    var app: String

    @Flag(help: "Include files that need review before removing them.")
    var all = false

    @OptionGroup var output: OutputOptions

    static func inTheTrash(_ app: InstalledApp) -> String {
        "\(Output.plain(app.name)) is already in the Trash. What it left behind can still be moved."
    }

    struct Report: Encodable {
        let app: AppRecord
        /// Nil when the app bundle couldn't be measured. Written as `null`, never left out, so a script always
        /// finds the key.
        let appSize: Int64?
        let leftovers: [LeftoverRecord]
        let needsReview: Int
        let unreadableLocations: [String]
        let needsFullDiskAccess: Bool
        let cutShortLocations: [String]
        /// Why `peel uninstall` would leave the app itself where it is, or `null` when it would move it. While the app
        /// stays, none of its files moves.
        let appStays: String?

        init(
            app: InstalledApp, appSize: Int64?, leftovers: [Leftover], scan: LeftoverScan, appStays: String?
        ) {
            self.app = AppRecord(app)
            self.appSize = appSize
            self.leftovers = leftovers.map(LeftoverRecord.init)
            needsReview = scan.leftovers.count { !$0.match.isRecommended }
            unreadableLocations = scan.unreadableLocations.map { Output.path($0.url) }
            needsFullDiskAccess = scan.needsFullDiskAccess
            cutShortLocations = scan.cutShortLocations.map { Output.path($0.url) }
            self.appStays = appStays
        }

        private enum CodingKeys: String, CodingKey {
            case app
            case appSize
            case leftovers
            case needsReview
            case unreadableLocations
            case needsFullDiskAccess
            case cutShortLocations
            case appStays
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(app, forKey: .app)
            try container.encode(appSize, forKey: .appSize)
            try container.encode(leftovers, forKey: .leftovers)
            try container.encode(needsReview, forKey: .needsReview)
            try container.encode(unreadableLocations, forKey: .unreadableLocations)
            try container.encode(needsFullDiskAccess, forKey: .needsFullDiskAccess)
            try container.encode(cutShortLocations, forKey: .cutShortLocations)
            try container.encode(appStays, forKey: .appStays)
        }
    }

    func run() async throws {
        let apps = AppLookup.apps(from: await AppCatalog.scan())
        let target = try AppLookup.app(matching: app, in: apps)
        let exclusions = await ExclusionStore().load()
        try AppLookup.refuseIfExcluded(target, by: exclusions)
        let homebrew = await CaskLookup.evidence(for: [target])
        let uninstallation = await ProgressLine.counting {
            await Uninstallation.prepare(
                target,
                installedApps: apps,
                exclusions: exclusions,
                casks: homebrew.casks,
                receipts: homebrew.receipts
            )
        }
        let leftovers = uninstallation.scan.leftovers.filter { all || $0.match.isRecommended }
        // In the order `peel uninstall` finds it.
        var stays = await UninstallCommand.whileRunning(target, among: apps)?.description
            ?? UninstallCommand.whyItStays(uninstallation)?.description
        if stays == nil, let refusal = await UninstallCommand.refusalOfTheMove(
            of: uninstallation, by: TrashService(exclusions: exclusions)
        ) {
            stays = UninstallCommand.wontMove(target, because: refusal)
        }

        // Printed in JSON mode too, on standard error, so a script that reads an empty list still learns what
        // was left out or couldn't be checked.
        if let stays {
            Output.note("\(stays) While it stays, `peel uninstall` moves none of its files.")
        }
        if uninstallation.isAppInTheTrash {
            Output.note(Self.inTheTrash(target))
        }
        let hidden = uninstallation.scan.leftovers.count - leftovers.count
        Self.notes(uninstallation, homebrew: homebrew, hidden: leftovers.isEmpty && !output.json ? 0 : hidden)
        if output.json {
            let appSize = uninstallation.isAppMeasured ? uninstallation.appSize : nil
            let report = Report(
                app: target, appSize: appSize, leftovers: leftovers, scan: uninstallation.scan,
                appStays: stays
            )
            try Output.json(report)
            return
        }
        let appSize = uninstallation.isAppMeasured ? Output.size(uninstallation.appSize) : "unknown"
        Output.line("\(target.name) \(target.version ?? "")  \(appSize)  \(Output.path(target.url))")
        if leftovers.isEmpty {
            Output.line(Self.whenNothingIsShown(hidden: hidden))
        } else {
            Output.line()
            Output.table(leftovers.map { [Output.size(Self.measured($0)), Output.path($0.url), Self.summary(of: $0)] })
        }
    }

    static func whenNothingIsShown(hidden: Int) -> String {
        guard hidden > 0 else { return "No leftovers found." }
        let them = hidden == 1 ? "it" : "them"
        return "No leftovers Peel suggests. \(Output.count(hidden, "file needs", "files need")) review. Add --all to see \(them)."
    }

    /// Describes `leftover` in one line: why it matched, why it needs review when it isn't suggested (held
    /// back, shared with other apps, or only a possible match), and whether it needs administrator access.
    static func summary(of leftover: Leftover) -> String {
        var summary = leftover.match.reason.summary
        if let heldBack = leftover.match.heldBack {
            summary += ", review: \(heldBack.summary(keptInStepBy: leftover.syncedBy))"
        } else if !leftover.match.isRecommended {
            let users = leftover.match.sharedWith + leftover.match.otherCopies.map(Output.path)
            summary += leftover.match.isShared
                ? ", review: shared with \(users.joined(separator: ", "))"
                : ", review: \(leftover.match.confidence.summary) match"
        }
        if leftover.requiresPrivileges {
            summary += ", needs administrator access"
        }
        if let leadsTo = leftover.leadsTo {
            summary += ", a link to \(Output.path(leadsTo))"
        }
        return summary
    }

    /// Returns the size of `leftover`, or nil when it couldn't be measured: its size is then unknown, not zero.
    static func measured(_ leftover: Leftover) -> Int64? {
        leftover.isMeasured ? leftover.size : nil
    }

    private static func notes(_ uninstallation: Uninstallation, homebrew: CaskLookup.Answer, hidden: Int) {
        if hidden > 0 {
            Output.note("\(Output.count(hidden, "more file needs", "more files need")) review. Add --all to see them.")
        }
        if let note = homebrew.note {
            Output.note(note)
        }
        if !uninstallation.scan.unreadableLocations.isEmpty {
            let scan = uninstallation.scan
            let folders = scan.unreadableLocations.map(\.url)
            Output.note(Output.unreadableNote(for: folders, needsFullDiskAccess: scan.needsFullDiskAccess))
        }
        for location in uninstallation.scan.cutShortLocations {
            Output.note("There are more folders in \(Output.plain(Output.path(location.url))) than Peel looks inside, so something of this app's may be in a folder Peel didn't reach.")
        }
    }
}

struct UninstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Move an app and its leftovers to the Trash.",
        discussion: """
            Only leftovers Peel suggests are included. Items that need administrator access stay where they \
            are: the Peel app moves those its helper may move, and once the app is in the Trash, Orphaned Files \
            in the Peel app lists the rest under Needs an Administrator, with how to remove them in Finder.
            The app moves first, and if it can't move, none of its files do. Answering \
            no exits with code 2; a removal that couldn't finish exits 1, and so does a privacy reset that \
            didn't happen.
            """
    )

    @Argument(help: "The app to remove: its path, bundle identifier, or name. Write ./Name.app for a bundle in the current folder.")
    var app: String

    @Flag(help: "Move only the app, not its leftovers.")
    var keepLeftovers = false

    @Flag(help: "Also reset the app's privacy permissions, just before it moves, so it asks again if you reinstall it. The Trash can't bring them back.")
    var resetPrivacy = false

    @Flag(help: "Show what would move without moving anything.")
    var dryRun = false

    @Flag(help: "Leave the app's icon in the Dock. Without it, the icon comes out once the app is in the Trash, and goes back where it was if the app is put back.")
    var keepInDock = false

    @Flag(name: .shortAndLong, help: "Don't ask for confirmation.")
    var yes = false

    @OptionGroup var output: OutputOptions

    /// What `--json` writes once the command is done.
    struct Report: Encodable {
        struct Item: Encodable {
            let path: String
            let size: MeasuredSize
            /// Why the item stays, in the words `peel history --refused` uses, or `null` when it moves.
            let stays: String?
            /// Where the item leads when it is a symbolic link, which moving it leaves in place, or `null`.
            var leadsTo: String?

            private enum CodingKeys: String, CodingKey {
                case path
                case size
                case stays
                case leadsTo
            }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(path, forKey: .path)
                try container.encode(size, forKey: .size)
                try container.encode(stays, forKey: .stays)
                try container.encode(leadsTo, forKey: .leadsTo)
            }
        }

        struct Failure: Encodable {
            let path: String
            let reason: String
            let detail: String?

            private enum CodingKeys: String, CodingKey {
                case path
                case reason
                case detail
            }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(path, forKey: .path)
                try container.encode(reason, forKey: .reason)
                try container.encode(detail, forKey: .detail)
            }
        }

        let app: AppRecord
        let dryRun: Bool
        let items: [Item]
        let moved: [String]
        let failed: [Failure]
        /// Whether the privacy permissions were reset, or `null` when that wasn't asked for or it was a dry run.
        let privacyReset: Bool?
        /// Whether the app itself went to the Trash, or `null` for a dry run.
        let appMoved: Bool?
        let needsAdministrator: Int
        let needsReview: Int
        let leftForAnAdministrator: Int
        let unreadableLocations: [String]
        let needsFullDiskAccess: Bool
        let cutShortLocations: [String]
        /// Why the app itself would stay, which only a dry run reports: a real run refuses instead.
        let appStays: String?
        let shellReferences: [ShellReference]
        /// Why the app's icon stayed in the Dock, or `null` when it went, wasn't there, or was kept.
        let dockIconStayed: String?

        struct ShellReference: Encodable {
            let file: String
            let line: Int
        }

        private enum CodingKeys: String, CodingKey {
            case app
            case dryRun
            case items
            case moved
            case failed
            case privacyReset
            case appMoved
            case needsAdministrator
            case needsReview
            case leftForAnAdministrator
            case unreadableLocations
            case needsFullDiskAccess
            case cutShortLocations
            case appStays
            case shellReferences
            case dockIconStayed
        }

        /// Encodes an unknown `privacyReset` and `appMoved` as `null`, for the reason `AppRecord` gives.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(app, forKey: .app)
            try container.encode(dryRun, forKey: .dryRun)
            try container.encode(items, forKey: .items)
            try container.encode(moved, forKey: .moved)
            try container.encode(failed, forKey: .failed)
            try container.encode(privacyReset, forKey: .privacyReset)
            try container.encode(appMoved, forKey: .appMoved)
            try container.encode(needsAdministrator, forKey: .needsAdministrator)
            try container.encode(needsReview, forKey: .needsReview)
            try container.encode(leftForAnAdministrator, forKey: .leftForAnAdministrator)
            try container.encode(unreadableLocations, forKey: .unreadableLocations)
            try container.encode(needsFullDiskAccess, forKey: .needsFullDiskAccess)
            try container.encode(cutShortLocations, forKey: .cutShortLocations)
            try container.encode(appStays, forKey: .appStays)
            try container.encode(shellReferences, forKey: .shellReferences)
            try container.encode(dockIconStayed, forKey: .dockIconStayed)
        }
    }

    /// The report `--json` writes. `result` is nil for a dry run, which moved nothing.
    static func report(
        app: InstalledApp,
        plan: UninstallPlan,
        result: TrashResult?,
        privacy: PrivacyReset.Result?,
        scan: LeftoverScan,
        appStays: String? = nil,
        shellReferences: [ShellReferences.Reference] = [],
        dockIconStayed: DockTiles.Stayed.Reason? = nil
    ) -> Report {
        Report(
            app: AppRecord(app),
            dryRun: result == nil,
            items: plan.items.map { item in
                Report.Item(
                    path: Output.path(item.url), size: MeasuredSize(item.size), stays: plan.whyItStays(item)?.word,
                    leadsTo: item.leadsTo.map(Output.path)
                )
            },
            moved: (result?.trashed ?? []).map { Output.path($0.originalURL) },
            failed: (result?.failures ?? []).map {
                Report.Failure(path: Output.path($0.url), reason: $0.reason.name, detail: $0.reason.detail)
            },
            privacyReset: privacy.map { $0 == .reset },
            appMoved: result.map { result in result.trashed.contains { $0.originalURL == plan.app } },
            needsAdministrator: plan.needsAdministrator,
            needsReview: plan.needsReview,
            leftForAnAdministrator: plan.leftForAnAdministrator,
            unreadableLocations: scan.unreadableLocations.map { Output.path($0.url) },
            needsFullDiskAccess: scan.needsFullDiskAccess,
            cutShortLocations: scan.cutShortLocations.map { Output.path($0.url) },
            appStays: appStays,
            shellReferences: shellReferences.map { Report.ShellReference(file: Output.path($0.file), line: $0.line) },
            dockIconStayed: dockIconStayed?.rawValue
        )
    }

    func validate() throws {
        if !yes, !dryRun {
            try Output.requireConfirmable()
        }
    }

    /// Throws while the app or one of its helpers is running: a process left running writes its settings
    /// again right after they move to the Trash.
    private static func refuseWhileRunning(_ target: InstalledApp, among apps: [InstalledApp]) async throws {
        if let failure = await whileRunning(target, among: apps) { throw failure }
    }

    static func whileRunning(_ target: InstalledApp, among apps: [InstalledApp]) async -> CommandFailure? {
        let belonging = await RunningCopies.belonging(to: target, among: RunningCopies.current, installedApps: apps)
        guard !belonging.isEmpty else { return nil }
        let jobs = await RunningCopies.keptRunningByJobs(inside: [target.url])
        let running = belonging.filter { !jobs.contains($0.identifier) && !$0.isAnExtension(inside: target.url) }
        guard !running.isEmpty else { return nil }
        let identifiers = Set(running.compactMap { $0.bundleIdentifier ?? $0.bundleURL.map(Output.path) })
            .sorted().map(Output.plain)
        return CommandFailure("Quit \(Output.plain(target.name)) first. Still running: \(identifiers.joined(separator: ", ")).")
    }

    /// Why the move would leave the app itself where it is now, by every check it makes, a program running from the
    /// bundle among them, or nil when it would move.
    static func refusalOfTheMove(
        of uninstallation: Uninstallation, by service: TrashService
    ) async -> TrashFailure.Reason? {
        let app = uninstallation.app.url
        let running: Set<URL> = uninstallation.uninstallsItself?.letsItsProgramsRun == true ? [app] : []
        return await service.refusalsNow(ofApps: [app], lettingTheirProgramsRun: running)[app]
    }

    static func wontMove(_ app: InstalledApp, because reason: TrashFailure.Reason) -> String {
        "Peel won't move \(Output.plain(Output.path(app.url))): \(reason.summary)."
    }

    /// Whether the app's icon comes out of the Dock: once the app itself is in the Trash, unless `--keep-in-dock`.
    static func takesOutDockIcon(of app: InstalledApp, after result: TrashResult, keeping: Bool) -> Bool {
        guard !keeping else { return false }
        return TrashService.isInsideATrash(app.url) ? !result.trashed.isEmpty
            : result.trashed.contains { $0.originalURL == app.url }
    }

    /// What the plan says about the app's icon in the Dock, which History puts back with the app.
    static func dockNote(for app: InstalledApp, isInTheDock: Bool, keeping: Bool) -> String? {
        guard isInTheDock, !keeping else { return nil }
        return "Peel takes \(Output.plain(app.name))'s icon out of the Dock once it is in the Trash, and puts it back if you put the app back. Add --keep-in-dock to leave it."
    }

    /// Why the app's icon stayed in the Dock after it moved.
    static func dockStayedNote(for app: InstalledApp, reason: DockTiles.Stayed.Reason) -> String {
        let name = Output.plain(app.name)
        return switch reason {
        case .notRemembered:
            "The Dock still shows \(name): Peel takes an icon out only once it has saved where to put it back, and it couldn't save that."
        case .notSaved: "The Dock still shows \(name): macOS didn't save the change to the Dock."
        }
    }

    /// The lines of the shell startup files that still name what moved, which the person edits and Peel never does.
    static func shellNote(for references: [ShellReferences.Reference]) -> String {
        let places = references.map { "\(Output.plain(Output.path($0.file))):\($0.line)" }.joined(separator: ", ")
        return "Your shell startup files still name what moved, at \(places). If a new shell shows an error, remove or change those lines: Peel reads them and never changes them."
    }

    /// What macOS still starts from the Trash once the app moved: its background items, at each login.
    static func startsFromTheTrashNote(for app: InstalledApp, after result: TrashResult) -> String? {
        guard result.startsFromTheTrash.contains(app.url) else { return nil }
        return "macOS still starts the background items of \(Output.plain(app.name)) from the Trash each time you log in, until you empty the Trash. System Settings > General > Login Items & Extensions can turn them off."
    }

    /// What would stop the move now, as a note on a dry run, which moves nothing, and as the refusal otherwise.
    static func note(for failure: (any Error & CustomStringConvertible)?, dryRun: Bool) throws -> String? {
        guard let failure else { return nil }
        guard dryRun else { throw failure }
        return failure.description
    }

    /// What the plan says of a browser's web app, whose shortcut is all that moves: the app stays in the browser.
    static func webAppNote(for app: InstalledApp, browserName: String) -> String? {
        guard case .browser = app.webApp else { return nil }
        let name = Output.plain(app.name)
        let browser = Output.plain(browserName)
        return "\(name) is a web app of \(browser). Moving it takes away only this shortcut, and the app stays in \(browser), which can make the shortcut again. To remove the app itself, uninstall it in \(browser), which takes the shortcut away too."
    }

    /// The name of the browser a web app of `app`'s kind belongs to, as the Finder shows it.
    static func browserName(of app: InstalledApp, among apps: [InstalledApp]) -> String? {
        guard case .browser(let identifier) = app.webApp else { return nil }
        return apps.first { $0.bundleIdentifier == identifier }?.name
            ?? AppInspector.knownName(forBundleIdentifier: identifier)
    }

    /// Said after a command that runs `sudo`, on an account that isn't an administrator's.
    static let administratorRunsIt = "This account isn't an administrator, so an administrator runs this command, or you run it after `su` and an administrator's short name."

    /// What the removal does that the Trash can't bring back, and what the app leaves behind, said before the question.
    static func warnings(
        moving urls: Set<URL>,
        of app: InstalledApp,
        uninstallsItself: UninstallsItself?,
        leftInTheSystem: LeftInTheSystem?,
        commandToRunFirst: CommandToRunFirst?,
        resettingPrivacy: Bool,
        isAdministrator: Bool = PrivilegedHelper.isAdministrator
    ) -> [String] {
        var warnings: [String] = []
        if resettingPrivacy {
            warnings.append("Peel resets \(app.name)'s privacy permissions just before it moves. The Trash can't bring them back.")
        }
        if let app = uninstallsItself, urls.contains(app.app.url) {
            switch app.uninstaller {
            case .logsOut(let script):
                warnings.append("Once \(app.app.name) leaves the Applications folder, its own service uninstalls it: it logs this Mac out of the account and deletes its settings, which the Trash can't bring back. Write down the account number first, or run its own uninstaller instead: \(script)")
            case .deletesTheApp:
                warnings.append("Once \(app.app.name) leaves the Applications folder, its own uninstaller opens and asks for an administrator's password. If you continue there, it deletes the app, even from the Trash, and its system files, which the Trash can't bring back.")
            case .removesItsComponents:
                warnings.append("Once \(app.app.name) leaves the Applications folder, its own uninstaller opens and asks to remove the components it keeps in the system. If you continue there, it deletes them, which the Trash can't bring back.")
            case .deletesItsSuite:
                warnings.append("Once \(app.app.name) leaves the Applications folder, the cleanup BlueStacks installs runs as an administrator. It deletes the other BlueStacks app if it's still in the Applications folder and the data BlueStacks keeps for every account in /Users/Shared, which the Trash can't bring back, and signs you out of now.gg unless BlueAI is installed.")
            case .uninstallsWithoutAsking:
                warnings.append("Once \(app.app.name) leaves the Applications folder, its own service uninstalls it as an administrator, without asking: it deletes its system files and can delete the app from the Trash too, which the Trash can't bring back. Then NoMachine Uninstall opens and asks for an administrator's password to delete the accounts NoMachine made.")
            case .watchedByAJob:
                warnings.append("Moving \(app.app.name) to the Trash starts a program that waits for it to leave. Peel leaves that program and the file that starts it in place so it can finish, and the Trash can't bring back anything it removes.")
            }
        }
        if urls.contains(app.url), let root = TrustedRoot.of(app) {
            let step = switch root.step {
            case .command(let command): "run `\(command)` first"
            case .menu(let menu): "choose \(menu) in \(app.name) first"
            case .keychainAccess:
                "open the certificate whose name begins with \(root.certificate) in Keychain Access and change its trust settings"
            }
            warnings.append("\(app.name)'s root certificate stays trusted on this Mac after the app goes. To stop trusting it, \(step).")
        }
        if urls.contains(app.url), let first = commandToRunFirst {
            switch first.undoes {
            case .chargingLimit:
                warnings.append("\(app.name) may have paused this Mac's charging at a limit. Before it goes, run `\(first.command)`, which turns charging back on and removes its tools from /usr/local/bin.")
            }
        }
        if urls.contains(app.url), let left = leftInTheSystem {
            let rule = left.ruleForSudo.map {
                " \($0) is a rule that lets anyone run the programs it names as an administrator, without a password."
            } ?? ""
            let them = left.paths.count == 1 ? "it" : "them"
            let who = AdministratorCommand.needsAnAdministrator(left.command, isAdministrator: isAdministrator)
                ? " " + administratorRunsIt : ""
            warnings.append("\(app.name) leaves \(Output.list(left.paths)) on this Mac after it goes, which only an administrator can remove.\(rule) To remove \(them), run `\(left.command)`.\(who)")
        }
        return warnings
    }

    /// Why the app itself can't move: macOS keeps another developer's app from a terminal without App Management,
    /// which the person can allow, while an app in a folder they can't write to needs an administrator, whom the Peel
    /// app asks through its helper, or Finder where the helper can't move it.
    static func whyItCannotMove(
        _ app: InstalledApp,
        isProtectedByPrivacy: Bool,
        isBeyondTheHelper: Bool
    ) -> CommandFailure {
        let name = Output.plain(app.name)
        if isProtectedByPrivacy {
            return CommandFailure("macOS lets your terminal app move \(name) only with App Management. Allow it in System Settings > Privacy & Security > App Management, then try again, or remove it with the Peel app.")
        }
        guard !isBeyondTheHelper else {
            return CommandFailure("Moving \(name) to the Trash needs administrator access, and Peel's helper can't move it from there. Move it to the Trash in Finder, which asks for an administrator's password.")
        }
        return CommandFailure("Moving \(name) to the Trash needs administrator access. Remove it with the Peel app.")
    }

    /// Why `peel uninstall` leaves the app itself where it is, in the words it says it, or nil when it moves it.
    static func whyItStays(_ uninstallation: Uninstallation) -> CommandFailure? {
        let app = uninstallation.app
        if let refusal = removedElsewhere(app, installedSystemExtensions: uninstallation.installedSystemExtensions)
            ?? keptByMacOS(app) ?? partOfAnotherPackage(app) {
            return refusal
        }
        guard uninstallation.appRequiresPrivileges else { return nil }
        return whyItCannotMove(
            app,
            isProtectedByPrivacy: FileAccess.isProtectedByPrivacy(app.url),
            isBeyondTheHelper: uninstallation.isAppBeyondTheHelper
        )
    }

    /// Why an app removed elsewhere never moves with `peel`, or nil for any other app. Peel removes itself from its own
    /// Settings, after unregistering its login item and privileged helper: if `peel` moved the app, the helper would
    /// stay registered with launchd and point into the Trash. An agent goes by its maker's uninstaller, which also
    /// takes what it keeps in the system.
    static func removedElsewhere(
        _ target: InstalledApp,
        installedSystemExtensions: CarriedSystemExtensions = .none,
        isAdministrator: Bool = PrivilegedHelper.isAdministrator
    ) -> CommandFailure? {
        switch RemovedElsewhere.of(target, installedSystemExtensions: installedSystemExtensions) {
        case nil:
            return nil
        case .byRemovePeel:
            return CommandFailure("Peel removes itself from its own settings, which unregisters the helper first. Open Peel and click Remove Peel in Settings.")
        case .byItsMaker(let uninstaller) where uninstaller.removes != nil:
            let product = Output.plain(uninstaller.removes ?? "")
            return CommandFailure("\(Output.plain(target.name)) is \(uninstaller.maker)'s uninstaller for \(product): open it, and it removes \(product) and then itself. See \(uninstaller.instructions.absoluteString)")
        case .byItsMaker(let uninstaller):
            let step = switch uninstaller.step {
            case .command(let command): "run `\(command)`"
            case .uninstaller(let url): "open \(Output.plain(Output.path(url)))"
            case .inTheApp: "use the uninstall command in \(Output.plain(target.name))"
            case .onItsDiskImage: "use the uninstaller on the disk image it came on"
            case .fromTheMakersPage: "download its uninstaller from \(uninstaller.maker)'s page"
            case .notOnTheMac: "follow \(uninstaller.maker)'s instructions, since the uninstaller they name isn't on this Mac"
            }
            let who = if case .command(let command) = uninstaller.step,
                         AdministratorCommand.needsAnAdministrator(command, isAdministrator: isAdministrator) {
                " " + administratorRunsIt
            } else {
                ""
            }
            return CommandFailure("\(Output.plain(target.name)) is removed with \(uninstaller.maker)'s own uninstaller, which also takes what it keeps in the system: \(step). See \(uninstaller.instructions.absoluteString)\(who)")
        case .byFinder(let carried) where !carried.isKnown:
            return CommandFailure("Peel can't look inside \(Output.plain(target.name)) to see which system extensions it carries, and macOS removes those only when the app goes to the Trash in Finder. Move the app to the Trash in Finder.")
        case .byFinder(let carried):
            let names = carried.names
            let extensions = names.map(Output.plain).joined(separator: ", ")
            let (what, them, stays, beside) = names.count == 1
                ? ("a system extension", "it", "it stays", "it") : ("system extensions", "them", "they stay", "each")
            let settings = carried.systemSettingsDeletesThem
                ? " If \(stays), in System Settings > General > Login Items & Extensions, choose By Category, click the Info button beside Network Extensions, then click the More button beside \(beside) and choose Delete Extension."
                : ""
            return CommandFailure("macOS installed \(what) that came with \(Output.plain(target.name)) (\(extensions)), and only macOS can remove \(them). Move the app to the Trash in Finder, which asks macOS to remove \(them).\(settings)")
        case .onceItsSystemExtensionsAreOff(let carried):
            let names = carried.inAnAppInside
            let extensions = names.map(Output.plain).joined(separator: ", ")
            let name = Output.plain(target.name)
            let (what, them) = names.count == 1 ? ("a system extension", "it") : ("system extensions", "them")
            let why = carried.keepsTheAppInPlace && names.count == 1
                ? "While \(extensions) runs, it keeps \(name) from being moved, by Finder, by peel, or by an administrator."
                : "macOS runs \(what) for an app inside \(name) (\(extensions)), and no move of the app removes \(them): Finder asks macOS to remove only the extensions in the app's own folder."
            return CommandFailure("\(why) Turn \(them) off first in System Settings > General > Login Items & Extensions, then run this again.")
        }
    }

    static func keptByMacOS(_ target: InstalledApp) -> CommandFailure? {
        guard target.isSystemProtected else { return nil }
        return CommandFailure("macOS protects \(Output.plain(target.name)), so it can't be removed.")
    }

    /// Why an app inside another package, such as a helper app inside the app it serves, never moves on its own: it
    /// would be cut out of that package. Nil for any other app.
    static func partOfAnotherPackage(_ target: InstalledApp) -> CommandFailure? {
        guard let package = target.enclosingPackage else { return nil }
        let name = Output.plain(AppInspector.displayName(of: package))
        return CommandFailure("\(Output.plain(target.name)) is part of \(name), so it can't be removed on its own.")
    }

    /// Throws when Peel never resets the privacy permissions of `target`. Called for `--reset-privacy` before
    /// anything is listed: skipping the reset quietly would remove the app and leave its permissions on record.
    static func refuseIfPrivacyCannotBeReset(_ target: InstalledApp) throws {
        guard !TrashService.isInsideATrash(target.url) else {
            throw CommandFailure("macOS can't reset the privacy permissions of an app in the Trash. Leave out --reset-privacy, or put it back first.")
        }
        guard !PrivacyReset.isAllowed(for: target) else { return }
        throw CommandFailure("Peel never resets privacy permissions for \(Output.plain(target.name)). Leave out --reset-privacy to remove it anyway.")
    }

    /// Refuses a privacy reset while another copy of the app stays: macOS keeps one set of permissions for every copy,
    /// so resetting them for this one would reset them for that one too.
    static func refuseIfPrivacyIsShared(of target: InstalledApp, withCopies copies: [URL]) throws {
        guard let copy = copies.first else { return }
        throw CommandFailure("Another copy of \(Output.plain(target.name)) stays at \(Output.plain(Output.path(copy))), and macOS keeps one set of privacy permissions for every copy, so resetting them would reset that copy's too. Leave out --reset-privacy to remove this one.")
    }

    /// Returns the line that reports the privacy reset, and whether it is a warning the command fails with: a reset
    /// that did not happen, or one for an app that then stayed (`PrivacyReset.worthTelling`).
    static func privacyOutcome(
        _ result: PrivacyReset.Result, app: InstalledApp, after removal: TrashResult
    ) -> (line: String, failed: Bool) {
        let name = Output.plain(app.name)
        guard result == .reset else { return ("\(name)'s privacy permissions weren't reset: \(result.summary).", true) }
        guard PrivacyReset.worthTelling([(app, result)], after: removal).isEmpty else {
            let stayed = "\(name) stayed where it is, so it will ask for them again"
            return ("Reset \(name)'s privacy permissions, but \(stayed).", true)
        }
        return ("Reset \(name)'s privacy permissions.", false)
    }

    func run() async throws {
        let apps = AppLookup.apps(from: await AppCatalog.scan())
        let target = try AppLookup.app(matching: app, in: apps)
        if !dryRun {
            let carried = await AppExtensions.installed(carriedBy: target)
            if let refusal = Self.removedElsewhere(target, installedSystemExtensions: carried)
                ?? Self.keptByMacOS(target) ?? Self.partOfAnotherPackage(target) {
                throw refusal
            }
        }
        if resetPrivacy {
            try Self.refuseIfPrivacyCannotBeReset(target)
        }
        let exclusions = await ExclusionStore().load()
        let excluded = try Self.note(for: AppLookup.refusal(of: target, by: exclusions), dryRun: dryRun)
        let service = TrashService(exclusions: exclusions)
        let running = try Self.note(for: await Self.whileRunning(target, among: apps), dryRun: dryRun)
        let homebrew = await CaskLookup.evidence(for: [target])
        let uninstallation = await ProgressLine.counting {
            await Uninstallation.prepare(
                target,
                installedApps: apps,
                exclusions: exclusions,
                casks: homebrew.casks,
                receipts: homebrew.receipts
            )
        }
        if resetPrivacy {
            try Self.refuseIfPrivacyIsShared(of: target, withCopies: uninstallation.otherCopies)
        }
        let access = try Self.note(for: Self.whyItStays(uninstallation), dryRun: dryRun)
        let inTheTrash = uninstallation.isAppInTheTrash ? LeftoversCommand.inTheTrash(target) : nil
        [excluded, running, access, inTheTrash].compactMap(\.self).forEach(Output.note)

        if let note = UnreadableHistory.note() {
            Output.note(note)
        }
        // The removal guard judges each item before printing, and the app gets every check its move makes, so the list
        // shows what the move will really do.
        let appRefusal = await Self.refusalOfTheMove(of: uninstallation, by: service)
        let plan = UninstallPlan.make(uninstallation, keepLeftovers: keepLeftovers) { url in
            url == target.url ? appRefusal : service.refusal(of: url)
        }
        let wontMove = plan.appStays.map { Self.wontMove(target, because: $0) }
        if let wontMove {
            guard dryRun else {
                _ = await plan.record(TrashResult(), from: target.name)
                throw CommandFailure("\(wontMove) Nothing of \(Output.plain(target.name)) was touched.")
            }
            Output.note("\(wontMove) While it stays, none of its files moves.")
        }
        if !output.json {
            // The third column appears only when some item stays, so an ordinary list has no trailing spaces.
            let saysWhy = plan.moving.count < plan.items.count
            if !plan.items.isEmpty {
                Output.table(plan.items.map { item in
                    let stays = plan.whyItStays(item).map { "stays: \($0.summary)" }
                    return [Output.size(item.size), Output.path(item.url)] + (saysWhy ? [stays ?? "moves"] : [])
                })
            }
            Output.line(plan.moving.isEmpty ? "Nothing here can be moved." : "Total: \(Output.size(plan.total))")
            for item in plan.moving {
                if let leadsTo = item.leadsTo {
                    Output.note("\(Output.path(item.url)) is a link to \(Output.path(leadsTo)): only the link moves.")
                }
            }
        }
        let isInTheDock = !(await DockTiles().holding([target.url])).isEmpty
        // With `--json`, standard output is the report alone, so the warnings go where the notes go.
        if !plan.moving.isEmpty {
            let moving = Set(plan.moving.map(\.url))
            let warnings = Self.warnings(
                moving: moving, of: target, uninstallsItself: uninstallation.uninstallsItself,
                leftInTheSystem: uninstallation.leftInTheSystem, commandToRunFirst: uninstallation.commandToRunFirst,
                resettingPrivacy: resetPrivacy
            )
            let dock = Self.dockNote(for: target, isInTheDock: isInTheDock, keeping: keepInDock)
            let webApp = Self.browserName(of: target, among: apps)
                .flatMap { Self.webAppNote(for: target, browserName: $0) }
            (warnings + [dock, webApp].compactMap(\.self)).forEach(output.json ? Output.note : Output.line)
        }
        Self.whatStays(plan, app: target, homebrew: homebrew, scan: uninstallation.scan).forEach(Output.note)

        guard !dryRun else {
            if output.json {
                let report = Self.report(
                    app: target, plan: plan, result: nil, privacy: nil, scan: uninstallation.scan,
                    appStays: excluded ?? running ?? access ?? wontMove
                )
                try Output.json(report)
            } else if !plan.moving.isEmpty {
                Output.line(resetPrivacy ? "Dry run: nothing was moved or reset." : "Dry run: nothing was moved.")
            }
            return
        }
        if !yes, !plan.moving.isEmpty {
            let items = Output.count(plan.moving.count, "item", "items")
            try Output.confirm(resetPrivacy ? "Reset privacy permissions and move \(items) to the Trash?" : "Move \(items) to the Trash?")
        }
        // Checked again: the scan and the question take time, and the app may have been opened, or something
        // excluded, meanwhile.
        try await Self.refuseWhileRunning(target, among: apps)
        let mover = service.excluding(await ExclusionStore().load())

        let (reset, result, recorded) = await Uninterrupted.run {
            // The privacy reset comes before the move, because `tccutil` only finds an app that is still in place.
            let reset = resetPrivacy ? await PrivacyReset.reset([target], beforeMovingWith: mover).first?.result : nil
            let result = await RecordedRemoval.$current.withValue(plan.recordedAs(target.name)) {
                await plan.move(using: mover)
            }
            let recorded = await plan.record(result, from: target.name)
            await LeftForAnAdministrator().record(uninstallation.leftForAnAdministrator(after: result))
            // An extension keeps running from the Trash, where nobody can quit it.
            if let moved = result.trashed.first(where: { $0.originalURL == target.url }) {
                SelfRemoval.endExtensions(runningFrom: moved.trashedURL)
            }
            return (reset, result, recorded)
        }
        let privacy = reset.map { Self.privacyOutcome($0, app: target, after: result) }
        var dockIconStayed: DockTiles.Stayed.Reason?
        if isInTheDock, Self.takesOutDockIcon(of: target, after: result, keeping: keepInDock) {
            let forgotten: Set<URL> = TrashService.isInsideATrash(target.url) ? [target.url] : []
            dockIconStayed = await DockTiles()
                .takeOut([target.url], foundAt: result.trashedAt, forgetting: forgotten)?.reason
        }
        let references = await ShellReferences.find(naming: result.trashed.map(\.originalURL))

        if output.json {
            let report = Self.report(
                app: target, plan: plan, result: result, privacy: reset, scan: uninstallation.scan,
                shellReferences: references, dockIconStayed: dockIconStayed
            )
            try Output.json(report)
            if let privacy, privacy.failed {
                Output.note(privacy.line)
            }
        } else {
            if !plan.moving.isEmpty {
                Output.line("Moved \(Output.count(result.trashed.count, "item", "items")) to the Trash.")
            }
            if let privacy {
                privacy.failed ? Output.note(privacy.line) : Output.line(privacy.line)
            }
        }
        if let note = Self.startsFromTheTrashNote(for: target, after: result) {
            Output.note(note)
        }
        if let dockIconStayed {
            Output.note(Self.dockStayedNote(for: target, reason: dockIconStayed))
        }
        if !references.isEmpty {
            Output.note(Self.shellNote(for: references))
        }
        if !recorded {
            Output.note("Peel couldn't write this to its History, so drag these back out of the Trash in Finder if you need to.")
        }
        if !result.failures.isEmpty {
            await Self.whatFailed(result, plan: plan, app: target).forEach(Output.note)
        }
        let everythingStayed = plan.moving.isEmpty && !plan.staying.isEmpty
        try Cleanup.end(
            failed: !result.failures.isEmpty || privacy?.failed == true || everythingStayed, recorded: recorded
        )
    }

    /// Returns the notes printed before the question: what the scan couldn't fully check, files that will stay, and
    /// Homebrew's record of the app when it stays. The user needs to see them before agreeing to the move.
    static func whatStays(
        _ plan: UninstallPlan,
        app: InstalledApp,
        homebrew: CaskLookup.Answer,
        scan: LeftoverScan
    ) -> [String] {
        var notes: [String] = []
        if let note = homebrew.note {
            notes.append(note)
        }
        let records = Set(scan.leftovers.filter { $0.kind == .homebrewReceipt }.map(\.url))
        let moving = Set(plan.moving.map(\.url))
        if moving.contains(app.url), moving.isDisjoint(with: records),
           let cask = CaskEvidence.installedCask(for: app, in: homebrew.casks) {
            notes.append("Homebrew installed \(Output.plain(app.name)) and will keep listing it as installed. To take it off that list, run `brew uninstall --cask \(Homebrew.lastWord(naming: cask.name))`: Homebrew then carries out the cask's own uninstall steps, which can delete files for good.")
        }
        if !scan.unreadableLocations.isEmpty {
            let folders = scan.unreadableLocations.map(\.url)
            notes.append(Output.unreadableNote(for: folders, needsFullDiskAccess: scan.needsFullDiskAccess))
        }
        notes += scan.cutShortLocations.map {
            "There are more folders in \(Output.plain(Output.path($0.url))) than Peel looks inside, so something of this app's may be in a folder Peel didn't reach."
        }
        if plan.needsAdministrator > 0 {
            let them = plan.needsAdministrator == 1 ? "it" : "them"
            notes.append("\(Output.count(plan.needsAdministrator, "item needs", "items need")) administrator access and will stay. Remove \(them) with the Peel app.")
        }
        if plan.leftForAnAdministrator > 0 {
            let them = plan.leftForAnAdministrator == 1 ? "it" : "them"
            notes.append("\(Output.count(plan.leftForAnAdministrator, "item needs", "items need")) an administrator, and Peel's helper can't move \(them). Once \(Output.plain(app.name)) is in the Trash, Orphaned Files in the Peel app lists \(them) under Needs an Administrator, with how to remove \(them).")
        }
        if plan.needsReview > 0 {
            let them = plan.needsReview == 1 ? "it" : "them"
            let place = Output.quoted(Output.path(app.url))
            notes.append("\(Output.count(plan.needsReview, "file needs", "files need")) review and will stay. See \(them) with `peel leftovers --all \(place)`.")
        }
        return notes
    }

    static func whatFailed(_ result: TrashResult, plan: UninstallPlan, app: InstalledApp) async -> [String] {
        var notes = result.failures.map { "Couldn't move \(Output.plain(Output.path($0.url))): \($0.reason.summary)" }
        if result.trashed.isEmpty, plan.moving.count > 1 {
            notes.append("\(Output.plain(app.name)) stayed, so its files were left where they are.")
        }
        // macOS refuses to move another developer's app without App Management, and it names no permission.
        if await AppManagement.state(after: result, appBundles: [plan.app]) == .missing {
            notes.append("Allow your terminal app in System Settings > Privacy & Security > App Management, then try again.")
        }
        return notes
    }
}

struct UpdatesCommand: AsyncParsableCommand {
    private static let concurrentChecks = 6

    static let configuration = CommandConfiguration(
        commandName: "updates",
        abstract: "Check installed apps for updates.",
        discussion: """
            Peel reads the settings of the Peel app: which source it prefers, which apps it was told to leave alone, \
            which versions were skipped, and what its checks found before. Nothing is installed. Only apps with an \
            update or a check that failed are listed unless --all is given.
            """
    )

    @Flag(help: "Show every app, not only those with an update.")
    var all = false

    @OptionGroup var output: OutputOptions

    private struct Record: Encodable {
        let app: AppRecord
        let status: String
        let availableVersion: String?
        let failure: String?

        private enum CodingKeys: String, CodingKey {
            case app
            case status
            case availableVersion
            case failure
        }

        init(app: InstalledApp, status: UpdateStatus, isWaiting: Bool, failure: UpdateFailure?) {
            self.app = AppRecord(app)
            self.failure = status == .failed ? failure?.summary : nil
            switch status {
            case .updateAvailable:
                self.status = isWaiting ? "updateAvailable" : "skipped"
                availableVersion = status.displayVersion
            case .upToDate:
                self.status = "upToDate"
                availableVersion = nil
            case .unsupported:
                self.status = "unsupported"
                availableVersion = nil
            case .failed:
                self.status = "failed"
                availableVersion = nil
            }
        }

        /// Written by hand so `availableVersion` and `failure` are always there, as `null` when there is none.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(app, forKey: .app)
            try container.encode(status, forKey: .status)
            try container.encode(availableVersion, forKey: .availableVersion)
            try container.encode(failure, forKey: .failure)
        }
    }

    /// The outcome of the checks, kept apart from the checking so a test can supply every answer. It counts
    /// the failures, so a run where every check failed isn't reported as up to date.
    struct Report {
        var rows: [(app: InstalledApp, status: UpdateStatus, failure: UpdateFailure?)] = []
        var failed = 0
        var withAFeed = 0
        var ignored = 0

        /// True when every app with an update feed failed its check, so nothing is known about updates.
        var nothingAnswered: Bool { withAFeed > 0 && failed == withAFeed }
    }

    static func report(
        apps: [InstalledApp],
        statuses: [InstalledApp.ID: UpdateStatus],
        failures: [InstalledApp.ID: UpdateFailure] = [:],
        preferences: UpdatePreferences,
        all: Bool
    ) -> Report {
        var report = Report(ignored: apps.count(where: preferences.isIgnored))
        for app in apps where !preferences.isIgnored(app) {
            let status = statuses[app.id] ?? .unsupported
            if status != .unsupported { report.withAFeed += 1 }
            if status == .failed { report.failed += 1 }
            // The same rule as the app's list: a skipped version is not a waiting update. A check that failed is
            // always listed, so a report with one is never read as all up to date.
            if all || status == .failed || preferences.isWaiting(status, for: app) {
                report.rows.append((app, status, status == .failed ? failures[app.id] : nil))
            }
        }
        return report
    }

    func run() async throws {
        let catalog = await AppCatalog.scan()
        let apps = catalog.apps
        // The Peel app's own update settings, so `peel` and the app agree on which updates are waiting.
        let preferences = UpdatePreferences.asTheAppSeesThem()
        let toCheck = apps.filter { !preferences.isIgnored($0) }
        let homebrew = await CaskLookup.evidence(for: toCheck)
        let checker = UpdateChecker()
        let checks = await ProgressLine.reporting { show in
            await Self.statuses(
                for: toCheck, checker: checker, preference: preferences.source, casks: homebrew.casks,
                memory: UpdateMemories.asTheAppSeesThem().recalled(for: apps)
            ) { answered in
                show(Self.progress(checked: answered, of: toCheck.count))
            }
        }
        let statuses = checks.statuses
        let report = Self.report(
            apps: apps, statuses: statuses, failures: checks.failures, preferences: preferences, all: all
        )

        if output.json {
            try Output.json(report.rows.map { row in
                Record(
                    app: row.app, status: row.status, isWaiting: preferences.isWaiting(row.status, for: row.app),
                    failure: row.failure
                )
            })
        } else if !report.rows.isEmpty {
            Output.table([["NAME", "INSTALLED", "STATUS"]] + report.rows.map { row in
                let summary = Self.summary(row.status, isWaiting: preferences.isWaiting(row.status, for: row.app))
                return [row.app.name, row.app.version ?? "", summary]
            })
        } else {
            Output.line("Every app Peel could check is up to date.")
        }
        if let note = homebrew.note {
            Output.note(note)
        }
        if let note = Output.unreadableNote(for: catalog) {
            Output.note(note)
        }
        let cannotTell = toCheck.filter { statuses[$0.id] == .unsupported }.compactMap { app in
            checker.homebrewCannotTell(about: app, preference: preferences.source, casks: homebrew.casks)
        }
        for note in Self.notes(about: cannotTell) {
            Output.note(note)
        }
        if report.ignored > 0 {
            Output.note("\(Output.count(report.ignored, "app is", "apps are")) set to be left alone in Peel and \(report.ignored == 1 ? "wasn't" : "weren't") checked.")
        }
        for note in Self.notes(aboutFailed: report) {
            Output.note(note)
        }
        if report.nothingAnswered {
            throw ExitCode.failure
        }
    }

    static func notes(aboutFailed report: Report) -> [String] {
        let failed = report.rows.filter { $0.status == .failed }
        let each = failed.map { row in
            "Couldn't check \(row.app.name)." + (row.failure.map { " " + $0.summary } ?? "")
        }
        guard report.nothingAnswered else { return each }
        let none = "Couldn't check any of the \(Output.count(report.withAFeed, "app", "apps")) with an update feed."
        // With no answer from any server, the fault is this Mac's network, which a line per app would only repeat.
        let reachedNoServer = failed.allSatisfy { row in
            if case .noAnswer = row.failure?.cause { true } else { false }
        }
        return reachedNoServer ? [none + " Check your connection and try again."] : each + [none]
    }

    static func notes(about cannotTell: [HomebrewCannotTell], timeZone: TimeZone = .current) -> [String] {
        let casks = { (reason: HomebrewCannotTell.Reason) in cannotTell.filter { $0.reason == reason }.map(\.cask) }
        var notes = [note(aboutCasksNotCheckedRecently: casks(.notCheckedRecently), timeZone: timeZone)]
        let newest = casks(.installsTheNewest).count
        if newest > 0 {
            notes.append("Homebrew's \(newest == 1 ? "cask" : "casks") of \(Output.count(newest, "app", "apps")) \(newest == 1 ? "installs" : "install") whatever is newest each time, so Homebrew has no version to compare, and whether \(newest == 1 ? "it is" : "they are") up to date isn't known.")
        }
        let left = casks(.leftToTheApp).count
        if left > 0 {
            notes.append("Homebrew's settings leave \(Output.count(left, "app", "apps")) to update \(left == 1 ? "itself" : "themselves") (HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS), so Homebrew doesn't compare \(left == 1 ? "its version" : "their versions"), and whether \(left == 1 ? "it is" : "they are") up to date isn't known.")
        }
        let disabled = casks(.disabled).count
        if disabled > 0 {
            notes.append("Homebrew has disabled the \(disabled == 1 ? "cask" : "casks") of \(Output.count(disabled, "app", "apps")), so whether \(disabled == 1 ? "it is" : "they are") up to date isn't known.")
        }
        return notes.compactMap(\.self)
    }

    private static func note(aboutCasksNotCheckedRecently casks: [HomebrewPackage], timeZone: TimeZone) -> String? {
        guard !casks.isEmpty else { return nil }
        let apps = "\(Output.count(casks.count, "app", "apps")) only Homebrew can answer for \(casks.count == 1 ? "is" : "are")"
        guard let checked = casks.compactMap(\.lastUpdateCheck).max() else {
            return "Homebrew doesn't say when it last checked for new versions, so whether \(apps) up to date isn't known."
        }
        return "Homebrew last checked for new versions on \(Output.day(checked, timeZone: timeZone)), so whether \(apps) up to date isn't known. Run `brew update`, then check again."
    }

    static func progress(checked: Int, of total: Int) -> String {
        "Checked \(Output.number(checked)) of \(Output.count(total, "app", "apps"))"
    }

    /// The status as the table writes it. An update the person skipped in the app reads as skipped.
    static func summary(_ status: UpdateStatus, isWaiting: Bool) -> String {
        switch status {
        case .updateAvailable:
            "\(status.displayVersion ?? "") \(isWaiting ? "available" : "skipped")"
        case .upToDate: "up to date"
        case .unsupported: "can't check"
        case .failed: "check failed"
        }
    }

    struct Checks {
        var statuses: [InstalledApp.ID: UpdateStatus] = [:]
        var failures: [InstalledApp.ID: UpdateFailure] = [:]
    }

    static func statuses(
        for apps: [InstalledApp],
        checker: UpdateChecker,
        preference: UpdateSource,
        casks: [HomebrewPackage],
        memory: UpdateMemories,
        answered: (Int) -> Void
    ) async -> Checks {
        // As the app does: what a check found before is its earlier answer, and an update its own source found is
        // kept through a check of that source that failed.
        let check = { @Sendable (app: InstalledApp) async -> (InstalledApp.ID, UpdateStatus, UpdateFailure?) in
            let earlier = memory.entry(for: app)
            let answer = await checker.answer(
                for: app, preference: preference, casks: casks, earlier: earlier?.status,
                notListedBefore: earlier?.isNotListed == true
            )
            return (app.id, answer.following(earlier?.status), answer.failure)
        }
        return await withTaskGroup(of: (InstalledApp.ID, UpdateStatus, UpdateFailure?).self) { group in
            var pending = apps.makeIterator()
            var checks = Checks()
            for _ in 0..<concurrentChecks {
                guard let app = pending.next() else { break }
                group.addTask { await check(app) }
            }
            while case let (id, status, failure)? = await group.next() {
                checks.statuses[id] = status
                checks.failures[id] = failure
                answered(checks.statuses.count)
                if let app = pending.next() {
                    group.addTask { await check(app) }
                }
            }
            return checks
        }
    }
}
