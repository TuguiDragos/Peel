public import Foundation
internal import PeelPrivileged

/// An app Peel has seen installed, kept after the app is gone. An app dragged to the Trash leaves its files
/// behind with nothing to name them, so Peel shows them under the remembered name instead of an identifier.
public struct RememberedApp: Sendable, Hashable, Codable, Identifiable {
    public let bundleIdentifier: String
    public let name: String
    public let teamIdentifier: String?
    public let lastSeen: Date
    /// Where it was the last time Peel saw it, which is worth showing when its files turn up later.
    public let lastPath: String

    public var id: String { bundleIdentifier }
}

extension RememberedApp {
    /// The app as it is now, when Peel cannot tell that it left: its bundle is still where Peel last saw it, the disk
    /// it was on is not connected, or macOS will not let Peel read its Info.plist. Nil once the place can be looked at
    /// and the app is not there.
    func stillInstalled() -> InstalledApp? {
        let place = URL(filePath: lastPath, directoryHint: .isDirectory)
        if let app = AppInspector.inspect(place), app.bundleIdentifier == bundleIdentifier { return app }
        guard place.isOnADiskNotConnected || AppInspector.isClosed(place) else { return nil }
        return InstalledApp(url: place, bundleIdentifier: bundleIdentifier, name: name, teamIdentifier: teamIdentifier)
    }
}

public struct AppMemory: Sendable {
    /// The most apps remembered, which is enough for any Mac. The least recently seen are dropped first.
    public static let maximumApps = 2000

    public let url: URL

    public init(url: URL = AppMemory.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL { url(inHome: .homeDirectory) }

    static func url(inHome home: URL) -> URL {
        PeelFolder.url(inHome: home).appending(path: "apps.json")
    }

    @concurrent
    public func load() async -> [RememberedApp] {
        // Taking the lock makes its file and folder, and a read must leave a home as it found it.
        guard !url.isMissing else { return [] }
        return FileLock.whileHeld(beside: url) { read() } ?? []
    }

    /// Records the apps currently installed, keeping every app seen before. Reading, merging, and writing happen
    /// under one lock, so two refreshes that overlap cannot lose each other's apps.
    @discardableResult
    @concurrent
    public func remember(_ apps: [InstalledApp], now: Date = .now) async -> [RememberedApp] {
        FileLock.whileHeld(beside: url) { remember(apps, now: now, onTopOf: read()) }
    }

    /// `known` is nil when the file cannot be read or reached. Its contents are then unknown, so it is never
    /// written over, and the apps currently installed are still returned for this run.
    private func remember(_ apps: [InstalledApp], now: Date, onTopOf known: [RememberedApp]?) -> [RememberedApp] {
        var byIdentifier = Dictionary(
            (known ?? []).map { ($0.bundleIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for app in apps where !app.isSystemProtected {
            guard let identifier = app.bundleIdentifier else { continue }
            byIdentifier[identifier] = RememberedApp(
                bundleIdentifier: identifier,
                name: app.name,
                teamIdentifier: app.teamIdentifier,
                lastSeen: now,
                lastPath: PathPattern.comparablePath(of: app.url)
            )
        }

        let kept = byIdentifier.values
            .sorted {
                $0.lastSeen != $1.lastSeen ? $0.lastSeen > $1.lastSeen : $0.bundleIdentifier < $1.bundleIdentifier
            }
            .prefix(Self.maximumApps)
            .map { $0 }
        if known != nil { write(kept) }
        return kept
    }

    /// Returns nil when the file cannot be read or reached. The file is the only record of apps that are gone,
    /// so a row that cannot be decoded costs only that row. The damaged file is first kept under another name,
    /// and when that fails, this returns nil so the file is left alone.
    private func read() -> [RememberedApp]? {
        guard !url.isMissing else { return [] }
        guard let data = BoundedRead.data(at: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let apps = try? decoder.decode([RememberedApp].self, from: data) { return apps }
        let readable = (try? decoder.decode([Row].self, from: data))?.compactMap(\.app) ?? []
        guard DamagedFile.setAside(url) != nil else { return nil }
        write(readable)
        return readable
    }

    /// One row of the file, decoded on its own. `app` is nil when the row is not a valid app.
    private struct Row: Decodable {
        let app: RememberedApp?

        init(from decoder: any Decoder) {
            app = try? RememberedApp(from: decoder)
        }
    }

    /// Returns the remembered app a leftover identifier belongs to: the same identifier, or else the longest one
    /// it starts with, so `com.example.app.helper` belongs to `com.example.app`. A two-part identifier
    /// (`md.obsidian`) is shaped like a maker's domain, which everything that maker ships starts with, so it never
    /// counts as a prefix. `LeftoverMatcher` follows the same rule.
    public static func app(for identifier: String, in remembered: [RememberedApp]) -> RememberedApp? {
        let lowercased = identifier.lowercased()
        if let exact = remembered.first(where: { $0.bundleIdentifier.lowercased() == lowercased }) {
            return exact
        }
        return remembered
            .filter {
                Identifier.componentCount(of: $0.bundleIdentifier) >= 3
                    && lowercased.hasPrefix($0.bundleIdentifier.lowercased() + ".")
            }
            .max { $0.bundleIdentifier.count < $1.bundleIdentifier.count }
    }

    private func write(_ apps: [RememberedApp]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(apps) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
