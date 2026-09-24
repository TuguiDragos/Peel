public import Foundation
internal import PeelPrivileged
internal import Security

/// The result of one scan for extensions.
public struct ExtensionScan: Sendable {
    public var extensions: [AppExtension] = []
    /// The kinds macOS gave no answer about: `pluginkit` lists app extensions and `systemextensionsctl` system
    /// extensions. No answer is not the same as finding none, so the list then holds only part of what is there.
    public var unanswered: Set<AppExtension.Kind> = []
}

/// A part of an app that macOS runs on its own, such as a Finder menu, a share sheet entry, a widget, or a
/// network filter. Peel only lists them: the user turns them on and off in System Settings, and removes one
/// by removing the app it came with.
public struct AppExtension: Sendable, Hashable, Identifiable {
    public init(
        id: String? = nil,
        identifier: String,
        name: String,
        kind: Kind,
        point: String?,
        owner: String?,
        url: URL?,
        election: Election,
        teamIdentifier: String?,
        reportedState: String?
    ) {
        self.id = id ?? identifier
        self.identifier = identifier
        self.name = name
        self.kind = kind
        self.point = point
        self.owner = owner
        self.url = url
        self.election = election
        self.teamIdentifier = teamIdentifier
        self.reportedState = reportedState
    }

    public enum Kind: String, Sendable, Hashable, CaseIterable {
        /// A `.appex` inside an app bundle, as listed by `pluginkit`.
        case appExtension
        /// A `.systemextension` or `.dext`. macOS installs a copy of its own, apart from the app.
        case systemExtension
    }

    /// The user's choice about an extension, or what macOS is doing with it. For an app extension, it comes
    /// from the tag `pluginkit` prints at the start of each line (`man pluginkit`): `+` elected to use, `-`
    /// elected to ignore, `!` elected for debugger use, `=` superseded by another plug-in, and `?` unknown. No
    /// tag (`asItCame`) means the user has not chosen, so macOS decides. For a system extension, it comes from
    /// the state `systemextensionsctl list` prints.
    public enum Election: String, Sendable, Hashable {
        case on
        case off
        case asItCame
        /// macOS has the extension but won't run it until the user allows it in System Settings. It is kept
        /// apart from `off` because the user never turned it off.
        case waitingForApproval
        /// macOS is removing the extension. Only one of the states that map here waits for a restart, so this
        /// case doesn't mean a restart is needed.
        case beingRemoved
        /// macOS is partway through a change to the extension, such as enabling or upgrading it.
        case changing
        /// Another copy of the same extension is the one macOS runs.
        case superseded
        /// `pluginkit`'s `?` (an unknown election state), or a system extension state Peel doesn't recognize.
        /// For the latter, `reportedState` holds the state as macOS printed it.
        case unknown
    }

    public let identifier: String
    public let name: String
    public let kind: Kind
    /// The identifier of the extension point it plugs into, such as `com.apple.FinderSync` for Finder. Nil when
    /// unknown, and always for a system extension.
    public let point: String?
    public let owner: String?
    /// The location of the copy macOS runs, or nil when it can't be found. No path is better than a wrong one.
    public let url: URL?
    public let election: Election
    public let teamIdentifier: String?
    /// The state `systemextensionsctl` printed, like `activated waiting for user`. Nil for an app extension,
    /// since `pluginkit` prints no such state.
    public let reportedState: String?
    /// Tells rows apart in a list. The identifier alone can't: while an app updates a system extension, macOS
    /// lists the old and the new version under the same identifier.
    public let id: String
}

public enum AppExtensions {
    /// The System Settings page where the user turns extensions on and off.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!

    /// Whether the extension at `path` is part of macOS, judged by the folder it sits in. These are left out,
    /// so the list shows only what apps added.
    static func isTheSystemsOwn(_ path: String) -> Bool {
        AppleCode.isInASystemFolder(path)
    }

    /// Runs a tool and returns its output, or nil when it gave no answer. A parameter so a test can say what
    /// macOS answers instead of asking it.
    typealias Runner = @Sendable (_ tool: String, _ arguments: [String]) async -> String?

    public static func scan(exclusions: Exclusions = .none) async -> ExtensionScan {
        await scan(exclusions: exclusions, run: run)
    }

    @concurrent
    static func scan(exclusions: Exclusions, run: Runner) async -> ExtensionScan {
        let apps = await appExtensions(run: run)
        let system = await systemExtensions(run: run)
        let found = (apps ?? []) + (system ?? [])
        return ExtensionScan(extensions: found
            .filter { extensionItem in
                guard !exclusions.excludes(bundleIdentifier: extensionItem.identifier) else { return false }
                return extensionItem.url.map { !exclusions.excludes($0) } ?? true
            }
            .sorted {
                let (one, other) = ($0.owner ?? "", $1.owner ?? "")
                guard one == other else { return one.localizedStandardCompare(other) == .orderedAscending }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            },
            unanswered: Set([apps == nil ? .appExtension : nil, system == nil ? .systemExtension : nil].compactMap(\.self))
        )
    }

    static func appExtensions(run: Runner) async -> [AppExtension]? {
        guard let output = await run("/usr/bin/pluginkit", ["-m", "-v"]) else { return nil }
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            guard let parsed = parse(String(line)), !isTheSystemsOwn(parsed.path) else { return nil }
            let url = URL(filePath: parsed.path, directoryHint: .isDirectory)
            let info = AppInspector.infoDictionary(in: url.appending(path: "Contents", directoryHint: .isDirectory))
            return AppExtension(
                identifier: parsed.identifier,
                name: Self.name(of: url, info: info),
                kind: .appExtension,
                point: extensionPoint(in: info),
                owner: owner(ofExtensionAt: parsed.path),
                url: url,
                election: parsed.election,
                teamIdentifier: nil,
                reportedState: nil
            )
        }
    }

    /// Whether the user turned `identifier` on but macOS runs a copy other than `own`, or a copy that is gone.
    /// Without `-A` or `-D`, `pluginkit` lists one copy per identifier, the one PlugInKit's discovery picks
    /// (`man pluginkit`). This matters because `FIFinderSyncController` reports on the calling app's own copy:
    /// with two copies of Peel installed, one of them reads "off" while System Settings shows the extension on.
    @concurrent
    public static func runsAnotherCopy(of identifier: String, than own: URL) async -> Bool {
        guard let listing = await run("/usr/bin/pluginkit", ["-m", "-v", "-i", identifier]) else { return false }
        return runsAnotherCopy(of: identifier, than: own, in: listing)
    }

    static func runsAnotherCopy(of identifier: String, than own: URL, in listing: String) -> Bool {
        let chosen = listing.split(whereSeparator: \.isNewline)
            .compactMap { parse(String($0)) }
            .first { $0.identifier == identifier && $0.election == .on }
        guard let chosen else { return false }
        let theirs = FileIdentity.Link.of(URL(filePath: chosen.path, directoryHint: .isDirectory).resolvingSymlinksInPath())
        return theirs != FileIdentity.Link.of(own.resolvingSymlinksInPath())
    }

    /// Parses one line of `pluginkit -m -v`, like `     com.example.thing(1.0)\t<uuid>\t<date>\t/path/to/Thing.appex`.
    /// A tag in front, such as `+` or `-`, gives the election.
    static func parse(_ line: String) -> (identifier: String, election: AppExtension.Election, path: String)? {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.count >= 4 else { return nil }
        let path = String(fields[3]).trimmingCharacters(in: .whitespaces)
        guard path.hasPrefix("/") else { return nil }

        var head = String(fields[0])
        let election: AppExtension.Election = switch head.first {
        case "+", "!": .on
        case "-": .off
        case "=": .superseded
        case "?": .unknown
        default: .asItCame
        }
        if election != .asItCame { head.removeFirst() }
        head = head.trimmingCharacters(in: .whitespaces)
        guard let identifier = identifier(before: head) else { return nil }
        return (identifier, election, path)
    }

    /// Returns the identifier in `head`, without the version in parentheses at its end. The version can hold
    /// parentheses of its own: `pluginkit` writes `((null))` for a bundle without one, and a version can read
    /// `(1.0 (23))`. So the identifier ends at the parenthesis that opens the version, not at the last `(`.
    static func identifier(before head: String) -> String? {
        guard !head.isEmpty else { return nil }
        guard head.hasSuffix(")") else { return head }
        var depth = 0
        var index = head.endIndex
        while index > head.startIndex {
            head.formIndex(before: &index)
            if head[index] == ")" {
                depth += 1
            } else if head[index] == "(" {
                depth -= 1
                guard depth == 0 else { continue }
                let identifier = String(head[head.startIndex..<index])
                return identifier.isEmpty ? nil : identifier
            }
        }
        return nil
    }

    /// The extension's display name, or else its bundle name, in the user's language when the bundle has a
    /// translation. Falls back to the file name.
    static func name(of url: URL, info: [String: Any]?) -> String {
        let localized = Bundle(url: url)?.localizedInfoDictionary
        return localized?["CFBundleDisplayName"] as? String ?? info?["CFBundleDisplayName"] as? String
            ?? localized?["CFBundleName"] as? String ?? info?["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent
    }

    /// The identifier of the extension point, read from `Info.plist`. An ExtensionKit bundle has no
    /// `NSExtension` and names its point under `EXAppExtensionAttributes` instead.
    static func extensionPoint(in info: [String: Any]?) -> String? {
        if let point = (info?["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String { return point }
        return (info?["EXAppExtensionAttributes"] as? [String: Any])?["EXExtensionPointIdentifier"] as? String
    }

    /// The name of the app the extension came with. This is the outermost app, so an extension inside
    /// Instruments inside Xcode belongs to Xcode.
    static func owner(ofExtensionAt path: String) -> String? {
        guard let end = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app", options: .backwards) : nil) else { return nil }
        return AppInspector.displayName(of: URL(filePath: String(path[..<end.lowerBound]) + ".app"))
    }

    static func systemExtensions(run: Runner) async -> [AppExtension]? {
        guard let output = await run("/usr/bin/systemextensionsctl", ["list"]) else { return nil }
        let records = systemExtensionRecords()
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            guard let row = parseSystemExtension(String(line)) else { return nil }
            let record = record(for: row.identifier, version: row.version, among: records)
            return AppExtension(
                // During an update, one identifier is listed twice, once for the old version and once for the new.
                id: [row.identifier, row.version].compactMap(\.self).joined(separator: " "),
                identifier: row.identifier,
                name: row.name,
                kind: .systemExtension,
                point: nil,
                owner: record?.container.flatMap(owner(ofExtensionAt:)),
                url: record?.staged,
                election: election(forSystemExtensionState: row.state),
                teamIdentifier: row.teamIdentifier,
                reportedState: row.state
            )
        }
    }

    /// Parses one row of `systemextensionsctl list`, laid out as
    /// `<enabled>\t<active>\t<team>\t<identifier> (<version>)\t<name>\t[<state>]`. The header row above each
    /// category has the same columns and is skipped, since its identifier column (`bundleID`) has no dot.
    static func parseSystemExtension(
        _ line: String
    ) -> (identifier: String, version: String?, name: String, teamIdentifier: String?, state: String)? {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
        guard fields.count >= 6, let bracketed = fields.last, bracketed.hasPrefix("["), bracketed.hasSuffix("]") else { return nil }
        let identifier = String(fields[3].prefix { $0 != " " })
        guard identifier.contains(".") else { return nil }
        let version = fields[3].dropFirst(identifier.count).trimmingCharacters(in: .whitespaces)
        return (
            identifier,
            version.hasPrefix("(") && version.hasSuffix(")") ? String(version.dropFirst().dropLast()) : nil,
            fields[4],
            fields[2].count == 10 ? fields[2] : nil,
            String(bracketed.dropFirst().dropLast())
        )
    }

    /// Maps a state printed by `systemextensionsctl` to an election. The names are `sysextd`'s own, printed
    /// with spaces where `sysextd` has underscores.
    static func election(forSystemExtensionState state: String) -> AppExtension.Election {
        switch state.replacing(" ", with: "_") {
        case "activated_enabled": .on
        case "activated_disabled": .off
        case "activated_waiting_for_user": .waitingForApproval
        case "terminated_waiting_to_uninstall_on_reboot", "terminating_for_uninstall",
             "terminating_for_uninstall_but_still_running", "terminating_for_uninstall_via_delegate",
             "uninstalling", "uninstalled": .beingRemoved
        case "activated_enabling", "activated_waiting_to_upgrade", "activated_waiting_to_upgrade_on_reboot",
             "terminating_for_disable", "terminating_for_disable_but_still_running",
             "terminating_for_upgrade_via_delegate", "validating", "validating_by_category": .changing
        default: .unknown
        }
    }

    /// What `/Library/SystemExtensions/db.plist` records about a system extension: where macOS staged the copy
    /// it runs (not the one inside the app), and which app requested it. One identifier can have a record per
    /// version, so the version is kept too.
    struct SystemExtensionRecord {
        let identifier: String
        let version: String?
        let staged: URL?
        let container: String?
    }

    /// The record of the extension `systemextensionsctl` listed: the one of its version, or the only one of its
    /// identifier. During an update an identifier has a record per version, and the other version's copy is not
    /// this one: no path is better than a wrong one.
    static func record(for identifier: String, version: String?, among records: [SystemExtensionRecord]) -> SystemExtensionRecord? {
        let named = records.filter { $0.identifier == identifier }
        return named.first { $0.version == version } ?? (named.count == 1 ? named.first : nil)
    }

    static func systemExtensionRecords(
        at url: URL = URL(filePath: "/Library/SystemExtensions/db.plist")
    ) -> [SystemExtensionRecord] {
        guard let entries = BoundedRead.propertyList(at: url)?["extensions"] as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let identifier = entry["identifier"] as? String else { return nil }
            let version = entry["bundleVersion"] as? [String: Any]
            let short = version?["CFBundleShortVersionString"] as? String
            let build = version?["CFBundleVersion"] as? String
            let staged = (entry["stagedBundleURL"] as? [String: Any])?["relative"] as? String
            return SystemExtensionRecord(
                identifier: identifier,
                version: [short, build].compactMap(\.self).joined(separator: "/"),
                staged: staged.flatMap(URL.init(string:)),
                container: (entry["container"] as? [String: Any])?["bundlePath"] as? String
            )
        }
    }

    /// Runs `tool` and returns its output, or nil when it could not run or failed. Nil means no answer, which
    /// is not the same as no extensions.
    private static func run(_ tool: String, _ arguments: [String]) async -> String? {
        guard case .success(let output) = await Subprocess.run(tool, arguments, timeout: 10) else { return nil }
        return output.status == 0 ? output.text : nil
    }
}

/// Tells whether code is Apple's own, from where it sits or from its signature, never from its name: any
/// bundle can call itself `com.apple.something`. Extensions and plug-ins both use it.
enum AppleCode {
    /// Whether `path` is inside `/System` or `/usr`, where macOS installs its own code. Not `/usr/local`, which
    /// System Integrity Protection leaves to administrators and Homebrew, nor the data volume, which macOS also
    /// names under `/System/Volumes/Data` and which holds what anybody installed.
    static func isInASystemFolder(_ path: String) -> Bool {
        let names = PathComponents.of(path)
        guard path.hasPrefix("/"), names.count > 1 else { return false }
        switch names[0] {
        case "usr": return names[1] != "local"
        case "System": return !(names[1] == "Volumes" && names.count > 2 && names[2] == "Data")
        default: return false
        }
    }

    static func isApples(_ url: URL) -> Bool {
        isInASystemFolder(url.path(percentEncoded: false)) || isSignedByApple(url)
    }

    /// Whether Apple itself signed the code at `url`. The requirement is `anchor apple`, because every
    /// Developer ID app also passes `anchor apple generic`. `kSecCSBasicValidateOnly` (`SecStaticCode.h`)
    /// skips hashing the executable, which is slow and not needed to know the signer, and checking the sealed
    /// resources, which some Apple components fail because of custom omit rules while their signature is
    /// sound. Skipping them can only turn a no into a yes, and a wrong yes only hides a row.
    private static func isSignedByApple(_ url: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            return false
        }
        var requirement: SecRequirement?
        guard
            SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement) == errSecSuccess,
            let requirement
        else { return false }
        let flags = SecCSFlags(rawValue: UInt32(kSecCSBasicValidateOnly))
        return SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess
    }
}
