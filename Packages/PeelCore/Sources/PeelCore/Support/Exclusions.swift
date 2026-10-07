public import Foundation
internal import PeelPrivileged

/// Paths and apps the user asked Peel to leave alone. Excluded items never appear in results and are never removed.
public struct Exclusions: Sendable, Codable, Hashable {
    public var paths: Set<URL> {
        didSet { spellings = Self.spellings(of: paths) }
    }

    public var bundleIdentifiers: Set<String> {
        didSet { appFolderNames = Self.folderNames(of: bundleIdentifiers) }
    }
    /// Every way each excluded path can be written, worked out whenever `paths` changes. A scan asks about
    /// every file it meets, and working the spellings out again for each one would cost several `lstat` calls.
    /// Each is kept as its names, since paths are compared name by name.
    private var spellings: [[String]] = []
    /// The excluded apps' identifiers, lowercase: what sits in a folder of that name is excluded with the app.
    private var appFolderNames: Set<String> = []
    /// True when the saved list exists but could not be read, so what the user excluded is unknown. Nothing is
    /// moved while this is true.
    public private(set) var isUnreadable = false
    /// False until the saved list has been read. Nothing is moved before, as for a list that cannot be read.
    public private(set) var hasBeenRead = true

    /// True when what the user excluded is known: the saved list was read, and could be.
    public var isKnown: Bool { hasBeenRead && !isUnreadable }

    public static let none = Exclusions()
    public static let unreadable: Exclusions = {
        var exclusions = Exclusions()
        exclusions.isUnreadable = true
        return exclusions
    }()
    /// The list before the saved one has been read.
    public static let notYetRead: Exclusions = {
        var exclusions = Exclusions()
        exclusions.hasBeenRead = false
        return exclusions
    }()

    private enum CodingKeys: String, CodingKey {
        case paths
        case bundleIdentifiers
    }

    /// Compares what is excluded. `spellings` and `appFolderNames` are left out, since they are worked out.
    public static func == (one: Exclusions, other: Exclusions) -> Bool {
        one.paths == other.paths && one.bundleIdentifiers == other.bundleIdentifiers
            && one.isUnreadable == other.isUnreadable
            && one.hasBeenRead == other.hasBeenRead
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(paths)
        hasher.combine(bundleIdentifiers)
        hasher.combine(isUnreadable)
        hasher.combine(hasBeenRead)
    }

    /// One saved entry. `value` is nil when the entry cannot be decoded, so a bad entry is dropped, not the list.
    private struct Entry<Value: Decodable>: Decodable {
        let value: Value?

        init(from decoder: any Decoder) {
            value = try? decoder.singleValueContainer().decode(Value.self)
        }
    }

    public init(paths: Set<URL> = [], bundleIdentifiers: Set<String> = []) {
        // A URL with no path would exclude everything, so only file URLs with an absolute path are kept.
        self.paths = Set(
            paths.lazy
                .filter { $0.isFileURL && $0.path(percentEncoded: false).hasPrefix("/") }
                .map { $0.standardizedFileURL }
        )
        self.bundleIdentifiers = bundleIdentifiers
        spellings = Self.spellings(of: self.paths)
        appFolderNames = Self.folderNames(of: bundleIdentifiers)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            paths: Set(try container.decodeIfPresent([Entry<URL>].self, forKey: .paths)?.compactMap(\.value) ?? []),
            bundleIdentifiers: Set(
                try container.decodeIfPresent([Entry<String>].self, forKey: .bundleIdentifiers)?.compactMap(\.value)
                    ?? []
            )
        )
    }

    public var isEmpty: Bool { paths.isEmpty && bundleIdentifiers.isEmpty }

    /// Adds `urls`, leaving out any already on the list under another spelling, as `/private/var` is `/var`.
    public mutating func add(_ urls: [URL]) {
        for url in urls where !paths.contains(where: { Self.isSamePlace($0, url) }) {
            paths.insert(url.standardizedFileURL)
        }
    }

    /// Takes `urls` off the list, however each entry was written. Returns whether anything came off.
    @discardableResult
    public mutating func remove(_ urls: [URL]) -> Bool {
        let removed = paths.filter { entry in urls.contains { Self.isSamePlace(entry, $0) } }
        paths.subtract(removed)
        return !removed.isEmpty
    }

    private static func isSamePlace(_ one: URL, _ other: URL) -> Bool {
        !spellings(of: one).isDisjoint(with: spellings(of: other))
    }

    /// True when `url` is excluded or sits inside something excluded. Compared name by name: a slash and a
    /// combining mark after it are one `Character`, so a name beginning with the mark would never read as
    /// inside its folder to a comparison of characters.
    public func excludes(_ url: URL) -> Bool {
        guard !spellings.isEmpty || !appFolderNames.isEmpty else { return false }
        return excludes(spellings: Self.spellings(of: url))
    }

    /// `excludes(_:)` for a path whose spellings are already worked out.
    func excludes(spellings asked: Set<String>) -> Bool {
        asked.contains { path in
            let names = PathComponents.of(path)
            return spellings.contains { names.starts(with: $0) } || names.contains(where: appFolderNames.contains)
        }
    }

    /// True when something excluded sits inside `url`, so moving `url` would take it along.
    public func holds(_ url: URL) -> Bool {
        guard !spellings.isEmpty || !appFolderNames.isEmpty else { return false }
        return holds(spellings: Self.spellings(of: url)) || !appFolders(inside: url).isEmpty
    }

    /// `holds(_:)` for a path whose spellings are already worked out.
    func holds(spellings asked: Set<String>) -> Bool {
        let asked = asked.map(PathComponents.of)
        return spellings.contains { inside in
            asked.contains { inside.count > $0.count && inside.starts(with: $0) }
        }
    }

    /// The excluded apps' folders a level or two inside `folder`. It reads the disk.
    func appFolders(inside folder: URL) -> [URL] {
        guard !appFolderNames.isEmpty else { return [] }
        let list = { (folder: URL) in
            (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        }
        return list(folder).flatMap { child in
            if appFolderNames.contains(child.lastPathComponent.lowercased()) { return [child] }
            guard child.isRealFolder else { return [] }
            return list(child).filter { appFolderNames.contains($0.lastPathComponent.lowercased()) }
        }
    }

    /// The excluded places inside `url`, leaving out one inside another, so what they hold is counted once.
    public func places(inside url: URL) -> [URL] {
        let asked = Self.spellings(of: url).map(PathComponents.of)
        let inside = paths.filter { path in
            Self.spellings(of: path).map(PathComponents.of).contains { names in
                asked.contains { names.count > $0.count && names.starts(with: $0) }
            }
        } + appFolders(inside: url)
        return inside.filter { place in !inside.contains { $0 != place && Exclusions(paths: [$0]).excludes(place) } }
    }

    /// Every way `url` can be written (see `ProtectedData.spellings(of:)`). An exclusion has to match all of
    /// them, or an item under `/var`, `/tmp` or `/etc` would slip past it when named through `/private`.
    private static func spellings(of url: URL) -> Set<String> {
        ProtectedData.spellings(of: PathPattern.comparablePath(of: url))
    }

    /// Every spelling of every excluded path as its names. The root, which has none, is left out: it would
    /// exclude everything.
    private static func spellings(of paths: Set<URL>) -> [[String]] {
        paths.flatMap { spellings(of: $0) }.map(PathComponents.of).filter { !$0.isEmpty }
    }

    /// Lowercase, as the disk compares names. A single word is too common to say whose a folder is.
    private static func folderNames(of identifiers: Set<String>) -> Set<String> {
        Set(identifiers.filter(Identifier.isValid).map { $0.lowercased() })
    }

    /// What on the list excludes an item: the app's identifier and the entries for the item itself, which taking off
    /// the list includes it again, and the excluded folders and apps' folders around it, which hold other things too.
    public struct Reasons: Sendable, Hashable {
        public let identifier: String?
        public let paths: [URL]
        public let folders: [URL]
        public let apps: [String]

        public var isEmpty: Bool { identifier == nil && paths.isEmpty && folders.isEmpty && apps.isEmpty }
    }

    /// `app` is the identifier of the app the item is, when it is one.
    public func reasons(excluding url: URL, app: String?) -> Reasons {
        let asked = Self.spellings(of: url).map(PathComponents.of)
        let sorted = paths.sorted { $0.path(percentEncoded: false) < $1.path(percentEncoded: false) }
        return Reasons(
            identifier: app.flatMap { bundleIdentifiers.contains($0) ? $0 : nil },
            paths: sorted.filter { Self.isSamePlace($0, url) },
            folders: sorted.filter { entry in
                Self.spellings(of: entry).map(PathComponents.of).contains { folder in
                    asked.contains { $0.count > folder.count && $0.starts(with: folder) }
                }
            },
            apps: bundleIdentifiers.sorted().filter { identifier in
                let name = identifier.lowercased()
                return appFolderNames.contains(name) && asked.contains { $0.contains(name) }
            }
        )
    }

    public func excludes(bundleIdentifier: String) -> Bool {
        bundleIdentifiers.contains(bundleIdentifier)
    }

    public func excludes(_ app: InstalledApp) -> Bool {
        excludes(bundleIdentifier: app.bundleIdentifier) || excludes(app.url)
    }

    /// True when `brew uninstall` would delete something excluded: an app the package installs (`apps` are the
    /// installed apps known to be its), an app identifier it quits, or its own folder under `prefix`. An
    /// unreadable list, or one not read yet, counts as excluding every package, since `brew uninstall` cannot be
    /// undone.
    public func excludes(_ package: HomebrewPackage, apps: [InstalledApp], prefix: URL?) -> Bool {
        guard isKnown else { return true }
        let targets = package.appTargets.map { URL(filePath: $0, directoryHint: .isDirectory) } + apps.map(\.url)
        if targets.contains(where: { excludes($0) || holds($0) }) { return true }
        if apps.contains(where: { excludes(bundleIdentifier: $0.bundleIdentifier) }) { return true }
        if package.quitIdentifiers.contains(where: { excludes(bundleIdentifier: $0) }) { return true }
        guard let prefix else { return false }
        let own = prefix
            .appending(path: package.kind == .cask ? "Caskroom" : "Cellar", directoryHint: .isDirectory)
            .appending(path: package.name, directoryHint: .isDirectory)
        return excludes(own) || holds(own)
    }

    /// The installed formulae whose own folder under `prefix` is excluded or holds something excluded, which
    /// Homebrew is told to keep: `brew cleanup`, and the autoremove `brew uninstall` runs, delete formulae and their
    /// old versions for good. An unreadable list, or one not read yet, keeps every formula.
    public func keptFormulae(inCellarOf prefix: URL) -> [String] {
        let cellar = prefix.appending(path: "Cellar", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: cellar.path(percentEncoded: false))) ?? []
        return names.filter { name in
            guard !name.hasPrefix(".") else { return false }
            guard isKnown else { return true }
            let own = cellar.appending(path: name, directoryHint: .isDirectory)
            return excludes(own) || holds(own)
        }.sorted()
    }

    public func keeping<T>(_ items: [T], url: (T) -> URL) -> [T] {
        guard !isEmpty else { return items }
        return items.filter { !excludes(url($0)) }
    }
}

extension Exclusions {
    /// True for a path too broad to exclude: `/`, a folder at the top of the disk, the home folder, or its
    /// Library. Excluding one would leave the tools with little or nothing to show, and `/` would protect
    /// nothing at all, since a bare `/` would match everything and is ignored. It is judged on every spelling
    /// matching reads, so the same folder written in another case is as broad.
    public static func isTooBroad(_ url: URL, home: URL = .homeDirectory) -> Bool {
        let topFolders = ["/Applications", "/Library", "/System", "/Users", "/Volumes"].map { URL(filePath: $0) }
        let broad = Set(([home, home.appending(path: "Library")] + topFolders).flatMap(spellings(of:)))
        let asked = spellings(of: url)
        return asked.contains { PathComponents.of($0).count < 2 } || !asked.isDisjoint(with: broad)
    }
}

public struct ExclusionStore: Sendable {
    public let url: URL

    public init(url: URL = ExclusionStore.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        PeelFolder.url.appending(path: "exclusions.json")
    }

    /// What `change(_:)` did.
    public enum Outcome: Sendable, Equatable {
        /// The list as it was saved.
        case saved(Exclusions)
        /// The saved list cannot be read, so it was left as it is.
        case unreadable
        /// The list could not be written. It carries what the list would have been, which the app keeps until it
        /// quits.
        case notSaved(Exclusions)
    }

    /// Loads the saved list. No file means an empty list. A file that cannot be read or reached gives `.unreadable`,
    /// never an empty list, so what the user excluded stays protected.
    @concurrent
    public func load() async -> Exclusions {
        read()
    }

    /// Saves `exclusions` in place of the list, and returns false when they could not be written. A saved file that
    /// cannot be read is first renamed with `DamagedFile`, never overwritten.
    @concurrent
    @discardableResult
    public func save(_ exclusions: Exclusions) async -> Bool {
        FileLock.whileHeld(beside: url) { write(exclusions) }
    }

    /// Changes the saved list with `transform`. The list is read again and written under the file's lock, so what
    /// another process saved meanwhile, such as `peel exclusions add` while the app runs, is kept. A saved list that
    /// cannot be read is left as it is, unless `startsOver`: it is then kept under another name and `transform`
    /// starts a new list, which is what an edit in Settings does and what `peel` never does.
    @concurrent
    public func change(
        startingOverIfUnreadable startsOver: Bool = false,
        _ transform: @Sendable (inout Exclusions) -> Void
    ) async -> Outcome {
        FileLock.whileHeld(beside: url) {
            var exclusions = read()
            if exclusions.isUnreadable {
                guard startsOver else { return .unreadable }
                exclusions = .none
            }
            transform(&exclusions)
            return write(exclusions) ? .saved(exclusions) : .notSaved(exclusions)
        }
    }

    private func read() -> Exclusions {
        guard !url.isMissing else { return .none }
        guard let data = BoundedRead.data(at: url), let saved = try? JSONDecoder().decode(Exclusions.self, from: data)
        else {
            return .unreadable
        }
        return saved
    }

    private func write(_ exclusions: Exclusions) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(exclusions) else { return false }
        if read().isUnreadable, DamagedFile.setAside(url) == nil { return false }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
