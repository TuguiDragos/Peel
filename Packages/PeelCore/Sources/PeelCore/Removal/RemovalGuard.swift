import Darwin
import Foundation
internal import PeelPrivileged

struct RemovalGuard: Sendable {
    /// Nothing inside these may be removed. `/Library/Updates` is where Software Update stages macOS updates.
    /// Lower-cased, because the spellings they are compared against are.
    private static let protectedPrefixes = ["/system", "/usr", "/bin", "/sbin", "/library/updates"]
    /// The folders command-line tools are linked into. A link directly in one is the one thing under `/usr` that may
    /// go: what an app's tool leaves there, which Peel's helper takes only once it leads nowhere.
    private static let toolLinkFolders = PrivilegedPathPolicy.linkLocations.map { PathComponents.of($0.lowercased()) }

    private let protectedPaths: Set<String>
    private let protectedTrees: [[String]]
    private let protectedObjects: ProtectedObjects
    private let exclusions: Exclusions

    var knowsTheExclusions: Bool { exclusions.isKnown }
    private let home: String

    init(environment: SearchEnvironment, exclusions: Exclusions = .none) {
        self.exclusions = exclusions
        let home = environment.homeDirectory
        self.home = home.path(percentEncoded: false)
        var paths: [String] = [
            "/", "/Applications", "/Library", "/Library/Updates", "/System", "/Users", "/Users/Shared", "/Volumes", "/opt", "/usr",
            "/private", "/private/var", "/private/tmp", "/private/etc", "/var", "/tmp", "/etc", "/cores",
        ]
        // The home folder and the folders every account starts with are the user's own, whatever they contain,
        // so they are never removed themselves.
        let homeDirectories: [URL] = [home] + ProtectedData.accountFolders.map { home.appending(path: $0) }
        paths += homeDirectories.map { $0.path(percentEncoded: false) }
        paths += environment.locations.map { $0.url.path(percentEncoded: false) }
        paths += SpaceInventory.emptiedFolders(in: environment).map { $0.path(percentEncoded: false) }
        paths += ProtectedData.sharedHomeItems.map { home.appending(path: $0).path(percentEncoded: false) }
        let trees = ProtectedData.homeTrees.map { home.appending(path: $0).path(percentEncoded: false) }
        protectedPaths = Set(paths.flatMap(Self.names))
        protectedTrees = Set((trees + ProtectedData.systemFolders).flatMap(Self.names)).map(PathComponents.of)
        protectedObjects = ProtectedObjects(trees: trees + ProtectedData.systemFolders, folders: paths)
    }

    /// Every lower-cased spelling of `path`, as written and as located on disk. A home kept on another disk is
    /// reached through a link, and Spotlight names files by the disk they are on, so both forms must match.
    private static func names(of path: String) -> Set<String> {
        let path = normalized(path)
        return PathPattern.spellings(of: path).union(PathPattern.locatedWithoutOpening(path).map(PathPattern.spellings) ?? [])
    }

    func allowsRemoval(of url: URL) -> Bool {
        allows(url, isALink: nil)
    }

    /// Whether `trashed` may go back to `destination`, which is judged as a removal from there would be, for the
    /// kind of item `trashed` is: nothing is there yet to tell.
    func allowsPuttingBack(_ trashed: URL, at destination: URL) -> Bool {
        allows(destination, isALink: Self.isALink(trashed.path(percentEncoded: false)))
    }

    /// True for the lower-cased spelling of a link directly in a folder command-line tools are linked into.
    static func isAToolsLink(_ spelling: String, isALink: Bool) -> Bool {
        isALink && toolLinkFolders.contains(Array(PathComponents.of(spelling).dropLast()))
    }

    private static func isALink(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFLNK
    }

    private func allows(_ url: URL, isALink known: Bool?) -> Bool {
        guard url.isFileURL, exclusions.isKnown else { return false }
        let path = Self.normalized(url.path(percentEncoded: false))
        // A path can be written several ways (`/var` for `/private/var`, a different case), and a Put Back
        // destination does not exist yet. `located` names the part that exists the way the kernel does.
        guard let located = PathPattern.located(path) else { return false }
        let isALink = known ?? Self.isALink(located)
        // The kernel's own name for the item is judged too: `/.vol/<device>/<inode>` names a file by its numbers
        // alone and shows none of the folders it sits in.
        let names = Set([path, located, PathPattern.kernelName(of: path, followingLinks: false)].compactMap(\.self))
        for name in names {
            let named = URL(filePath: name)
            guard !exclusions.excludes(named), !exclusions.holds(named) else { return false }
            guard protectedObjects.allows(name) else { return false }
            // The rules the helper follows. They protect every account's keychain and mail, not only those of the
            // account Peel runs in.
            guard !ProtectedData.refuses(name, home: home), !ProtectedData.holds(name, home: home) else { return false }
        }

        for spelling in names.reduce(into: Set<String>(), { $0.formUnion(PathPattern.spellings(of: $1)) }) {
            let isUnderAPrefix = Self.protectedPrefixes.contains { PathComponents.isPath(spelling, inside: $0) }
            guard !protectedPaths.contains(spelling), !isUnderAPrefix || Self.isAToolsLink(spelling, isALink: isALink) else {
                return false
            }

            let parts = PathComponents.of(spelling)
            guard !protectedTrees.contains(where: { parts.starts(with: $0) }) else { return false }
            // Also refuse a folder with a protected tree inside, since removing it would take the tree along.
            guard !protectedTrees.contains(where: { $0.count > parts.count && $0.starts(with: parts) }) else { return false }
            guard !Self.isInsideAUserLibrary(spelling), !ProtectedData.isGlobalPreferences(spelling) else { return false }
            guard !ProtectedData.isInAnApplesGroupContainer(spelling) else { return false }
            // A sandboxed app's own documents sit inside its container, beside the settings.
            guard !ProtectedData.isInAContainersDocuments(spelling) else { return false }
        }
        var info = stat()
        guard lstat(path, &info) != 0 || info.st_flags & UInt32(SF_RESTRICTED) == 0 else { return false }

        // Last, since each reads what is a level or two inside the folder, and a name refused above needs none of it.
        for name in names {
            // An uninstall lists a whole container, and the documents inside would go with it. Space lists a
            // vendor's whole cache folder, and work kept only there (an IDE's local history) would go with it.
            guard !ProtectedData.holdsAContainersDocuments(name), !ProtectedData.holdsWorkKeptInACache(name) else { return false }
            guard !ProtectedData.holdsALibrary(name), !ProtectedData.holdsABrowserWallet(name) else { return false }
        }
        return true
    }

    /// True for anything at or inside a photo, music or video library package. The path arrives lower-cased.
    private static func isInsideAUserLibrary(_ path: String) -> Bool {
        PathComponents.of(path).contains { component in
            ProtectedData.extensions.contains { component.hasSuffix("." + $0) }
        }
    }

    private static func normalized(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        return standardized.count > 1 && standardized.hasSuffix("/") ? String(standardized.dropLast()) : standardized
    }
}
