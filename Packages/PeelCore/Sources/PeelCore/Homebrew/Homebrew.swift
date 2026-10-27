public import Foundation
internal import PeelPrivileged

public struct HomebrewPackage: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case formula
        case cask
    }

    public let name: String
    /// The name with its tap in front (`hashicorp/tap/terraform`) for a package that is not Homebrew's own,
    /// which is the only name that installs it again. The short name otherwise.
    public let fullName: String
    public let kind: Kind
    public let summary: String?
    public let homepage: URL?
    public let installedVersion: String?
    public let latestVersion: String?
    public let isOutdated: Bool
    public let isPinned: Bool
    public let isInstalledOnRequest: Bool
    public let dependencies: [String]
    /// Apps a cask installs, like "Example.app".
    public let appNames: [String]
    /// Where Homebrew put them, for a cask that is installed: "/Applications/Example.app".
    public let appTargets: [String]
    /// Where Homebrew linked the commands an installed cask puts on the path: "/opt/homebrew/bin/example".
    /// `brew uninstall` removes these links.
    public let commandLinks: [String]
    /// Bundle identifiers the cask tells macOS to quit, which prove a cask really is a given app.
    public let quitIdentifiers: [String]
    /// Installer receipts the cask forgets, which can prove the cask for an app installed from a `.pkg`.
    public let packageIdentifiers: [String]
    /// Paths a cask's `uninstall` and `zap` stanzas remove, as written, with `~` and globs.
    public let leftoverPatterns: [String]
    /// Folders the same stanzas remove only when they are empty (`rmdir`).
    public let emptyFolderPatterns: [String]
    /// Set when Homebrew has deprecated or disabled the package.
    public let retirement: HomebrewRetirement?
    /// True for a cask whose upgrade runs a step as root with `sudo`, which asks for a password that only a
    /// terminal can give: an installer package, an installer script run with `sudo`, or an `uninstall` step that
    /// needs one, since an upgrade removes the old version first.
    public let upgradeNeedsAnAdministrator: Bool
    /// True for a cask whose `uninstall` stanza runs a step with `sudo`: `pkgutil`, `delete`, `kext`, or a script
    /// run with `sudo`.
    public let uninstallNeedsAnAdministrator: Bool
    /// True for a cask whose app updates itself (`auto_updates`). Homebrew counts such a cask outdated only while its
    /// settings let it upgrade one, and then by the version in the app's own bundle.
    public let appUpdatesItself: Bool
    /// True for a cask whose app updates itself while Homebrew's settings leave such casks to their apps, so that
    /// Homebrew never counts it outdated. Set by `noting(_:)`.
    public private(set) var isLeftToItsApp = false
    /// The entries of `packageIdentifiers` whose receipts are installed, lowercased. `noting(receipts:)` sets
    /// them, so the cask carries this proof to every place that checks it.
    public private(set) var receiptsOnThisMac: [String] = []
    /// Where the packages named by `packageIdentifiers` wrote apps, as their receipts list them, for an installed cask
    /// that installs from a `.pkg` and so may name no app. An installer's script can move an app once its package
    /// wrote it, so an app found at one of these is the cask's, and one found elsewhere may still be.
    public private(set) var packagedApps: [String] = []
    /// An installed cask's folder in Homebrew's Caskroom (`brew --caskroom <token>`), set by `kept(inCaskroom:)`.
    public private(set) var caskroomFolder: URL?
    /// True for an installed cask that left nothing on this Mac: every app gone from where Homebrew put it, or, for a
    /// cask with no app, every package it installed, as their receipts say. Set by `checkingWhatItInstalled`.
    public private(set) var isMissingWhatItInstalled = false
    /// True for an installed cask whose upgrade was stopped once Homebrew had moved its app into the cask's folder,
    /// renamed `<version>.upgrading`: Homebrew puts it back only when the upgrade fails with an error, not when it is
    /// stopped. Set by `checkingWhatItInstalled`.
    public private(set) var isStoppedMidUpgrade = false
    /// When Homebrew last checked for new versions, read before this package was (`Homebrew.lastUpdateCheck()`), or
    /// nil when Peel couldn't tell. What `isOutdated` says is no more recent than that check.
    public private(set) var lastUpdateCheck: Date?

    public var id: String { "\(kind.rawValue)/\(name)" }

    /// Why Homebrew's `outdated` says nothing of whether this cask's app is behind, or nil when Homebrew compares its
    /// version: a cask written `version :latest` installs whatever is newest each time.
    public var whyHomebrewCannotCompare: HomebrewCannotTell.Reason? {
        if !isStillUpgraded { return .disabled }
        if latestVersion == "latest" { return .installsTheNewest }
        return isLeftToItsApp ? .leftToTheApp : nil
    }

    /// Returns a copy that notes what Homebrew's own settings, when it said them, make of this cask.
    public func noting(_ settings: Homebrew.Overrides?) -> HomebrewPackage {
        var noted = self
        noted.isLeftToItsApp = appUpdatesItself && settings?.contains(.leavesAppsThatUpdateThemselves) == true
        return noted
    }

    /// Whether Upgrade All takes it along when it is out of date: a pinned package is held at its version on purpose,
    /// a cask whose upgrade needs an administrator is upgraded in Terminal, and Peel's own updates itself.
    public var joinsUpgradeAll: Bool {
        isStillUpgraded && !isPinned && !upgradeNeedsAnAdministrator && !isMissingWhatItInstalled
            && !isStoppedMidUpgrade && !isPeelItself
    }

    /// True for Peel's own cask: its definition quits Peel or one of its parts, or the code that runs is in one of its
    /// apps. Peel never runs Homebrew on it, since Homebrew would have to quit Peel first.
    public var isPeelItself: Bool {
        quitIdentifiers.contains(where: Identifier.isPeels)
            || appTargets.contains { target in
                let app = PathPattern.comparablePath(of: URL(filePath: target, directoryHint: .isDirectory))
                return PathComponents.isPath(InstalledApp.runningBundle, atOrInside: app)
            }
    }

    /// Whether Homebrew offers a newer version that it can install. It upgrades a cask's app where it put it, so it
    /// can't upgrade a cask whose apps are gone.
    public var waitsForAnUpgrade: Bool {
        isOutdated && isStillUpgraded && !isMissingWhatItInstalled && !isStoppedMidUpgrade
    }

    /// Whether Homebrew still upgrades it: one it has disabled gets no more upgrades, though `outdated` may say it is.
    public var isStillUpgraded: Bool {
        retirement?.stage != .disabled
    }

    /// Returns a copy that notes whether what the installed cask put on the Mac is all gone, asked of the disk now: its
    /// apps, or, with none, the receipts in `receipts` of the packages it installed. An app on a disk that is not
    /// connected is not gone.
    public func checkingWhatItInstalled(
        receipts: URL = URL(filePath: "/private/var/db/receipts", directoryHint: .isDirectory)
    ) -> HomebrewPackage {
        var checked = self
        let missing = appTargets.map { URL(filePath: $0, directoryHint: .isDirectory) }
            .filter { $0.isMissing && !$0.isOnADiskNotConnected }
        checked.isStoppedMidUpgrade = caskroomFolder.map {
            Self.holdsMidUpgrade(missing.map(\.lastPathComponent), in: $0)
        } ?? false
        checked.isMissingWhatItInstalled = caskroomFolder != nil && !checked.isStoppedMidUpgrade && (appTargets.isEmpty
            ? Self.packagesAreGone(packageIdentifiers, receipts: receipts)
            : missing.count == appTargets.count)
        return checked
    }

    /// Whether one of `apps` sits in a `<version>.upgrading` folder inside the cask's folder.
    private static func holdsMidUpgrade(_ apps: [String], in folder: URL) -> Bool {
        guard !apps.isEmpty, let versions = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return false
        }
        return versions.filter { $0.hasSuffix(".upgrading") }.contains { version in
            apps.contains { !folder.appending(path: version).appending(path: $0).isMissing }
        }
    }

    /// True when `identifiers` name packages exactly and none of them has a receipt left. Homebrew reads each as a
    /// pattern (`pkgutil --pkgs=`), and one with more than letters, digits, dots, hyphens and underscores could match
    /// a package by another name, so it proves nothing.
    private static func packagesAreGone(_ identifiers: [String], receipts: URL) -> Bool {
        let isExact = { (identifier: String) in
            !identifier.hasPrefix(".")
                && identifier.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
        }
        return !identifiers.isEmpty && identifiers.allSatisfy { identifier in
            isExact(identifier) && receipts.appending(path: "\(identifier).plist").isMissing
        }
    }

    /// Returns a copy that notes which `packageIdentifiers` are among `receipts`, the lowercased identifiers of
    /// the installed receipts. A pattern such as `com.adobe.acrobat.DC.*` matches none and proves nothing,
    /// which errs on the safe side.
    public func noting(receipts: Set<String>) -> HomebrewPackage {
        var noted = self
        noted.receiptsOnThisMac = packageIdentifiers.map { $0.lowercased() }.filter(receipts.contains)
        return noted
    }

    func noting(packagedApps: [String]) -> HomebrewPackage {
        var noted = self
        noted.packagedApps = packagedApps
        return noted
    }

    public func noting(lastUpdateCheck: Date?) -> HomebrewPackage {
        var noted = self
        noted.lastUpdateCheck = lastUpdateCheck
        return noted
    }

    public func kept(inCaskroom caskroom: URL) -> HomebrewPackage {
        var kept = self
        kept.caskroomFolder = caskroom.appending(path: name, directoryHint: .isDirectory)
        return kept
    }

    public init(
        name: String,
        kind: Kind,
        fullName: String? = nil,
        summary: String? = nil,
        homepage: URL? = nil,
        installedVersion: String? = nil,
        latestVersion: String? = nil,
        isOutdated: Bool = false,
        isPinned: Bool = false,
        isInstalledOnRequest: Bool = true,
        dependencies: [String] = [],
        appNames: [String] = [],
        appTargets: [String] = [],
        commandLinks: [String] = [],
        leftoverPatterns: [String] = [],
        emptyFolderPatterns: [String] = [],
        quitIdentifiers: [String] = [],
        packageIdentifiers: [String] = [],
        retirement: HomebrewRetirement? = nil,
        upgradeNeedsAnAdministrator: Bool = false,
        uninstallNeedsAnAdministrator: Bool = false,
        appUpdatesItself: Bool = false
    ) {
        self.name = name
        self.kind = kind
        self.fullName = fullName ?? name
        self.summary = summary
        self.homepage = homepage
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
        self.isOutdated = isOutdated
        self.isPinned = isPinned
        self.isInstalledOnRequest = isInstalledOnRequest
        self.dependencies = dependencies
        self.appNames = appNames
        self.appTargets = appTargets
        self.commandLinks = commandLinks
        self.leftoverPatterns = leftoverPatterns
        self.emptyFolderPatterns = emptyFolderPatterns
        self.quitIdentifiers = quitIdentifiers
        self.packageIdentifiers = packageIdentifiers
        self.retirement = retirement
        self.upgradeNeedsAnAdministrator = upgradeNeedsAnAdministrator
        self.uninstallNeedsAnAdministrator = uninstallNeedsAnAdministrator
        self.appUpdatesItself = appUpdatesItself
    }
}

extension [HomebrewPackage] {
    /// Whether `other` has the same packages installed, at the same versions, whatever else Homebrew now says of
    /// them, such as a newer version it offers.
    public func installsTheSame(as other: [HomebrewPackage]) -> Bool {
        installed == other.installed
    }

    private var installed: [String: String?] {
        Dictionary(map { ($0.id, $0.installedVersion) }, uniquingKeysWith: { first, _ in first })
    }
}

public struct HomebrewInstallation: Sendable, Hashable {
    public let version: String
    public let prefix: URL
    /// Where Homebrew keeps its formulae, as it says: in its repository when it has one there, else under the prefix.
    public let cellar: URL
    /// Where Homebrew itself is, as it says: the prefix on a Mac with Apple silicon, `/usr/local/Homebrew` on Intel.
    public let repository: URL
    /// The account the repository belongs to, which installed Homebrew.
    public private(set) var owner: String?
    /// Whether this account may change Homebrew (`Homebrew.mayBeChanged`), judged when it was read.
    public private(set) var mayBeChangedByThisAccount = true

    public var caskroom: URL {
        prefix.appending(path: "Caskroom", directoryHint: .isDirectory)
    }

    private let numbers: [Int]

    public var reportsHealthAsJSON: Bool { isAtLeast(6, 0, 13) }

    public var checksVulnerabilities: Bool { isAtLeast(6, 0, 11) }

    /// Homebrew has written sizes in powers of 1000 since 5.0.0 (`utils/formatter.rb`), and of 1024 before.
    var countsInThousands: Bool { isAtLeast(5, 0, 0) }

    /// `brew bundle` is part of Homebrew since 4.4.25; before, it lived in a tap that asking for it would download.
    public var writesABrewfile: Bool { isAtLeast(4, 4, 25) }

    public init(version: String, prefix: URL, cellar: URL? = nil, repository: URL? = nil) {
        self.version = version
        self.prefix = prefix
        self.cellar = cellar ?? prefix.appending(path: "Cellar", directoryHint: .isDirectory)
        self.repository = repository ?? prefix
        numbers = version
            .prefix { $0.isNumber || $0 == "." }
            .split(separator: ".")
            .compactMap { Int($0) }
    }

    /// A copy that says whose Homebrew this is and whether this account may change it.
    func judgedForThisAccount() -> HomebrewInstallation {
        var judged = self
        let path = repository.path(percentEncoded: false)
        judged.owner = (try? FileManager.default.attributesOfItem(atPath: path))?[.ownerAccountName] as? String
        judged.mayBeChangedByThisAccount = Homebrew.mayBeChanged(cellar: cellar, repository: repository)
        return judged
    }

    private func isAtLeast(_ required: Int...) -> Bool {
        for (index, number) in required.enumerated() {
            let mine = index < numbers.count ? numbers[index] : 0
            guard mine == number else { return mine > number }
        }
        return true
    }
}

/// One thing `brew doctor` found, with the commands Homebrew itself suggests for it.
public struct HomebrewFinding: Sendable, Hashable, Identifiable {
    public let text: String
    public let remedy: String?
    public let commands: [String]

    public var id: String { text }

    public init(text: String, remedy: String?, commands: [String]) {
        self.text = text
        self.remedy = remedy
        self.commands = commands
    }
}

public struct HomebrewVulnerability: Sendable, Hashable, Identifiable {
    public enum Severity: Sendable, Hashable, Comparable {
        case unknown
        case low
        case medium
        case high
        case critical

        public init(name: String) {
            switch name.lowercased() {
            case "low": self = .low
            case "medium": self = .medium
            case "high": self = .high
            case "critical": self = .critical
            default: self = .unknown
            }
        }
    }

    /// What OSV.dev says fixes a vulnerability.
    public enum Fix: Sendable, Hashable {
        case versions([String])
        /// OSV.dev names only the commits that fix it, and no version.
        case commits
        case notListed

        /// Reads Homebrew's `fixed_versions`, where the fix of a Git range is a full commit hash (the OSV schema,
        /// `GIT` ranges) and any other entry is a version.
        init(fixedIn entries: [String]) {
            let versions = entries.filter { !Self.isCommit($0) }
            self = if !versions.isEmpty { .versions(versions) } else if entries.isEmpty { .notListed } else { .commits }
        }

        private static func isCommit(_ entry: String) -> Bool {
            (entry.count == 40 || entry.count == 64) && entry.allSatisfy(\.isHexDigit)
        }
    }

    public let id: String
    public let aliases: [String]
    public let severity: Severity
    public let summary: String
    public let fix: Fix

    public init(id: String, aliases: [String] = [], severity: Severity, summary: String, fix: Fix = .notListed) {
        self.id = id
        self.aliases = aliases
        self.severity = severity
        self.summary = summary
        self.fix = fix
    }
}

public struct HomebrewAdvisory: Sendable, Hashable, Identifiable {
    public let formula: String
    public let version: String
    public let vulnerabilities: [HomebrewVulnerability]
    /// True when Homebrew couldn't tell what the installed version was built from, so it checked the formula as it is
    /// now: `version` is then not the version these were found in.
    public var checkedTheCurrentFormula = false

    public var id: String { formula }

    public var highestSeverity: HomebrewVulnerability.Severity {
        vulnerabilities.map(\.severity).max() ?? .unknown
    }

    public init(formula: String, version: String, vulnerabilities: [HomebrewVulnerability]) {
        self.formula = formula
        self.version = version
        self.vulnerabilities = vulnerabilities
    }
}

public struct HomebrewVulnerabilityReport: Sendable, Hashable {
    public let advisories: [HomebrewAdvisory]
    public let skipped: [String]
    /// The formulae checked as they are now rather than as installed (`outdated_without_sbom`): older than the
    /// formula, and installed before Homebrew recorded what it built from.
    public var checkedTheCurrentFormula: [String] = []
    /// What `brew vulns` wrote to standard error beside the result, in Homebrew's words: that an untrusted tap
    /// was not scanned, for example, or that the result is about the current formula, not the installed version.
    public var caveats = ""

    public init(advisories: [HomebrewAdvisory], skipped: [String]) {
        self.advisories = advisories
        self.skipped = skipped
    }
}

/// One stanza of a cask. Homebrew writes them as free-form JSON, so only the pieces Peel understands are read.
struct CaskArtifact: Decodable, Sendable {
    let appNames: [String]
    let appTargets: [String]
    let commandLinks: [String]
    let leftoverPatterns: [String]
    let emptyFolderPatterns: [String]
    /// Bundle identifiers the cask tells macOS to quit. The surest sign a cask really is a given app.
    let quitIdentifiers: [String]
    /// Installer receipts the cask forgets, which can be matched against the receipts on this Mac.
    let packageIdentifiers: [String]
    /// True when installing runs as root: an installer package, or an installer script run with `sudo`.
    let installNeedsAnAdministrator: Bool
    /// True when the `uninstall` stanza runs a step as root: `pkgutil`, `delete` and `kext` always do, and a
    /// script when it says `sudo`. `launchctl` tries with `sudo` and goes on without it, and `zap` is not run.
    let uninstallNeedsAnAdministrator: Bool

    private static let removalKeys = ["trash", "delete"]
    private static let stepsRunAsRoot = ["pkgutil", "delete", "kext"]

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode([String: CaskValue].self)) ?? [:]
        // A cask writes its app plainly, inside a folder, or as `{"target": "Krita.app"}` when it renames it.
        let app = raw["app"]
        appNames = ((app?.strings ?? []) + (app?.dictionaries ?? []).flatMap { $0["target"]?.strings ?? [] })
            .map { ($0 as NSString).lastPathComponent }
            .filter { !$0.isEmpty }
        // Homebrew writes where each artifact it moves goes, installed or not:
        // `{"app": [...], "target": "/Applications/Krita.app"}`.
        appTargets = app == nil ? [] : (raw["target"]?.strings ?? []).filter { $0.hasPrefix("/") }
        // A command's link is written the same way: `{"binary": [...], "target": "/opt/homebrew/bin/studio"}`, and
        // so is the link to a script Homebrew writes to run the app's program (`command_wrapper`).
        let linksACommand = raw["binary"] != nil || raw["command_wrapper"] != nil
        commandLinks = linksACommand ? (raw["target"]?.strings ?? []).filter { $0.hasPrefix("/") } : []

        var patterns: [String] = []
        var emptyFolders: [String] = []
        var quits: [String] = []
        var packages: [String] = []
        for key in ["uninstall", "zap"] {
            for stanza in raw[key]?.dictionaries ?? [] {
                for removal in Self.removalKeys {
                    patterns += stanza[removal]?.strings ?? []
                }
                emptyFolders += stanza["rmdir"]?.strings ?? []
                // `quit` is a string for most casks and a list for a few, like Docker Desktop.
                quits += stanza["quit"]?.strings ?? []
                packages += stanza["pkgutil"]?.strings ?? []
            }
        }
        leftoverPatterns = patterns
        emptyFolderPatterns = emptyFolders
        quitIdentifiers = quits
        packageIdentifiers = packages

        let runsAsRoot = { (script: CaskValue?) in (script?.dictionaries ?? []).contains { $0["sudo"]?.isTrue == true } }
        installNeedsAnAdministrator = raw["pkg"] != nil || (raw["installer"]?.dictionaries ?? []).contains { runsAsRoot($0["script"]) }
        uninstallNeedsAnAdministrator = (raw["uninstall"]?.dictionaries ?? []).contains { stanza in
            Self.stepsRunAsRoot.contains { stanza[$0] != nil } || runsAsRoot(stanza["script"]) || runsAsRoot(stanza["early_script"])
        }
    }
}

/// Anything a cask stanza can hold: a string, a list, a dictionary, or something Peel ignores.
indirect enum CaskValue: Decodable, Sendable {
    case string(String)
    case list([CaskValue])
    case dictionary([String: CaskValue])
    case boolean(Bool)
    case other

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([CaskValue].self) {
            self = .list(value)
        } else if let value = try? container.decode([String: CaskValue].self) {
            self = .dictionary(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else {
            self = .other
        }
    }

    var strings: [String] {
        switch self {
        case .string(let value): [value]
        case .list(let values): values.flatMap(\.strings)
        case .dictionary, .boolean, .other: []
        }
    }

    var dictionaries: [[String: CaskValue]] {
        switch self {
        case .dictionary(let value): [value]
        case .list(let values): values.flatMap(\.dictionaries)
        case .string, .boolean, .other: []
        }
    }

    var isTrue: Bool {
        if case .boolean(true) = self { true } else { false }
    }
}

public enum Homebrew {
    static let notInstalled = "Homebrew isn’t installed."

    /// Whether this account may change the Homebrew whose Cellar and repository these are, as `brew update` judges it
    /// (`cmd/update.sh`): the Cellar, when there is one, and the repository can be written. Homebrew belongs to the
    /// account that installed it, so another account of the Mac can read it and not change it.
    static func mayBeChanged(cellar: URL, repository: URL) -> Bool {
        func writable(_ url: URL) -> Bool { access(url.path(percentEncoded: false), W_OK) == 0 }
        return (cellar.isMissing || writable(cellar)) && writable(repository)
    }

    /// Whether `sudo` stopped for a password it had no terminal to ask in, in its own words, which it writes in English
    /// in the environment Peel runs Homebrew in.
    public static func askedForAPassword(in transcript: String) -> Bool {
        ["a terminal is required to read the password", "a password is required"].contains(where: transcript.contains)
    }
    /// The command brew.sh gives for installing Homebrew. Its script says what it will do and waits before doing it.
    public static let installCommand = "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    public static let website = URL(string: "https://brew.sh")!
    /// How long Homebrew lets its last check for new versions stand before it checks again on its own: the default of
    /// `HOMEBREW_AUTO_UPDATE_SECS` (`man brew`).
    public static let autoUpdateInterval: TimeInterval = 24 * 60 * 60

    public struct CommandFailure: Error, Sendable, Hashable {
        public let output: String
    }

    /// The `brew` executable: the one the person chose in Settings (`HomebrewChoice`), or else the one in either
    /// place Homebrew installs itself by default. An app not started from a shell doesn't get the login shell's
    /// `PATH`, so `which brew` would find nothing. Taking the prefix from the environment would let anything that
    /// can set `HOMEBREW_PREFIX` choose which program Peel runs.
    public static var executableURL: URL? {
        executable(chosen: HomebrewChoice().load())
    }

    /// The prefixes Homebrew installs itself in by default, from the root of the disk.
    static let usualPrefixes = ["opt/homebrew", "usr/local"]

    static let usualPlaces = usualPrefixes.map { URL(filePath: "/\($0)/bin/brew") }

    /// A `brew` in a usual place runs by the rule a chosen one does: this account's or root's, and nobody else can
    /// change it, since its code runs as this account whenever Peel asks Homebrew something.
    static func executable(chosen: URL?, usualPlaces: [URL] = Homebrew.usualPlaces, user: uid_t = getuid()) -> URL? {
        if let chosen { return HomebrewChoice.refusal(of: chosen, user: user) == nil ? chosen : nil }
        return usualPlaces.first { HomebrewChoice.refusal(of: $0, user: user) == nil }
    }

    /// The `brew` in a usual place that Peel won't run, and why, when none was chosen and none there can run.
    public static func refusedInAUsualPlace() -> HomebrewChoice.Unrunnable? {
        refusedInAUsualPlace(chosen: HomebrewChoice().load(), usualPlaces: usualPlaces)
    }

    static func refusedInAUsualPlace(
        chosen: URL?, usualPlaces: [URL], user: uid_t = getuid()
    ) -> HomebrewChoice.Unrunnable? {
        guard chosen == nil, executable(chosen: nil, usualPlaces: usualPlaces, user: user) == nil else { return nil }
        return usualPlaces.lazy.compactMap { brew in
            switch HomebrewChoice.refusal(of: brew, user: user) {
            case let refusal? where refusal == .ownedByAnotherAccount || refusal == .writableByEveryone:
                HomebrewChoice.Unrunnable(brew: brew, refusal: refusal)
            default: nil
            }
        }.first
    }

    /// Returns whether Homebrew's local copy of its definitions is on disk. Without it, any command that may read
    /// them makes Homebrew download the copy first, even with `HOMEBREW_NO_AUTO_UPDATE` set (`fetch_api_files!` in
    /// `brew.rb`, 7.0). So Peel looks for the copy itself, and runs nothing else when it is missing. Where Homebrew
    /// keeps it and the platform it is named for are asked of Homebrew with its API turned off, which keeps that
    /// question from downloading. Whether it reads its taps instead is what its `brew.env` files say, since Peel's
    /// own environment never sets it.
    @concurrent
    public static func hasLocalDefinitions() async -> Bool {
        await hasLocalDefinitions(home: .homeDirectory)
    }

    static func hasLocalDefinitions(home: URL) async -> Bool {
        guard executableURL != nil else { return false }
        let question = "puts HOMEBREW_CACHE; puts Utils::Bottles.tag; puts HOMEBREW_PREFIX; "
            + "puts ENV.fetch('HOMEBREW_USER_CONFIG_HOME', ''); "
            + "puts(CoreTap.instance.installed? && CoreCaskTap.instance.installed?)"
        guard let answer = try? await answer(["ruby", "-e", question], readsTheAPI: false, home: home) else {
            return false
        }
        let lines = answer.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.count == 5, !lines[0].isEmpty, !lines[1].isEmpty, !lines[2].isEmpty, !lines[3].isEmpty else {
            return false
        }
        let files = settingsFiles(
            system: URL(filePath: "/etc/homebrew/brew.env"),
            prefix: URL(filePath: lines[2], directoryHint: .isDirectory),
            userConfiguration: URL(filePath: lines[3], directoryHint: .isDirectory)
        )
        let cache = URL(filePath: lines[0], directoryHint: .isDirectory)
        let readsItsTaps = lines[4] == "true" && readsTheTaps(settingsIn: files)
        return hasLocalDefinitions(inCache: cache, tag: lines[1], readsTheTaps: readsItsTaps)
    }

    /// A settings file `bin/brew` reads from a shell that sets `XDG_CONFIG_HOME` to `~/.config`, and not when Peel runs
    /// it, since Peel runs it without the shell's settings and Homebrew then reads `~/.homebrew/brew.env`.
    public static func unreadSettingsFile(home: URL = .homeDirectory) -> URL? {
        let file = home.appending(path: ".config/homebrew/brew.env")
        var isFolder: ObjCBool = false
        let isThere = FileManager.default.fileExists(atPath: file.path(percentEncoded: false), isDirectory: &isFolder)
        return isThere && !isFolder.boolValue ? file : nil
    }

    /// The `brew.env` files `bin/brew` reads before every command, in its order: the system's, the prefix's, the
    /// user's, and the system's once more when it says it takes priority.
    static func settingsFiles(system: URL, prefix: URL, userConfiguration: URL) -> [URL] {
        let files = [
            system,
            prefix.appending(path: "etc/homebrew/brew.env"),
            userConfiguration.appending(path: "brew.env"),
        ]
        let takesPriority = setting("HOMEBREW_SYSTEM_ENV_TAKES_PRIORITY", in: [system]).map { !$0.isEmpty } == true
        return files + (takesPriority ? [system] : [])
    }

    /// Whether the last line among `files` that sets `HOMEBREW_NO_INSTALL_FROM_API` sets it to anything but blank,
    /// which makes Homebrew read its taps. Peel's own environment never sets it.
    static func readsTheTaps(settingsIn files: [URL]) -> Bool {
        let value = setting("HOMEBREW_NO_INSTALL_FROM_API", in: files) ?? ""
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The value the last line of `files` gives `name`, read as `bin/brew` reads them (`read -r`): a line counts only
    /// once it ends, trimmed of spaces and tabs, and the value is what follows the equals sign.
    static func setting(_ name: String, in files: [URL]) -> String? {
        var value: String?
        for file in files {
            guard let data = BoundedRead.data(at: file, maximum: 64 * 1_024) else { continue }
            let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
            for line in lines.dropLast() {
                let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
                if trimmed.hasPrefix(name + "=") {
                    value = String(trimmed.dropFirst(name.count + 1))
                }
            }
        }
        return value
    }

    /// Returns whether `cache` holds that copy. In Homebrew 6.0.0 and later, the copy is one file named for the
    /// platform Homebrew reads it for (`tag`), like `api/internal/packages.arm64_tahoe.jws.json`: a file left for
    /// an older macOS is no copy, since Homebrew downloads the one it wants. Earlier versions keep one file for
    /// formulae and one for casks (`cmd/update.sh` in 5.1.9), and both must be there: a query of either kind
    /// downloads its file when it is missing. A Homebrew that reads its taps needs neither.
    static func hasLocalDefinitions(inCache cache: URL, tag: String, readsTheTaps: Bool) -> Bool {
        guard !readsTheTaps else { return true }
        let api = cache.appending(path: "api", directoryHint: .isDirectory)
        let packages = api.appending(path: "internal/packages.\(tag).jws.json")
        if FileManager.default.fileExists(atPath: packages.path(percentEncoded: false)) { return true }
        return ["formula.jws.json", "cask.jws.json"].allSatisfy {
            FileManager.default.fileExists(atPath: api.appending(path: $0).path(percentEncoded: false))
        }
    }

    /// When Homebrew last checked for new versions: when `brew update` last touched `.git/FETCH_HEAD` in its
    /// repository, which Homebrew compares with `HOMEBREW_AUTO_UPDATE_SECS`, or, while it reads its definitions from
    /// its API, when it last downloaded or confirmed them, whichever is later. Nil when neither can be found.
    @concurrent
    public static func lastUpdateCheck() async -> Date? {
        guard let answer = try? await answer(["--repository"]), let repository = folder(answering: answer) else {
            return nil
        }
        guard let executable = executableURL, let cache = (try? await self.answer(["--cache"])).flatMap(folder(answering:))
        else { return lastUpdateCheck(inRepository: repository) }
        let files = settingsFiles(
            system: URL(filePath: "/etc/homebrew/brew.env"),
            prefix: executable.deletingLastPathComponent().deletingLastPathComponent(),
            userConfiguration: URL.homeDirectory.appending(path: ".homebrew", directoryHint: .isDirectory)
        )
        return lastUpdateCheck(inRepository: repository, cache: cache, readsTheTaps: readsTheTaps(settingsIn: files))
    }

    static func lastUpdateCheck(inRepository repository: URL, cache: URL, readsTheTaps: Bool) -> Date? {
        let fetched = lastUpdateCheck(inRepository: repository)
        guard !readsTheTaps else { return fetched }
        return ([fetched] + definitionsChecks(inCache: cache)).compactMap(\.self).max()
    }

    /// The dates of the packages files in Homebrew's API cache, which it sets at every download or revalidation
    /// (`api.rb`). One it pins to 1970, after a download it couldn't verify, says nothing.
    static func definitionsChecks(inCache cache: URL) -> [Date] {
        let folder = cache.appending(path: "api/internal", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasPrefix("packages.") && $0.hasSuffix(".jws.json") }
            .compactMap { FileIdentity.of(folder.appending(path: $0))?.modificationDate }
            .filter { $0 > Date(timeIntervalSince1970: 2 * 24 * 60 * 60) }
    }

    /// Homebrew reads the file only as a regular file (`find -type f` in `utils/auto-update.sh`), never through a link.
    static func lastUpdateCheck(inRepository repository: URL) -> Date? {
        FileIdentity.of(repository.appending(path: ".git/FETCH_HEAD"))?.modificationDate
    }

    @concurrent
    public static func installedPackages() async throws(CommandFailure) -> [HomebrewPackage] {
        try await installed().packages
    }

    /// The installed packages, each with what Homebrew's own settings make of it, and those settings, or nil when
    /// Homebrew would not say them.
    public static func installed() async throws(CommandFailure)
        -> (packages: [HomebrewPackage], overrides: Overrides?) {
        // Read first, so a check made while the packages are read leaves them dated older than they are, never newer.
        let checked = await lastUpdateCheck()
        async let settings = overrides()
        let output = try await answer(["info", "--json=v2", "--installed"])
        let caskroom = (try? await answer(["--caskroom"])).flatMap(folder(answering:))
        guard let packages = parseInstalled(Data(output.utf8), caskroom: caskroom) else {
            throw CommandFailure(output: output)
        }
        let overrides = await settings
        let noted = packages.map { $0.noting(lastUpdateCheck: checked).noting(overrides) }
        return (await checkedOnThisMac(noted, pkgutil: PackageReceipts.pkgutil), overrides)
    }

    /// The installed packages with what this Mac says of them: the receipts their casks name, where those packages
    /// wrote apps, and whether their apps are gone.
    static func checkedOnThisMac(
        _ packages: [HomebrewPackage],
        pkgutil: @escaping PackageReceipts.Pkgutil
    ) async -> [HomebrewPackage] {
        let receipts = await PackageReceipts.identifiers(pkgutil: pkgutil)
        return await packages.concurrentMap(width: PackageReceipts.concurrentReceipts) { package in
            let apps = await PackageReceipts.apps(
                installedByPackagesMatching: package.packageIdentifiers, pkgutil: pkgutil
            )
            return package.noting(receipts: receipts).noting(packagedApps: apps).checkingWhatItInstalled()
        }
    }

    /// Returns the name of every cask Homebrew knows of, read from its local copy of the definitions. It needs
    /// no network and is quick enough to ask on every scan.
    @concurrent
    public static func caskTokens() async -> Set<String> {
        guard let output = try? await answer(["casks"]) else { return [] }
        return Set(
            output.split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
    }

    /// Returns the name of every formula Homebrew knows of, read from its local copy of the definitions.
    @concurrent
    public static func formulaNames() async -> Set<String> {
        guard let output = try? await answer(["formulae"]) else { return [] }
        return Set(
            output.split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
    }

    /// Asks about several formulae in one call. A single unknown name makes the whole call fail, so only names from
    /// `formulaNames()` are ever passed in.
    @concurrent
    public static func formulae(named names: [String]) async -> [HomebrewPackage] {
        guard !names.isEmpty else { return [] }
        guard let output = try? await answer(["info", "--json=v2", "--formula"] + names) else { return [] }
        return parseInstalled(Data(output.utf8))?.filter { $0.kind == .formula } ?? []
    }

    /// Asks about several casks in one call, which is quicker than asking about each on its own. A single
    /// unknown name makes the whole call fail, so only names from `caskTokens()` are ever passed in.
    @concurrent
    public static func casks(named tokens: [String]) async -> [HomebrewPackage] {
        guard !tokens.isEmpty else { return [] }
        guard let output = try? await answer(["info", "--json=v2", "--cask"] + tokens) else { return [] }
        return parseInstalled(Data(output.utf8))?.filter { $0.kind == .cask } ?? []
    }

    /// Upgrades `package` with no time limit, since Homebrew builds some packages on this Mac and that can take
    /// hours: `onOutput` is handed what Homebrew writes as it writes it, so the person can follow it, and the
    /// upgrade stops when its task is canceled.
    @concurrent
    public static func upgrade(
        _ package: HomebrewPackage,
        onOutput: @escaping @Sendable (Data) -> Void
    ) async throws(CommandFailure) -> String {
        let arguments = ["upgrade", package.kind == .cask ? "--cask" : "--formula", package.name]
        return try await execute(arguments, autoUpdate: true, timeout: nil, inWritingOrder: true, onOutput: onOutput)
            .transcript()
    }

    /// Upgrades `packages` the same way.
    @concurrent
    public static func upgrade(
        _ packages: [HomebrewPackage],
        onOutput: @escaping @Sendable (Data) -> Void
    ) async throws(CommandFailure) -> String {
        // Said once: both calls below would fail the same way.
        guard executableURL != nil else { throw CommandFailure(output: notInstalled) }
        return try await upgrade(packages) { arguments throws(CommandFailure) in
            try await execute(arguments, autoUpdate: true, timeout: nil, inWritingOrder: true, onOutput: onOutput)
        }
    }

    /// Formulae and casks go in separate calls because a name can belong to both. Both are attempted even when
    /// the first fails, whether `brew` reported the failure or never finished, so the report covers the whole
    /// run, but nothing starts once the person has stopped it. `execute` is a parameter so a test can stand in for
    /// `brew`.
    static func upgrade(
        _ packages: [HomebrewPackage],
        execute: (_ arguments: [String]) async throws(CommandFailure) -> Attempt
    ) async throws(CommandFailure) -> String {
        var output = ""
        var didFail = false
        for kind in [HomebrewPackage.Kind.formula, .cask] where !Task.isCancelled {
            let names = packages.filter { $0.kind == kind }.map(\.name)
            guard !names.isEmpty else { continue }
            do {
                let attempt = try await execute(["upgrade", kind == .cask ? "--cask" : "--formula"] + names)
                output += attempt.output
                didFail = didFail || attempt.status != 0
            } catch {
                // A failure is one sentence with no line ending, and the next call's report starts on a line of
                // its own.
                output += error.output.hasSuffix("\n") ? error.output : error.output + "\n"
                didFail = true
            }
        }
        guard !didFail else { throw CommandFailure(output: output) }
        return output
    }

    /// Returns the version and prefix of the Homebrew at `executableURL`. The prefix is the folder holding the
    /// `bin` that `brew` was found in, never one the environment names.
    @concurrent
    public static func installation() async -> HomebrewInstallation? {
        guard executableURL != nil, let version = try? await answer(["--version"]) else { return nil }
        let found = installation(
            versionAnswer: version,
            prefixAnswer: try? await answer(["--prefix"]),
            cellarAnswer: try? await answer(["--cellar"]),
            repositoryAnswer: try? await answer(["--repository"])
        )
        return found?.judgedForThisAccount()
    }

    /// The installation as Homebrew describes it. Its prefix and Cellar are asked, never worked out from where `brew`
    /// is: run from its repository, `bin/brew` moves the prefix to /usr/local when /usr/local/bin/brew leads there, and
    /// the Cellar is in the repository when there is one.
    static func installation(
        versionAnswer: String,
        prefixAnswer: String?,
        cellarAnswer: String?,
        repositoryAnswer: String? = nil
    ) -> HomebrewInstallation? {
        // The first line is `Homebrew <version>`; anything under it names a tap.
        guard let first = versionAnswer.split(whereSeparator: \.isNewline).first else { return nil }
        let line = first.trimmingCharacters(in: .whitespaces)
        let label = "Homebrew "
        let version = line.hasPrefix(label) ? String(line.dropFirst(label.count)) : line
        guard !version.isEmpty, let prefix = prefixAnswer.flatMap(folder(answering:)),
              let cellar = cellarAnswer.flatMap(folder(answering:))
        else { return nil }
        return HomebrewInstallation(
            version: version,
            prefix: URL(filePath: PathPattern.comparablePath(of: prefix), directoryHint: .notDirectory),
            cellar: cellar,
            repository: repositoryAnswer.flatMap(folder(answering:))
        )
    }

    /// Homebrew's own Brewfile for this Mac, from `brew bundle dump`: the taps with the addresses they came from,
    /// what was installed on request, and what this Mac trusts, as `brew bundle` reads them back on a new Mac.
    /// Like `installedPackages()`, it is asked only once Homebrew's definitions are on this Mac.
    @concurrent
    public static func brewfile(from installation: HomebrewInstallation) async throws(CommandFailure) -> String {
        guard installation.writesABrewfile else {
            throw CommandFailure(
                output: "Homebrew \(installation.version) keeps `brew bundle` in a tap it would download. "
                    + "Run `brew update` first."
            )
        }
        return try await answer(["bundle", "dump", "--file=-", "--tap", "--formula", "--cask"])
    }

    /// What `brew cleanup` would do, as its dry run says.
    public struct CleanupPreview: Sendable, Hashable {
        /// What it would free, leaving out the formulae it would autoremove. Nil when Homebrew's words can't be read.
        public let bytes: Int64?
        /// The formulae it would uninstall for good because nothing needs them anymore.
        public let autoremoved: [String]
    }

    /// What `brew cleanup` would do. Nothing is removed: `--dry-run` only reports.
    @concurrent
    public static func cleanupPreview(
        asWrittenBy installation: HomebrewInstallation?, keeping kept: [String]
    ) async -> CleanupPreview? {
        guard let output = try? await execute(
            ["cleanup", "--dry-run"], autoUpdate: false, keeping: kept, timeout: longestAnswer
        ).answer() else { return nil }
        return CleanupPreview(
            bytes: reclaimableBytes(in: output, countsInThousands: installation?.countsInThousands ?? true),
            autoremoved: autoremovedFormulae(in: output)
        )
    }

    /// Reads the formulae named under the "Would autoremove" headline, one to a line.
    static func autoremovedFormulae(in output: String) -> [String] {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        guard let headline = lines.firstIndex(where: { $0.hasPrefix("==> Would autoremove") }) else { return [] }
        return Array(lines[(headline + 1)...].prefix { !$0.isEmpty && !$0.contains(" ") })
    }

    /// Reads the total from the one sentence where Homebrew gives it, such as "would free approximately
    /// 61.2MB". Homebrew prints it only when the total is not zero, and lists every file it would remove
    /// ("Would remove: <path> (<size>)"), so a run that lists no file frees nothing. Output worded any other way
    /// gives nil rather than a made-up figure. Homebrew's largest unit is GB.
    static func reclaimableBytes(in output: String, countsInThousands: Bool) -> Int64? {
        guard output.contains("would free approximately") || output.contains("Would remove: ") else { return 0 }
        guard let match = output.firstMatch(of: /would free approximately ([0-9]+(?:\.[0-9]+)?)(GB|MB|KB|B)/),
              let size = Double(match.1)
        else { return nil }
        let step = countsInThousands ? 1000.0 : 1024.0
        let multiplier: Double = switch match.2 {
        case "B": 1
        case "KB": step
        case "MB": step * step
        default: step * step * step
        }
        // `Int64(exactly:)` gives nil for a figure too large to hold, where `Int64(_:)` would crash.
        return Int64(exactly: (size * multiplier).rounded())
    }

    /// Returns what `brew doctor --json` found. Only a Homebrew whose `reportsHealthAsJSON` is true understands
    /// it; an older one is asked for `healthReport()` instead.
    @concurrent
    public static func health() async throws(CommandFailure) -> [HomebrewFinding] {
        let attempt = try await execute(
            ["doctor", "--json"], autoUpdate: false, timeout: longestCommand, writesLinesAsTheyGo: false
        )
        guard let report = try? JSONDecoder().decode(DoctorReport.self, from: Data(attempt.standardOutput.utf8)) else {
            throw CommandFailure(output: attempt.output)
        }
        return report.findings.map(\.finding)
    }

    @concurrent
    public static func vulnerabilities() async throws(CommandFailure) -> HomebrewVulnerabilityReport {
        let attempt = try await execute(["vulns", "--json"], autoUpdate: false, timeout: longestCommand)
        guard
            var report = (try? JSONDecoder().decode(VulnsReport.self, from: Data(attempt.standardOutput.utf8)))?.report
        else {
            throw CommandFailure(output: attempt.output)
        }
        report.caveats = attempt.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        return report
    }

    /// Returns what `brew doctor` prints, for a Homebrew that cannot be asked for JSON.
    @concurrent
    public static func healthReport() async -> String {
        let attempt = try? await execute(
            ["doctor"], autoUpdate: false, timeout: longestCommand, inWritingOrder: true, writesLinesAsTheyGo: false
        )
        return attempt?.output ?? ""
    }

    /// `kept` are the formulae Homebrew must not autoremove afterward.
    @concurrent
    public static func uninstall(
        _ package: HomebrewPackage, keeping kept: [String]
    ) async throws(CommandFailure) -> String {
        let arguments = ["uninstall", package.kind == .cask ? "--cask" : "--formula", package.name]
        return try await execute(
            arguments, autoUpdate: false, keeping: kept, timeout: longestCommand, inWritingOrder: true
        ).transcript()
    }

    @concurrent
    public static func updateMetadata() async throws(CommandFailure) -> String {
        try await run(["update"], autoUpdate: false)
    }

    /// How much `brew cleanup` removes, each besides the old versions and the formulae nothing needs (`brew cleanup
    /// --help`): what Homebrew judges stale, every cache file older than some days, or every download but those of
    /// what is installed now.
    public enum Cleanup: Sendable, Hashable {
        case standard
        case olderThan(days: Int)
        case everyDownload

        var arguments: [String] {
            switch self {
            case .standard: ["cleanup"]
            case .olderThan(let days): ["cleanup", "--prune=\(days)"]
            case .everyDownload: ["cleanup", "--scrub"]
            }
        }
    }

    /// `kept` are the formulae Homebrew must neither clean up nor autoremove.
    @concurrent
    public static func cleanup(
        _ cleanup: Cleanup = .standard, keeping kept: [String]
    ) async throws(CommandFailure) -> String {
        try await execute(
            cleanup.arguments, autoUpdate: false, keeping: kept, timeout: longestCommand, inWritingOrder: true
        ).transcript()
    }

    static let repairTapsArguments = ["tap", "--repair"]

    /// Adds the links a tap's manual pages and completions are missing, and corrects a tap whose upstream renamed its
    /// main branch (`brew tap --help`). It deletes nothing.
    @concurrent
    public static func repairTaps() async throws(CommandFailure) -> String {
        try await execute(repairTapsArguments, autoUpdate: false, timeout: longestCommand, inWritingOrder: true)
            .transcript()
    }

    /// True when Homebrew, its own `brew.env` files read, still keeps every formula in `kept`. Such a file can
    /// replace the list Peel gives it, and `brew config` says what is in effect.
    @concurrent
    public static func keepsEvery(_ kept: [String]) async -> Bool {
        guard !kept.isEmpty else { return true }
        guard let config = try? await execute(["config"], autoUpdate: false, keeping: kept, timeout: longestAnswer)
            .answer() else { return false }
        return Set(kept).isSubset(of: keptFormulae(inConfig: config))
    }

    /// `command` for the person to run in Terminal, telling Homebrew to keep `kept`, the formulae the exclusions
    /// cover, as Peel's own runs do: an upgrade cleans up after itself and an uninstall removes what nothing needs,
    /// both for good. The list is quoted, since a folder in the Cellar can be called anything.
    public static func terminalCommand(_ command: String, keeping kept: [String]) -> String {
        guard !kept.isEmpty else { return command }
        let list = kept.joined(separator: ",").replacingOccurrences(of: "'", with: "'\\''")
        return "HOMEBREW_NO_CLEANUP_FORMULAE='\(list)' \(command)"
    }

    /// Reads the `HOMEBREW_NO_CLEANUP_FORMULAE: a,b` line of `brew config`'s answer.
    static func keptFormulae(inConfig config: String) -> Set<String> {
        let prefix = "HOMEBREW_NO_CLEANUP_FORMULAE: "
        let lines = config.split(whereSeparator: \.isNewline)
        guard let line = lines.first(where: { $0.hasPrefix(prefix) }) else { return [] }
        return Set(line.dropFirst(prefix.count).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }

    static func folder(answering answer: String) -> URL? {
        let lines = answer.split(whereSeparator: \.isNewline)
        guard lines.count == 1, let path = lines.first.map(String.init), path.hasPrefix("/") else { return nil }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    static func parseInstalled(_ data: Data, caskroom: URL? = nil) -> [HomebrewPackage]? {
        guard let response = try? JSONDecoder().decode(InfoResponse.self, from: data) else { return nil }

        let formulae = response.formulae.map { formula in
            HomebrewPackage(
                name: formula.name,
                kind: .formula,
                fullName: formula.fullName,
                summary: formula.desc,
                homepage: formula.homepage.flatMap(URL.init(string:)),
                installedVersion: formula.installed.last?.version,
                latestVersion: formula.versions.stable.map { stable in
                    (formula.revision ?? 0) > 0 ? "\(stable)_\(formula.revision ?? 0)" : stable
                },
                isOutdated: formula.outdated ?? false,
                isPinned: formula.pinned ?? false,
                isInstalledOnRequest: formula.installed.contains { $0.isInstalledOnRequest == true },
                dependencies: formula.dependencies ?? [],
                retirement: formula.retirement.value
            )
        }
        let casks = response.casks.map { cask in
            let package = HomebrewPackage(
                name: cask.token,
                kind: .cask,
                fullName: cask.fullToken,
                summary: cask.desc,
                homepage: cask.homepage.flatMap(URL.init(string:)),
                installedVersion: cask.installed,
                latestVersion: cask.version,
                isOutdated: cask.outdated ?? false,
                isPinned: cask.pinned ?? false,
                isInstalledOnRequest: true,
                dependencies: [],
                appNames: cask.artifacts?.flatMap(\.appNames) ?? [],
                appTargets: cask.artifacts?.flatMap(\.appTargets) ?? [],
                commandLinks: cask.artifacts?.flatMap(\.commandLinks) ?? [],
                leftoverPatterns: cask.artifacts?.flatMap(\.leftoverPatterns) ?? [],
                emptyFolderPatterns: cask.artifacts?.flatMap(\.emptyFolderPatterns) ?? [],
                quitIdentifiers: cask.artifacts?.flatMap(\.quitIdentifiers) ?? [],
                packageIdentifiers: cask.artifacts?.flatMap(\.packageIdentifiers) ?? [],
                retirement: cask.retirement.value,
                upgradeNeedsAnAdministrator: cask.artifacts?.contains {
                    $0.installNeedsAnAdministrator || $0.uninstallNeedsAnAdministrator
                } ?? false,
                uninstallNeedsAnAdministrator: cask.artifacts?.contains(where: \.uninstallNeedsAnAdministrator)
                    ?? false,
                appUpdatesItself: cask.autoUpdates ?? false
            )
            guard let caskroom, cask.installed != nil else { return package }
            return package.kept(inCaskroom: caskroom)
        }
        return (formulae + casks).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The time limit for a command that can run long, such as an uninstall or a cleanup. An upgrade has none.
    private static let longestCommand: TimeInterval = 30 * 60
    /// The time limit for a question Homebrew answers from its local files.
    private static let longestAnswer: TimeInterval = 2 * 60

    /// Runs a command whose output is shown to the user, and returns everything it printed.
    private static func run(_ arguments: [String], autoUpdate: Bool) async throws(CommandFailure) -> String {
        try await execute(arguments, autoUpdate: autoUpdate, timeout: longestCommand, inWritingOrder: true)
            .transcript()
    }

    /// Runs a command whose output Peel reads (JSON, a path, a list, or a version), and returns its stdout.
    private static func answer(
        _ arguments: [String], readsTheAPI: Bool = true, home: URL = .homeDirectory
    ) async throws(CommandFailure) -> String {
        try await execute(arguments, autoUpdate: false, timeout: longestAnswer, readsTheAPI: readsTheAPI, home: home)
            .answer()
    }

    struct Attempt {
        let status: Int32
        let standardOutput: String
        let standardError: String

        var output: String { standardOutput + standardError }

        /// Homebrew writes warnings to stderr and still exits 0, so an answer is what came on stdout alone:
        /// JSON with a warning after it is not JSON.
        func answer() throws(CommandFailure) -> String {
            guard status == 0 else { throw CommandFailure(output: output) }
            return standardOutput
        }

        func transcript() throws(CommandFailure) -> String {
            guard status == 0 else { throw CommandFailure(output: output) }
            return output
        }
    }

    /// Runs `brew`, or `executable` when a test stands in for it, since a real upgrade would change this Mac. A run
    /// shown to the person keeps what Homebrew writes `inWritingOrder`: its warnings and errors among its steps.
    static func execute(
        _ arguments: [String],
        autoUpdate: Bool,
        keeping kept: [String] = [],
        timeout: TimeInterval?,
        inWritingOrder: Bool = false,
        onOutput: (@Sendable (Data) -> Void)? = nil,
        executable: URL? = executableURL,
        readsTheAPI: Bool = true,
        home: URL = .homeDirectory,
        writesLinesAsTheyGo: Bool = true
    ) async throws(CommandFailure) -> Attempt {
        guard let executable else {
            throw CommandFailure(output: Self.notInstalled)
        }
        let path = executable.path(percentEncoded: false)
        let environment = environment(
            autoUpdate: autoUpdate, keeping: kept, executable: executable, readsTheAPI: readsTheAPI, home: home,
            writesLinesAsTheyGo: writesLinesAsTheyGo
        )
        switch await Subprocess.run(
            path, arguments, environment: environment, timeout: timeout, errorsIntoOutput: inWritingOrder,
            onOutput: onOutput
        ) {
        case .success(let output):
            return Attempt(status: output.status, standardOutput: output.text, standardError: output.errorText)
        case .failure(let failure):
            // A run someone follows shows Peel's own sentence where it happened, after what the tool wrote.
            onOutput?(Data((failure.explanation + "\n").utf8))
            throw CommandFailure(output: failure.explanation)
        }
    }

    /// What Homebrew's own settings undo of the environment Peel runs it in, or change of what it tells Peel.
    /// `bin/brew` reads `brew.env` files after that environment (`/etc/homebrew`, the prefix's `etc/homebrew`, and
    /// `~/.homebrew`), and a line there with no value turns one of Peel's settings off.
    public struct Overrides: OptionSet, Sendable, Hashable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// An upgrade runs `brew cleanup` by itself, which deletes old versions for good.
        public static let cleansUp = Overrides(rawValue: 1 << 0)
        /// Homebrew sends analytics when Peel runs it.
        public static let sendsAnalytics = Overrides(rawValue: 1 << 1)
        /// Homebrew may update its package lists, over the network, when Peel only asks about them.
        public static let updatesItself = Overrides(rawValue: 1 << 2)
        /// Homebrew leaves casks whose apps update themselves to those apps, and never counts one outdated.
        public static let leavesAppsThatUpdateThemselves = Overrides(rawValue: 1 << 3)

        /// Reads `brew config`'s answer, which lists each setting in effect as `NAME: set`.
        init(config: String) {
            let set = Set(config.split(whereSeparator: \.isNewline).compactMap { line -> Substring? in
                guard line.hasSuffix(": set") else { return nil }
                return line.dropLast(": set".count)
            })
            self = []
            if !set.contains("HOMEBREW_NO_INSTALL_CLEANUP") { insert(.cleansUp) }
            if !set.contains("HOMEBREW_NO_ANALYTICS") { insert(.sendsAnalytics) }
            if !set.contains("HOMEBREW_NO_AUTO_UPDATE") || set.contains("HOMEBREW_FORCE_API_AUTO_UPDATE") { insert(.updatesItself) }
            if set.contains("HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS") { insert(.leavesAppsThatUpdateThemselves) }
        }
    }

    /// What Homebrew's own settings undo, as it says itself. Nil when it would not say.
    @concurrent
    public static func overrides() async -> Overrides? {
        guard let config = try? await answer(["config"]) else { return nil }
        return Overrides(config: config)
    }

    /// The environment every `brew` call runs in. It is built from nothing rather than inherited: a `HOMEBREW_*`
    /// value set anywhere in the user's session would otherwise decide how Homebrew behaves, and
    /// `HOMEBREW_FORCE_API_AUTO_UPDATE` would undo the setting that keeps Peel off the network. Homebrew's own
    /// `brew.env` files are read after it and can still undo a setting here, which `overrides()` reports.
    static func environment(
        autoUpdate: Bool, keeping kept: [String] = [], executable: URL? = nil, readsTheAPI: Bool = true,
        home: URL = .homeDirectory, writesLinesAsTheyGo: Bool = true
    ) -> [String: String] {
        var path = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        // A Homebrew in a prefix of its own finds its own programs first, as the default ones do.
        if let executable {
            let bin = (executable.path(percentEncoded: false) as NSString).deletingLastPathComponent
            let sbin = ((bin as NSString).deletingLastPathComponent as NSString).appendingPathComponent("sbin")
            if !path.split(separator: ":").contains(Substring(bin)) {
                path = "\(bin):\(sbin):" + path
            }
        }
        var values = [
            "PATH": path,
            "HOME": home.path(percentEncoded: false),
            "HOMEBREW_NO_ENV_HINTS": "1",
            // Without this every call pings Homebrew's analytics over the network.
            "HOMEBREW_NO_ANALYTICS": "1",
            "HOMEBREW_NO_COLOR": "1",
            // Otherwise an upgrade runs `brew cleanup` by itself, which deletes old versions and downloads for
            // good. Peel deletes those only through Clean Up, which asks first.
            "HOMEBREW_NO_INSTALL_CLEANUP": "1",
            // `brew upgrade` asks before it goes on unless this is set, and nobody is there to answer. It skips
            // the question only because no terminal is attached (`ask.rb`). A version without it ignores it.
            "HOMEBREW_NO_ASK": "1",
        ]
        // `brew.rb` writes each line as it goes only under `CI`. Otherwise Ruby holds what goes to standard output back
        // in a pipe, and an error printed after a step shows before it. `brew doctor` reads `CI` as a CI run, though,
        // and leaves out its check of the taps' branches, so it is asked without it.
        if writesLinesAsTheyGo {
            values["CI"] = "1"
        }
        if !autoUpdate {
            values["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        }
        if !kept.isEmpty {
            values["HOMEBREW_NO_CLEANUP_FORMULAE"] = kept.joined(separator: ",")
        }
        if !readsTheAPI {
            values["HOMEBREW_NO_INSTALL_FROM_API"] = "1"
        }
        return values
    }

    struct VulnsReport: Decodable {
        struct Finding: Decodable {
            struct Vulnerability: Decodable {
                let id: String
                let severity: String?
                let summary: String?
                let aliases: [String]?
                let fixedVersions: [String]?

                enum CodingKeys: String, CodingKey {
                    case id, severity, summary, aliases
                    case fixedVersions = "fixed_versions"
                }
            }

            let formula: String
            let version: String?
            let vulnerabilities: [Vulnerability]
        }

        enum CodingKeys: String, CodingKey {
            case findings
            case skippedFormulae = "skipped_formulae"
            case outdatedWithoutSBOM = "outdated_without_sbom"
        }

        let findings: [Finding]
        let skippedFormulae: [String]?
        let outdatedWithoutSBOM: [String]?

        /// 6.0.11 to 6.0.18 write the findings as a list on its own, 6.0.19 and later inside an object.
        init(from decoder: any Decoder) throws {
            if let list = try? [Finding](from: decoder) {
                (findings, skippedFormulae, outdatedWithoutSBOM) = (list, nil, nil)
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            findings = try container.decode([Finding].self, forKey: .findings)
            skippedFormulae = try container.decodeIfPresent([String].self, forKey: .skippedFormulae)
            outdatedWithoutSBOM = try container.decodeIfPresent([String].self, forKey: .outdatedWithoutSBOM)
        }

        var report: HomebrewVulnerabilityReport {
            let current = Set(outdatedWithoutSBOM ?? [])
            // Leaves out a formula whose vulnerabilities are all patched, which `brew vulns` lists with none open.
            let advisories = findings.filter { !$0.vulnerabilities.isEmpty }.map { finding in
                var advisory = HomebrewAdvisory(
                    formula: finding.formula,
                    version: finding.version ?? "",
                    vulnerabilities: finding.vulnerabilities
                        .map {
                            HomebrewVulnerability(
                                id: $0.id,
                                aliases: $0.aliases ?? [],
                                severity: HomebrewVulnerability.Severity(name: $0.severity ?? ""),
                                summary: ($0.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                fix: HomebrewVulnerability.Fix(fixedIn: $0.fixedVersions ?? [])
                            )
                        }
                        .sorted {
                            $0.severity == $1.severity
                                ? $0.id.localizedStandardCompare($1.id) == .orderedAscending
                                : $0.severity > $1.severity
                        }
                )
                advisory.checkedTheCurrentFormula = current.contains(finding.formula)
                return advisory
            }
            var report = HomebrewVulnerabilityReport(
                advisories: advisories.sorted {
                    $0.highestSeverity == $1.highestSeverity
                        ? $0.formula.localizedStandardCompare($1.formula) == .orderedAscending
                        : $0.highestSeverity > $1.highestSeverity
                },
                skipped: (skippedFormulae ?? []).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            )
            report.checkedTheCurrentFormula = current.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            return report
        }
    }

    struct DoctorReport: Decodable {
        struct Finding: Decodable {
            struct Remediation: Decodable {
                let commands: [String]?
                let text: String?
            }

            let text: String
            let remediation: Remediation?

            var finding: HomebrewFinding {
                let remedy = remediation?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
                return HomebrewFinding(
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    remedy: (remedy?.isEmpty == false) ? remedy : nil,
                    commands: remediation?.commands ?? []
                )
            }
        }

        let findings: [Finding]
    }

    private struct InfoResponse: Decodable {
        /// The same fields on a formula and on a cask.
        struct Retirement: Decodable {
            enum CodingKeys: String, CodingKey {
                case deprecated, disabled
                case disableDate = "disable_date"
                case deprecationReason = "deprecation_reason"
                case disableReason = "disable_reason"
                case deprecationReplacementFormula = "deprecation_replacement_formula"
                case deprecationReplacementCask = "deprecation_replacement_cask"
                case disableReplacementFormula = "disable_replacement_formula"
                case disableReplacementCask = "disable_replacement_cask"
            }

            let deprecated: Bool?
            let disabled: Bool?
            let disableDate: String?
            let deprecationReason: String?
            let disableReason: String?
            let deprecationReplacementFormula: String?
            let deprecationReplacementCask: String?
            let disableReplacementFormula: String?
            let disableReplacementCask: String?

            var value: HomebrewRetirement? {
                HomebrewRetirement(
                    deprecated: deprecated, disabled: disabled, disableDate: disableDate,
                    deprecationReason: deprecationReason, disableReason: disableReason,
                    deprecationReplacement: (deprecationReplacementFormula, deprecationReplacementCask),
                    disableReplacement: (disableReplacementFormula, disableReplacementCask)
                )
            }
        }

        struct Formula: Decodable {
            struct Installed: Decodable {
                enum CodingKeys: String, CodingKey {
                    case version
                    case isInstalledOnRequest = "installed_on_request"
                }

                let version: String?
                let isInstalledOnRequest: Bool?
            }

            struct Versions: Decodable {
                let stable: String?
            }

            enum CodingKeys: String, CodingKey {
                case name, desc, homepage, installed, versions, revision, outdated, pinned, dependencies
                case fullName = "full_name"
            }

            let name: String
            let fullName: String?
            /// Homebrew's own rebuild of the same upstream version, written after an underscore: `1.11.1_5`.
            let revision: Int?
            let desc: String?
            let homepage: String?
            let installed: [Installed]
            let versions: Versions
            let outdated: Bool?
            let pinned: Bool?
            let dependencies: [String]?
        }

        struct Cask: Decodable {
            enum CodingKeys: String, CodingKey {
                case token, desc, homepage, installed, version, outdated, pinned, artifacts
                case fullToken = "full_token"
                case autoUpdates = "auto_updates"
            }

            let token: String
            let fullToken: String?
            let desc: String?
            let homepage: String?
            let installed: String?
            let version: String?
            let outdated: Bool?
            let pinned: Bool?
            let autoUpdates: Bool?
            /// Free-form stanzas such as `app`, `uninstall`, and `zap`. Only what `CaskArtifact` understands is read.
            let artifacts: [CaskArtifact]?
        }

        /// A formula or a cask with what it says about retirement, both read from the same object.
        @dynamicMemberLookup
        struct Retiring<Package: Decodable>: Decodable {
            let package: Package
            let retirement: Retirement

            init(from decoder: any Decoder) throws {
                package = try Package(from: decoder)
                retirement = try Retirement(from: decoder)
            }

            subscript<Value>(dynamicMember keyPath: KeyPath<Package, Value>) -> Value {
                package[keyPath: keyPath]
            }
        }

        let formulae: [Retiring<Formula>]
        let casks: [Retiring<Cask>]
    }
}
