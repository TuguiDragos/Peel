public import Foundation

/// One app in an inventory: what it is and where it came from. An inventory is written out to be read
/// elsewhere, to set up a new Mac the same way or to keep a record of what was on this one.
public struct InventoryEntry: Sendable, Hashable, Codable {
    public let name: String
    public let bundleIdentifier: String
    public let version: String?
    public let build: String?
    /// Where the app came from: "Homebrew", "App Store", "Setapp", "Sparkle", "Electron", "Downloaded", or "Unknown".
    public let source: String
    /// What identifies the app in that source: a cask token, a feed address, or the address it was downloaded from.
    public let sourceDetail: String?
    public let teamIdentifier: String?
    public let architectures: [String]
    public let path: String
    public let installedOn: Date?
    public let lastOpened: Date?

    /// Writes a missing value as `null` instead of leaving the key out, as the synthesized encoder would. Every
    /// object then has the same keys, so a reader never has to guess what a missing key means.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(version, forKey: .version)
        try container.encode(build, forKey: .build)
        try container.encode(source, forKey: .source)
        try container.encode(sourceDetail, forKey: .sourceDetail)
        try container.encode(teamIdentifier, forKey: .teamIdentifier)
        try container.encode(architectures, forKey: .architectures)
        try container.encode(path, forKey: .path)
        try container.encode(installedOn, forKey: .installedOn)
        try container.encode(lastOpened, forKey: .lastOpened)
    }
}

public struct Inventory: Sendable {
    public enum Format: String, Sendable, CaseIterable {
        case json
        case csv
        case text
        case brewfile
    }

    /// A Brewfile asked for while Homebrew did not answer: an empty one would read as a Mac with nothing to install.
    public struct HomebrewDidNotAnswer: Error {}

    public let entries: [InventoryEntry]
    /// What Homebrew says was installed on request, which is what a Brewfile has to reproduce.
    public let formulae: [String]
    public let casks: [String]
    /// The packages among them, by full name, that come from a tap outside Homebrew's own and are trusted.
    public var trusted: Set<String> = []
    /// False when Homebrew did not answer, so what it installed is not known.
    public var knowsHomebrew = true

    /// `casks` is what Homebrew installed, nil when it did not answer. `origins` looks up where downloaded apps
    /// came from. The app and `peel` pass `DownloadOrigins.onThisMac`. `trust` is what this Mac trusts, which only
    /// a Brewfile needs (`Homebrew.trust()`).
    public static func build(
        apps: [InstalledApp],
        casks: [HomebrewPackage]? = [],
        origins: DownloadOrigins? = nil,
        trust: HomebrewTrust = HomebrewTrust()
    ) -> Inventory {
        let entries = apps
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { app in entry(for: app, casks: casks ?? [], origins: origins) }
        let requested = (casks ?? []).filter(\.isInstalledOnRequest)
        return Inventory(
            entries: entries,
            formulae: requested.filter { $0.kind == .formula }.map(\.fullName).sorted(),
            casks: requested.filter { $0.kind == .cask }.map(\.fullName).sorted(),
            trusted: Set(requested.filter(trust.trusts).map(\.fullName)),
            knowsHomebrew: casks != nil
        )
    }

    static func entry(for app: InstalledApp, casks: [HomebrewPackage], origins: DownloadOrigins?) -> InventoryEntry {
        let cask = CaskEvidence.cask(for: app, in: casks)
        let (source, detail) = origin(of: app, cask: cask, origins: origins)
        return InventoryEntry(
            name: app.name,
            bundleIdentifier: app.bundleIdentifier,
            version: app.version,
            build: app.buildVersion,
            source: source,
            sourceDetail: detail,
            teamIdentifier: app.teamIdentifier,
            architectures: app.architectures.map(\.rawValue).sorted(),
            path: PathPattern.comparablePath(of: app.url),
            installedOn: app.dateAdded,
            lastOpened: app.lastUsedDate
        )
    }

    /// Homebrew comes first: a cask says exactly how to install the app again.
    static func origin(of app: InstalledApp, cask: HomebrewPackage?, origins: DownloadOrigins?) -> (String, String?) {
        if let cask {
            return ("Homebrew", cask.name)
        }
        if app.isFromAppStore {
            return ("App Store", nil)
        }
        // Setapp keeps its apps up to date itself, whatever feed they also carry.
        if app.isFromSetapp {
            return ("Setapp", nil)
        }
        // `.appStore` and `.gitHubRelease` only say where Peel asks about updates. The receipt inside the bundle
        // is the only thing that says an app was installed from the App Store.
        return switch app.updateFeed {
        case .sparkle(let url): ("Sparkle", url.absoluteString)
        case .electron(let url): ("Electron", url.absoluteString)
        case .appStore, .gitHubRelease, nil: origins?.address(of: app.url).map { ("Downloaded", $0.absoluteString) } ?? ("Unknown", nil)
        }
    }

    public func written(as format: Format) throws -> String {
        switch format {
        case .json: try json()
        case .csv: csv()
        case .text: text()
        case .brewfile: try brewfile()
        }
    }

    private func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        // Ends in a newline like the other three: what is written to a file, and what a shell prints.
        return String(decoding: try encoder.encode(entries), as: UTF8.self) + "\n"
    }

    private func csv() -> String {
        let header = ["Name", "Bundle Identifier", "Version", "Build", "Source", "Source Detail", "Team", "Architectures", "Path", "Installed On", "Last Opened"]
        let rows = entries.map { entry in
            [
                entry.name,
                entry.bundleIdentifier,
                entry.version ?? "",
                entry.build ?? "",
                entry.source,
                entry.sourceDetail ?? "",
                entry.teamIdentifier ?? "",
                entry.architectures.joined(separator: " "),
                entry.path,
                entry.installedOn.map { Self.day($0) } ?? "",
                entry.lastOpened.map { Self.day($0) } ?? "",
            ]
        }
        return ([header] + rows)
            .map { $0.map { Self.escaped(PlainText.of($0)) }.joined(separator: ",") }
            .joined(separator: "\n") + "\n"
    }

    /// A line per app. Its name and version come from the app's own bundle, so each is shown plain (`PlainText`).
    private func text() -> String {
        entries.map { entry in
            var line = PlainText.of(entry.name)
            if let version = entry.version {
                line += " \(PlainText.of(version))"
            }
            line += ", \(entry.source)"
            if let detail = entry.sourceDetail, entry.source == "Homebrew" {
                line += " (\(PlainText.of(detail)))"
            }
            return line
        }
        .joined(separator: "\n") + "\n"
    }

    /// Lists only what Homebrew can install again, taken from what Homebrew says is installed. Each package is
    /// written under its full name, so Homebrew adds a third-party package's tap by itself, and one this Mac
    /// trusts says so, as `brew bundle dump` writes it.
    private func brewfile() throws -> String {
        guard knowsHomebrew else { throw HomebrewDidNotAnswer() }
        func line(_ kind: String, _ name: String) -> String {
            "\(kind) \"\(name)\"" + (trusted.contains(name) ? ", trusted: true" : "")
        }
        let lines = formulae.map { line("brew", $0) } + casks.map { line("cask", $0) }
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    /// Formats `date` as a day in `timeZone`, the user's by default. `ISO8601FormatStyle` counts in UTC unless
    /// told otherwise, which would put a time just after midnight east of Greenwich on the day before.
    public static func day(_ date: Date, timeZone: TimeZone = .current) -> String {
        date.formatted(Date.ISO8601FormatStyle(dateSeparator: .dash, timeZone: timeZone).year().month().day())
    }

    /// Characters that make a spreadsheet read a field as a formula rather than as text. Names and versions come
    /// from each app's own `Info.plist`, so a field that starts with one of them is escaped.
    private static let formulaStarts: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]

    private static func escaped(_ field: String) -> String {
        var field = field
        if let first = field.first, formulaStarts.contains(first) {
            field = "'" + field
        }
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

extension Inventory.Format {
    public var fileExtension: String {
        switch self {
        case .json: "json"
        case .csv: "csv"
        case .text: "txt"
        case .brewfile: ""
        }
    }

}
