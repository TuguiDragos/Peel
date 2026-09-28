import AppKit
import ArgumentParser
import Foundation
import PeelCore

struct AppsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "apps", abstract: "List installed apps.")

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let apps = await AppCatalog.installedApps()
        if output.json {
            try Output.json(apps.map(AppRecord.init))
            return
        }
        Output.table([["NAME", "VERSION", "IDENTIFIER", "PATH"]] + apps.map { [$0.name, $0.version ?? "", $0.bundleIdentifier, Output.path($0.url)] })
    }
}

struct InventoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inventory",
        abstract: "Write out what is installed and where each app came from.",
        discussion: "A Brewfile only lists what Homebrew can install again; everything else would be a line that doesn't work."
    )

    /// An enum, so `--help` lists the formats and the shell can complete them.
    @Option(help: "What to write.")
    var format: FormatArgument = .text

    func run() async throws {
        let chosen = format.format
        guard chosen != .brewfile else {
            Output.write(try Inventory.build(apps: [], brewfile: try await Self.brewfile()).written(as: chosen))
            return
        }
        let apps = await AppCatalog.installedApps()
        let inventory = Inventory.build(apps: apps, casks: await Self.casks(), origins: .onThisMac)
        Output.write(try inventory.written(as: chosen))
    }

    /// Returns Homebrew's own Brewfile, or fails with why: an empty one would look like a success until someone
    /// uses it.
    private static func brewfile() async throws -> String {
        let why: String
        if !(await Homebrew.hasLocalDefinitions()) {
            why = noDefinitions(isInstalled: Homebrew.executableURL != nil)
        } else if let installation = await Homebrew.installation() {
            do {
                return try await Homebrew.brewfile(from: installation)
            } catch {
                why = error.output
            }
        } else {
            why = "Homebrew didn't say which version it is."
        }
        throw CommandFailure("Homebrew didn't answer, so there is nothing to write a Brewfile from.\n\(why)")
    }

    /// Returns the packages Homebrew installed, so an app it installed says so. When Homebrew can't answer, the
    /// list goes on without it and says why.
    private static func casks() async -> [HomebrewPackage] {
        let why: String
        if await Homebrew.hasLocalDefinitions() {
            do {
                return try await Homebrew.installedPackages()
            } catch {
                why = error.output
            }
        } else {
            why = noDefinitions(isInstalled: Homebrew.executableURL != nil)
        }
        if let note = homebrewNote(isInstalled: Homebrew.executableURL != nil, why: why) {
            Output.note(note)
        }
        return []
    }

    /// What a list other than a Brewfile says when Homebrew gave no packages: nothing on a Mac without Homebrew,
    /// and why otherwise.
    static func homebrewNote(isInstalled: Bool, why: String) -> String? {
        isInstalled ? "Homebrew didn't answer, so no app is marked as installed by it.\n\(why)" : nil
    }

    /// Why Homebrew was not asked: without its local copy of the definitions it would download them. The copy is
    /// missing because Homebrew isn't installed, or because it never fetched one.
    static func noDefinitions(isInstalled: Bool) -> String {
        isInstalled ? "Homebrew has no list of packages on this Mac. Run `brew update` first." : "Homebrew isn't installed."
    }
}

struct LeftoversCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "leftovers",
        abstract: "Show the files an app leaves behind.",
        discussion: "APP can be the path to the app, its bundle identifier, or its name."
    )

    @Argument(help: "The app to inspect.")
    var app: String

    @Flag(help: "Include files that need review before removing them.")
    var all = false

    @OptionGroup var output: OutputOptions

    struct Report: Encodable {
        let app: AppRecord
        /// Nil when the app bundle couldn't be measured. Written as `null`, never left out, so a script always
        /// finds the key.
        let appSize: Int64?
        let leftovers: [LeftoverRecord]
        let unreadableLocations: [String]

        init(app: InstalledApp, appSize: Int64?, leftovers: [Leftover], unreadableLocations: [SearchLocation]) {
            self.app = AppRecord(app)
            self.appSize = appSize
            self.leftovers = leftovers.map(LeftoverRecord.init)
            self.unreadableLocations = unreadableLocations.map { Output.path($0.url) }
        }

        private enum CodingKeys: String, CodingKey {
            case app
            case appSize
            case leftovers
            case unreadableLocations
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(app, forKey: .app)
            try container.encode(appSize, forKey: .appSize)
            try container.encode(leftovers, forKey: .leftovers)
            try container.encode(unreadableLocations, forKey: .unreadableLocations)
        }
    }

    func run() async throws {
        let apps = await AppCatalog.installedApps()
        let target = try AppLookup.app(matching: app, in: apps)
        let exclusions = await ExclusionStore().load()
        try AppLookup.refuseIfExcluded(target, by: exclusions)
        let homebrew = await CaskLookup.evidence(for: target)
        let uninstallation = await Uninstallation.prepare(
            target,
            installedApps: apps,
            exclusions: exclusions,
            casks: homebrew.casks,
            receipts: homebrew.receipts
        )
        let leftovers = uninstallation.scan.leftovers.filter { all || $0.match.isRecommended }

        // Printed in JSON mode too, on standard error, so a script that reads an empty list still learns what
        // was left out or couldn't be checked.
        Self.notes(uninstallation, homebrew: homebrew, hidden: uninstallation.scan.leftovers.count - leftovers.count)
        if output.json {
            let appSize = uninstallation.isAppMeasured ? uninstallation.appSize : nil
            let unread = uninstallation.scan.unreadableLocations
            try Output.json(Report(app: target, appSize: appSize, leftovers: leftovers, unreadableLocations: unread))
            return
        }
        let appSize = uninstallation.isAppMeasured ? Output.size(uninstallation.appSize) : "unknown"
        Output.line("\(target.name) \(target.version ?? "")  \(appSize)  \(Output.path(target.url))")
        if leftovers.isEmpty {
            Output.line("No leftovers found.")
        } else {
            Output.line()
            Output.table(leftovers.map { [Output.size(Self.measured($0)), Output.path($0.url), Self.summary(of: $0)] })
        }
    }

    /// Describes `leftover` in one line: why it matched, why it needs review when it isn't suggested (held
    /// back, shared with other apps, or only a possible match), and whether it needs administrator access.
    static func summary(of leftover: Leftover) -> String {
        var summary = leftover.match.reason.summary
        if let heldBack = leftover.match.heldBack {
            summary += ", review: \(heldBack.summary)"
        } else if !leftover.match.isRecommended {
            let users = leftover.match.sharedWith + leftover.match.otherCopies.map(Output.path)
            summary += leftover.match.isShared
                ? ", review: shared with \(users.joined(separator: ", "))"
                : ", review: \(leftover.match.confidence.summary) match"
        }
        if leftover.requiresPrivileges {
            summary += ", needs administrator access"
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
            are; remove them with the Peel app.
            The app itself moves first, so nothing of it goes to the Trash while it stays installed. Answering \
            no exits with code 2; a removal that couldn't finish exits 1, and so does a privacy reset that \
            didn't happen.
            """
    )

    @Argument(help: "The app to remove: its path, bundle identifier, or name.")
    var app: String

    @Flag(help: "Move only the app, not its leftovers.")
    var keepLeftovers = false

    @Flag(help: "Also reset the app's privacy permissions, just before it moves, so it asks again if you reinstall it. The Trash can't bring them back.")
    var resetPrivacy = false

    @Flag(help: "Show what would move without moving anything.")
    var dryRun = false

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

            private enum CodingKeys: String, CodingKey {
                case path
                case size
                case stays
            }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(path, forKey: .path)
                try container.encode(size, forKey: .size)
                try container.encode(stays, forKey: .stays)
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
        let unreadableLocations: [String]

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
            case unreadableLocations
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
            try container.encode(unreadableLocations, forKey: .unreadableLocations)
        }
    }

    /// The report `--json` writes. `result` is nil for a dry run, which moved nothing.
    static func report(
        app: InstalledApp,
        plan: UninstallPlan,
        result: TrashResult?,
        privacy: PrivacyReset.Result?,
        unreadable: [SearchLocation]
    ) -> Report {
        Report(
            app: AppRecord(app),
            dryRun: result == nil,
            items: plan.items.map { item in
                Report.Item(path: Output.path(item.url), size: MeasuredSize(item.size), stays: item.refusal?.name)
            },
            moved: (result?.trashed ?? []).map { Output.path($0.originalURL) },
            failed: (result?.failures ?? []).map {
                Report.Failure(path: Output.path($0.url), reason: $0.reason.name, detail: $0.reason.detail)
            },
            privacyReset: privacy.map { $0 == .reset },
            appMoved: result.map { result in result.trashed.contains { $0.originalURL == plan.app } },
            needsAdministrator: plan.needsAdministrator,
            needsReview: plan.needsReview,
            unreadableLocations: unreadable.map { Output.path($0.url) }
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
        let running = await RunningCopies.belonging(to: target, among: RunningCopies.current, installedApps: apps)
        guard running.isEmpty else {
            let identifiers = Set(running.map(\.bundleIdentifier)).sorted().map(Output.plain)
            throw CommandFailure("Quit \(Output.plain(target.name)) first. Still running: \(identifiers.joined(separator: ", ")).")
        }
    }

    /// Throws for Peel itself. Peel removes itself from its own Settings, after unregistering its login item
    /// and privileged helper. If `peel` moved the app, the helper would stay registered with launchd and
    /// point into the Trash.
    static func refuseIfItIsPeel(_ target: InstalledApp) throws {
        guard target.isPeelItself else { return }
        throw CommandFailure("Peel removes itself from its own settings, which unregisters the helper first. Open Peel and click Remove Peel in Settings.")
    }

    /// Throws when Peel never resets the privacy permissions of `target`. Called for `--reset-privacy` before
    /// anything is listed: skipping the reset quietly would remove the app and leave its permissions on record.
    static func refuseIfPrivacyCannotBeReset(_ target: InstalledApp) throws {
        guard !PrivacyReset.isAllowed(bundleIdentifier: target.bundleIdentifier) else { return }
        throw CommandFailure("Peel never resets privacy permissions for \(Output.plain(target.name)). Leave out --reset-privacy to remove it anyway.")
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
        let apps = await AppCatalog.installedApps()
        let target = try AppLookup.app(matching: app, in: apps)
        try Self.refuseIfItIsPeel(target)
        guard !target.isSystemProtected else {
            throw CommandFailure("macOS protects \(Output.plain(target.name)), so it can't be removed.")
        }
        if resetPrivacy {
            try Self.refuseIfPrivacyCannotBeReset(target)
        }
        let exclusions = await ExclusionStore().load()
        try AppLookup.refuseIfExcluded(target, by: exclusions)
        let service = TrashService(exclusions: exclusions)
        guard !service.isInsideATrash(target.url) else {
            throw CommandFailure("\(Output.plain(target.name)) is already in the Trash. Empty it, or put it back first.")
        }
        try await Self.refuseWhileRunning(target, among: apps)
        let homebrew = await CaskLookup.evidence(for: target)
        let uninstallation = await Uninstallation.prepare(
            target,
            installedApps: apps,
            exclusions: exclusions,
            casks: homebrew.casks,
            receipts: homebrew.receipts
        )
        guard !uninstallation.appRequiresPrivileges else {
            throw CommandFailure("Moving \(Output.plain(target.name)) to the Trash needs administrator access. Remove it with the Peel app.")
        }

        if let note = UnreadableHistory.note() {
            Output.note(note)
        }
        // The removal guard judges each item before printing, so the list shows what the move will really do.
        let plan = UninstallPlan.make(uninstallation, keepLeftovers: keepLeftovers, refusal: service.refusal(of:))
        if let refusal = plan.appStays {
            throw CommandFailure("Peel won't move \(Output.plain(Output.path(target.url))): \(refusal.summary). Nothing of \(Output.plain(target.name)) was touched.")
        }
        let unreadable = uninstallation.scan.unreadableLocations
        if !output.json {
            // The third column appears only when some item stays, so an ordinary list has no trailing spaces.
            let staying = !plan.staying.isEmpty
            Output.table(plan.items.map { item in
                [Output.size(item.size), Output.path(item.url)] + (staying ? [item.refusal.map { "stays: \($0.summary)" } ?? "moves"] : [])
            })
            Output.line("Total: \(Output.size(plan.total))")
            if resetPrivacy {
                Output.line("Peel resets \(target.name)'s privacy permissions just before it moves. The Trash can't bring them back.")
            }
        }
        Self.whatStays(plan, app: target, homebrew: homebrew, scan: uninstallation.scan).forEach(Output.note)

        guard !dryRun else {
            if output.json {
                try Output.json(Self.report(app: target, plan: plan, result: nil, privacy: nil, unreadable: unreadable))
            } else {
                Output.line(resetPrivacy ? "Dry run: nothing was moved or reset." : "Dry run: nothing was moved.")
            }
            return
        }
        if !yes {
            let items = Output.count(plan.moving.count, "item", "items")
            try Output.confirm(resetPrivacy ? "Reset privacy permissions and move \(items) to the Trash?" : "Move \(items) to the Trash?")
        }
        // Checked again: the scan and the question take time, and the app may have been opened meanwhile.
        try await Self.refuseWhileRunning(target, among: apps)

        let (reset, result, recorded) = await Uninterrupted.run {
            // The privacy reset comes before the move, because `tccutil` only finds an app that is still in place.
            let reset = resetPrivacy ? await PrivacyReset.reset(bundleIdentifier: target.bundleIdentifier) : nil
            let result = await plan.move(using: service)
            let sizes = [URL: Int64](measured: plan.items.map { ($0.url, $0.size) })
            return (reset, result, await Removals.record(result, from: target.name, sizes: sizes, tool: "applications"))
        }
        let privacy = reset.map { Self.privacyOutcome($0, app: target, after: result) }

        if output.json {
            let report = Self.report(app: target, plan: plan, result: result, privacy: reset, unreadable: unreadable)
            try Output.json(report)
            if let privacy, privacy.failed {
                Output.note(privacy.line)
            }
        } else {
            Output.line("Moved \(Output.count(result.trashed.count, "item", "items")) to the Trash.")
            if let privacy {
                privacy.failed ? Output.note(privacy.line) : Output.line(privacy.line)
            }
        }
        if !recorded {
            Output.note("Peel couldn't write this to its History, so drag these back out of the Trash in Finder if you need to.")
        }
        guard result.failures.isEmpty else {
            Self.whatFailed(result, plan: plan, app: target).forEach(Output.note)
            throw ExitCode.failure
        }
        if privacy?.failed == true {
            throw ExitCode.failure
        }
    }

    /// Returns the notes printed before the question: what the scan couldn't fully check, and files that
    /// will stay. The user needs to see them before agreeing to the move.
    static func whatStays(_ plan: UninstallPlan, app: InstalledApp, homebrew: CaskLookup.Answer, scan: LeftoverScan) -> [String] {
        var notes: [String] = []
        if let note = homebrew.note {
            notes.append(note)
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
        if plan.needsReview > 0 {
            let them = plan.needsReview == 1 ? "it" : "them"
            notes.append("\(Output.count(plan.needsReview, "file needs", "files need")) review and will stay. See \(them) with `peel leftovers \(Output.quoted(app.name)) --all`.")
        }
        return notes
    }

    static func whatFailed(_ result: TrashResult, plan: UninstallPlan, app: InstalledApp) -> [String] {
        var notes = result.failures.map { "Couldn't move \(Output.plain(Output.path($0.url))): \($0.reason.summary)" }
        if result.trashed.isEmpty, plan.moving.count > 1 {
            notes.append("\(Output.plain(app.name)) stayed, so its files were left where they are.")
        }
        // macOS refuses to move another developer's app without App Management, and it names no permission.
        if AppManagement.state(after: result, appBundles: [plan.app]) == .missing {
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
            and which versions were skipped. Nothing is installed; apps with no feed are left out unless --all is \
            given.
            """
    )

    @Flag(help: "Show every app, not only those with an update.")
    var all = false

    @OptionGroup var output: OutputOptions

    private struct Record: Encodable {
        let app: AppRecord
        let status: String
        let availableVersion: String?

        private enum CodingKeys: String, CodingKey {
            case app
            case status
            case availableVersion
        }

        init(app: InstalledApp, status: UpdateStatus, isWaiting: Bool) {
            self.app = AppRecord(app)
            switch status {
            case .updateAvailable(let version, _, _):
                self.status = isWaiting ? "updateAvailable" : "skipped"
                availableVersion = version
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

        /// Written by hand so `availableVersion` is always there, as `null` when there is no update.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(app, forKey: .app)
            try container.encode(status, forKey: .status)
            try container.encode(availableVersion, forKey: .availableVersion)
        }
    }

    /// The outcome of the checks, kept apart from the checking so a test can supply every answer. It counts
    /// the failures, so a run where every check failed isn't reported as up to date.
    struct Report {
        var rows: [(app: InstalledApp, status: UpdateStatus)] = []
        var failed = 0
        var withAFeed = 0
        var ignored = 0

        /// True when every app with an update feed failed its check, so nothing is known about updates.
        var nothingAnswered: Bool { withAFeed > 0 && failed == withAFeed }
    }

    static func report(
        apps: [InstalledApp],
        statuses: [InstalledApp.ID: UpdateStatus],
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
                report.rows.append((app, status))
            }
        }
        return report
    }

    func run() async throws {
        let apps = await AppCatalog.installedApps()
        // The Peel app's own update settings, so `peel` and the app agree on which updates are waiting.
        let preferences = UpdatePreferences.asTheAppSeesThem()
        let homebrew = await CaskLookup.installed()
        let statuses = await Self.statuses(
            for: apps.filter { !preferences.isIgnored($0) },
            preference: preferences.source,
            casks: homebrew.casks
        )
        let report = Self.report(apps: apps, statuses: statuses, preferences: preferences, all: all)

        if output.json {
            try Output.json(report.rows.map { row in
                Record(app: row.app, status: row.status, isWaiting: preferences.isWaiting(row.status, for: row.app))
            })
        } else if !report.rows.isEmpty {
            Output.table([["NAME", "INSTALLED", "STATUS"]] + report.rows.map { row in
                let summary = Self.summary(row.status, isWaiting: preferences.isWaiting(row.status, for: row.app))
                return [row.app.name, row.app.version ?? "", summary]
            })
        } else {
            Output.line("Every app with an update feed is up to date.")
        }
        if let note = homebrew.note {
            Output.note(note)
        }
        if report.ignored > 0 {
            Output.note("\(Output.count(report.ignored, "app is", "apps are")) set to be left alone in Peel and \(report.ignored == 1 ? "wasn't" : "weren't") checked.")
        }
        guard !report.nothingAnswered else {
            Output.note("Couldn't check any of the \(Output.count(report.withAFeed, "app", "apps")) with an update feed. Check your connection and try again.")
            throw ExitCode.failure
        }
        if report.failed > 0 {
            Output.note("Couldn't check \(Output.count(report.failed, "app", "apps")), so \(report.failed == 1 ? "whether it has an update" : "whether they have updates") isn't known.")
        }
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

    private static func statuses(
        for apps: [InstalledApp],
        preference: UpdateSource,
        casks: [HomebrewPackage]
    ) async -> [InstalledApp.ID: UpdateStatus] {
        let checker = UpdateChecker()
        return await withTaskGroup(of: (InstalledApp.ID, UpdateStatus).self) { group in
            var pending = apps.makeIterator()
            var statuses: [InstalledApp.ID: UpdateStatus] = [:]
            for _ in 0..<concurrentChecks {
                guard let app = pending.next() else { break }
                group.addTask { (app.id, await checker.status(for: app, preference: preference, casks: casks)) }
            }
            while case let (id, status)? = await group.next() {
                statuses[id] = status
                if let app = pending.next() {
                    group.addTask { (app.id, await checker.status(for: app, preference: preference, casks: casks)) }
                }
            }
            return statuses
        }
    }
}
