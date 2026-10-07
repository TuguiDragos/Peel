public import Darwin
import Foundation

public struct PrivilegedPathPolicy: Sendable {
    public enum Rejection: Error, Equatable, Sendable, CaseIterable {
        case notAbsolute
        case relativeComponent
        case controlCharacter
        case unresolvableParent
        /// The folder it is in is there, but the helper had no descriptor left to open it with.
        case tooManyOpenFolders
        case outsideAllowedLocations
        case notAnApplication
        case missing
        case alreadyExists
        case protectedByFlags
        case irreplaceable
        case loadsCode
        case notALink
        case leadsSomewhere

        /// What the helper sends back when it refuses. The app recognizes it and says it in the reader's language.
        public var explanation: String {
            switch self {
            case .notAbsolute: "That isn’t a full path."
            case .relativeComponent: "The path has a . or .. in it."
            case .controlCharacter: "The path holds a character no real name has."
            case .unresolvableParent: "The folder it’s in couldn’t be found."
            case .tooManyOpenFolders: "Peel’s helper had too many folders open at once. Try again."
            case .outsideAllowedLocations: "It is outside the folders Peel’s helper may touch."
            case .notAnApplication: "Peel removes only apps from that folder."
            case .missing: "It isn’t there anymore."
            case .alreadyExists: "Something is there already."
            case .protectedByFlags: "macOS marks it as protected."
            case .irreplaceable: "It holds something nothing could bring back, so Peel never moves it."
            case .loadsCode: "Code is loaded from that folder, so only what Peel’s helper took from it can go back."
            case .notALink: "Peel removes only links from that folder."
            case .leadsSomewhere: "It still leads to something on this Mac."
            }
        }

        /// Why a folder would not open: it is gone, or the helper had no descriptor left to open it with.
        init(openingFolderFailedWith error: POSIXError) {
            self = [.EMFILE, .ENFILE].contains(error.code) ? .tooManyOpenFolders : .unresolvableParent
        }
    }

    public static let systemLocations = ["/Applications"]
        + (LibraryFolder.local + LibraryFolder.plugIns).map { "/Library/" + $0.rawValue }
        + ["/private/var/db/receipts"]

    /// The served folders where anything the helper moved may be put back (`init` adds the user's Library).
    /// The others are folders that code is loaded from, and take back only what belongs to root alone (see
    /// `openDestination`). `HelperLedger`, never the caller, decides which item may go back, and where to.
    public static let restoreLocations = [
        "/Applications",
        "/Library/Application Support",
        "/Library/Caches",
        "/Library/Logs",
        "/Library/Preferences",
        "/private/var/db/receipts",
    ]

    /// The folders command-line tools and their shell completions are linked into. The helper takes only a link from
    /// them, and only one that leads nowhere: what an app's tool leaves there once the app is gone.
    public static let linkLocations = ["/usr/local/bin", "/usr/local/sbin"]
        + shellCompletionFolders.map { "/usr/local/" + $0 }

    /// Where shell completions are linked under a prefix: Homebrew's four for a cask (`Cask::Config`), the first of
    /// which also begins zsh's own function path, `/usr/local/share/zsh/site-functions`.
    public static let shellCompletionFolders = [
        "share/zsh/site-functions", "share/fish/vendor_completions.d", "etc/bash_completion.d", "share/pwsh/completions",
    ]

    private static let protectedFlags = UInt32(SF_RESTRICTED) | UInt32(SF_IMMUTABLE) | UInt32(SF_NOUNLINK)

    private let locations: [String]
    private let restorable: [String]
    private let applicationLocations: [String]
    private let links: [String]
    /// The folders of the home's Library that Peel searches, lowercased, as names from the root.
    private let searchedFolders: Set<[String]>
    private let homeDirectory: String
    private let trustedOwner: uid_t

    public init(
        homeDirectory: String,
        systemLocations: [String] = Self.systemLocations,
        applicationLocations: [String] = ["/Applications"],
        restoreLocations: [String] = Self.restoreLocations,
        linkLocations: [String] = Self.linkLocations,
        trustedOwner: uid_t = 0
    ) {
        self.homeDirectory = homeDirectory
        self.trustedOwner = trustedOwner
        links = linkLocations.compactMap(Self.realPath)
        locations = (systemLocations + [homeDirectory + "/Library"]).compactMap(Self.realPath) + links
        restorable = (restoreLocations + [homeDirectory + "/Library"]).compactMap(Self.realPath)
        self.applicationLocations = applicationLocations.compactMap(Self.realPath)
        let library = Self.realPath(homeDirectory + "/Library") ?? homeDirectory + "/Library"
        searchedFolders = Set(LibraryFolder.inTheUsersLibrary.map { folder in
            PathComponents.of((library + "/" + folder.rawValue).lowercased())
        })
    }

    /// True for a path directly in one of the folders the helper takes only a link from.
    public func takesOnlyALink(at path: String) -> Bool {
        guard let parent = Self.realPath((path as NSString).deletingLastPathComponent) else { return false }
        return links.contains(parent)
    }

    private struct Resolved {
        let parent: String
        let name: String
        let path: String
    }

    /// Checks `path` by name alone, before anything is opened. The parent is resolved once, the result must
    /// sit inside one of `locations`, and it must neither be nor hold anything protected.
    private func resolve(_ path: String, in locations: [String]) -> Result<Resolved, Rejection> {
        guard path.hasPrefix("/") else { return .failure(.notAbsolute) }
        guard Self.isPlainlyReadable(path) else { return .failure(.controlCharacter) }
        guard !ProtectedData.refuses(path, home: homeDirectory) else { return .failure(.irreplaceable) }
        let components = PathComponents.of(path)
        guard let name = components.last, !components.contains(where: { $0 == "." || $0 == ".." }) else {
            return .failure(.relativeComponent)
        }

        let parent = "/" + components.dropLast().joined(separator: "/")
        guard let resolvedParent = Self.realPath(parent) else { return .failure(.unresolvableParent) }
        return judge(name, in: resolvedParent, locations: locations)
    }

    /// The checks on `name` in a folder named with no link left in its path, as `realpath` or the kernel names it.
    private func judge(_ name: String, in resolvedParent: String, locations: [String]) -> Result<Resolved, Rejection> {
        let resolved = (resolvedParent == "/" ? "" : resolvedParent) + "/" + name
        guard
            !ProtectedData.refuses(resolved, home: homeDirectory),
            !searchedFolders.contains(PathComponents.of(resolved.lowercased())),
            !ProtectedData.spellings(of: resolved).contains(where: ProtectedData.isInAContainersDocuments)
        else { return .failure(.irreplaceable) }
        // Refused as well when moving it would take something protected along with it. The helper runs as
        // root, so it asks this itself rather than trusting the app to.
        guard
            !ProtectedData.holds(resolved, home: homeDirectory),
            !ProtectedData.holdsAContainersDocuments(resolved),
            !ProtectedData.holdsWorkKeptInACache(resolved),
            !ProtectedData.holdsALibrary(resolved),
            !ProtectedData.holdsABrowserWallet(resolved)
        else { return .failure(.irreplaceable) }

        guard let location = locations.first(where: { PathComponents.isPath(resolved, inside: $0) }) else {
            return .failure(.outsideAllowedLocations)
        }
        // A tool's link sits directly in its folder, never deeper.
        if links.contains(location), resolvedParent != location {
            return .failure(.outsideAllowedLocations)
        }
        if applicationLocations.contains(location), !name.hasSuffix(".app") {
            return .failure(.notAnApplication)
        }
        return .success(Resolved(parent: resolvedParent, name: name, path: resolved))
    }

    /// What the helper would answer before opening anything, nil when it would go on to open `path`.
    public func refusal(of path: String) -> Rejection? {
        if case .failure(let rejection) = resolve(path, in: locations) { return rejection }
        return nil
    }

    /// Checks `path`, opens its folder, and checks the item again there, as the kernel names that folder. The move
    /// goes through the same descriptor and moves only the item whose identity was read here.
    public func open(_ path: String) -> Result<OpenItem, Rejection> {
        open(path, beforeOpening: {})
    }

    func open(_ path: String, beforeOpening: () -> Void) -> Result<OpenItem, Rejection> {
        openFolder(of: path, beforeOpening: beforeOpening).flatMap { name, parent in
            var info = stat()
            guard name.withCString({ fstatat(parent.descriptor, $0, &info, AT_SYMLINK_NOFOLLOW) }) == 0 else {
                return .failure(.missing)
            }
            return judged(name, in: parent).flatMap { item in
                guard info.st_flags & Self.protectedFlags == 0 else { return .failure(.protectedByFlags) }
                if links.contains(item.parent) {
                    guard info.st_mode & S_IFMT == S_IFLNK else { return .failure(.notALink) }
                    // Followed this time: nothing there, or a chain that loops, is a link that leads nowhere.
                    var target = stat()
                    let leads = item.name.withCString { fstatat(parent.descriptor, $0, &target, 0) } == 0
                    let error = errno
                    guard !leads, error == ENOENT || error == ENOTDIR || error == ELOOP else {
                        return .failure(.leadsSomewhere)
                    }
                }
                return .success(OpenItem(path: item.path, name: item.name, parent: parent, status: info))
            }
        }
    }

    /// Like `open`, for a path where nothing exists yet. A folder that code is loaded from takes back only an
    /// item owned by root that nobody else can write to, which is how anything the helper took from there
    /// looks. Anything else could have been rewritten while it sat in the user's Trash.
    public func openDestination(_ path: String, for trashed: OpenItem) -> Result<OpenItem, Rejection> {
        openFolder(of: path, beforeOpening: {}).flatMap { name, parent in
            judged(name, in: parent).flatMap { item in
                if links.contains(item.parent) {
                    guard let mode = trashed.mode, mode & S_IFMT == S_IFLNK else { return .failure(.notALink) }
                }
                if !restorable.contains(where: { PathComponents.isPath(item.path, inside: $0) }) {
                    guard trashed.owner == trustedOwner, let mode = trashed.mode, mode & 0o022 == 0 else {
                        return .failure(.loadsCode)
                    }
                }
                var info = stat()
                guard item.name.withCString({ fstatat(parent.descriptor, $0, &info, AT_SYMLINK_NOFOLLOW) }) != 0 else {
                    return .failure(.alreadyExists)
                }
                return .success(OpenItem(path: item.path, name: item.name, parent: parent))
            }
        }
    }

    /// Checks `path` by name, so nothing is opened for a path refused anyway, then opens its folder.
    private func openFolder(
        of path: String,
        beforeOpening: () -> Void
    ) -> Result<(name: String, parent: DirectoryHandle), Rejection> {
        resolve(path, in: locations).flatMap { named in
            beforeOpening()
            switch DirectoryHandle.at(canonical: named.parent) {
            case .success(let parent): return .success((named.name, parent))
            case .failure(let error): return .failure(Rejection(openingFolderFailedWith: error))
            }
        }
    }

    /// Checks `name` again in the folder `parent` holds, as the kernel names it now.
    private func judged(_ name: String, in parent: DirectoryHandle) -> Result<Resolved, Rejection> {
        guard let folder = parent.currentPath else { return .failure(.unresolvableParent) }
        return judge(name, in: folder, locations: locations)
    }

    /// Opens the user's own Trash. A link in place of `.Trash` is refused, and the folder must belong to
    /// `user`, so the Trash cannot be used to drop a root-owned file somewhere else.
    public func openTrash(ownedBy user: uid_t) -> DirectoryHandle? {
        guard
            let home = Self.realPath(homeDirectory),
            let trash = (try? DirectoryHandle.at(canonical: home).get())?.child(".Trash"),
            trash.ownerIdentifier() == user
        else { return nil }
        return trash
    }

    /// Opens the item at `path` when, with links resolved, it sits inside `trash`.
    public func openInTrash(_ path: String, trash: DirectoryHandle) -> OpenItem? {
        guard
            let item = try? OpenItem.at(path).get(),
            PathComponents.isPath(item.parent.path, atOrInside: trash.path)
        else { return nil }
        return item
    }

    /// False for a path holding a control character. The rules here read a Swift string, but the kernel
    /// reads a C string, which ends at the first NUL, so a path holding a NUL would be checked as one thing
    /// and moved as another. Every other control character is refused as well.
    static func isPlainlyReadable(_ path: String) -> Bool {
        !path.utf8.contains { $0 < 0x20 || $0 == 0x7F }
    }

    /// True for a launchd label the helper may pass to `launchctl`: no shell or path characters, no leading
    /// dot or hyphen, and no `com.apple.` prefix.
    public static func isValidLabel(_ label: String) -> Bool {
        guard (1...255).contains(label.utf8.count), !label.hasPrefix("com.apple.") else { return false }
        return label.utf8.allSatisfy { byte in
            (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
                || byte == 0x2E || byte == 0x2D || byte == 0x5F
        } && label.first != "." && label.first != "-"
    }

    /// True for a job the helper may act on. The `com.apple.` prefix is not enough, since macOS also ships
    /// daemons such as `com.openssh.sshd`, `org.cups.cupsd`, and `com.vix.cron`, so every label macOS declares
    /// is refused too. An empty list means the labels could not be read, and then everything is refused. The
    /// helper never acts on itself: `bootout` would kill it before it answers, and `disable` persists across
    /// boots (`man launchctl`), leaving nothing to undo it.
    public static func allowsDaemon(_ label: String, shipped: Set<String> = SystemDaemons.shipped) -> Bool {
        isValidLabel(label) && !shipped.isEmpty && !shipped.contains(label) && label != HelperIdentity.helperIdentifier
    }

    /// The path with every symlink resolved, or nil when it doesn't exist.
    public static func resolvedPath(_ path: String) -> String? {
        realPath(path)
    }

    static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
