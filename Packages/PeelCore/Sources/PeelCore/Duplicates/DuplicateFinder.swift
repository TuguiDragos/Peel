import Darwin
public import Foundation
internal import PeelPrivileged
import Synchronization
import UniformTypeIdentifiers

public struct DuplicateFinder: Sendable {
    private static let suggestedFolders = ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music"]
    /// Folders in the home folder that hold app data or files managed by the Music and TV libraries.
    private static let managedFolders = ["Library", "Music/Music", "Music/iTunes", "Movies/TV"]


    private let homeDirectory: URL
    private let exclusions: Exclusions
    private let digestMemory: DigestMemory?
    private let isDataless: @Sendable (URL) -> Bool

    /// Without a `digestMemory`, every file is read and no digest is saved, so tests never touch the user's
    /// saved digests.
    public init(
        homeDirectory: URL = .homeDirectory,
        exclusions: Exclusions = .none,
        digestMemory: DigestMemory? = nil
    ) {
        self.init(homeDirectory: homeDirectory, exclusions: exclusions, digestMemory: digestMemory) {
            FileSize.isDataless($0)
        }
    }

    /// `isDataless` stands in for a folder a file provider keeps only in the cloud, which no test can make.
    init(
        homeDirectory: URL,
        exclusions: Exclusions,
        digestMemory: DigestMemory?,
        isDataless: @escaping @Sendable (URL) -> Bool
    ) {
        self.exclusions = exclusions
        self.homeDirectory = homeDirectory.resolvingSymlinksInPath()
        self.digestMemory = digestMemory
        self.isDataless = isDataless
    }

    public var defaultFolders: [URL] {
        Self.suggestedFolders
            .map { homeDirectory.appending(path: $0, directoryHint: .isDirectory) }
            .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    /// Why a chosen folder is not scanned. `refusal(of:)` answers the first three for any folder, which is what
    /// `canScan` refuses; a scan adds the last two for a chosen folder it finds so.
    public enum Refusal: Sendable, Hashable {
        /// App data, the Music and TV apps' media folders, or a place Peel protects, such as a library or a keychain.
        case appData
        /// An app or another package, or a folder inside one: what is inside belongs to it.
        case inAPackage
        /// Outside the home folder and `/Users/Shared`, or on a volume Peel can't write to.
        case outsideTheHome
        /// A repository, or a folder inside one, which the scan leaves alone.
        case insideARepository
        /// Not a folder Peel can reach, as one on a disk that isn't connected.
        case notAFolder
    }

    /// Whether `folder` may be scanned: a folder in the home folder, in `/Users/Shared`, or on another writable
    /// volume. App data and system locations are refused. A folder that syncs to other devices, such as iCloud
    /// Drive or one another app keeps in step, is scanned, and each copy found in it is held back: a removal there
    /// reaches every device, so the scan shows such copies and never moves them.
    public func canScan(_ folder: URL) -> Bool {
        refusal(of: folder) == nil
    }

    /// Why `folder` may not be scanned, or nil. iCloud Drive and the folder where file providers keep their files
    /// are in the home's Library and protected data to the guard, which refuses each copy inside when the scan
    /// asks it; the scan shows those copies and never moves them, so neither rule refuses such a folder here.
    public func refusal(of folder: URL) -> Refusal? {
        let path = Self.path(of: folder.resolvingSymlinksInPath())
        let home = Self.path(of: homeDirectory)
        if folder.isOrIsInsideAPackage { return .inAPackage }
        let syncs = Self.isInACloudFolder(path)
        if !syncs, ProtectedData.refuses(path, home: home) { return .appData }
        if path.isInside(home) {
            return !syncs && Self.managedFolders.contains { path.isInside(home + "/" + $0) } ? .appData : nil
        }
        guard path.isInside("/Users/Shared") || PathComponents.isPath(path, inside: "/Volumes") else {
            return .outsideTheHome
        }
        let isReadOnly = (try? folder.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true
        return isReadOnly ? .outsideTheHome : nil
    }

    /// Why a scan would set `folder` aside, or nil: what `refusal(of:)` refuses, a folder that is not there, or a
    /// repository. It is what the scan asks of each chosen folder, and what the list of folders says beside one.
    public func reasonToSetAside(_ folder: URL) -> Refusal? {
        refusal(of: folder)
            ?? (!Self.isAFolder(folder) ? .notAFolder : nil)
            ?? (Self.isInsideARepository(folder, home: homeDirectory) ? .insideARepository : nil)
    }

    /// Whether `path` is in iCloud Drive, or in the folder where file providers keep their files.
    private static func isInACloudFolder(_ path: String) -> Bool {
        let names = PathComponents.of(path.lowercased())
        return zip(names, names.dropFirst()).contains { folder, inside in
            folder == "library" && ["mobile documents", "cloudstorage"].contains(inside)
        }
    }

    /// Whether `url` is a folder Peel can reach, links followed.
    private static func isAFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Runs a walk as `BlockingWork`, so a folder that never answers holds no thread of the scan's task: it throws
    /// once the task is canceled, and the walk, asking `isGivenUp`, stops.
    static func walk<T: Sendable>(
        _ walk: @escaping @Sendable (_ isGivenUp: @escaping @Sendable () -> Bool) throws(CancellationError) -> T
    ) async throws(CancellationError) -> T {
        let answer: Result<T, CancellationError>? = await BlockingWork.run { isGivenUp in
            do throws(CancellationError) { return .success(try walk(isGivenUp)) } catch { return .failure(error) }
        }
        guard case .success(let value)? = answer else { throw CancellationError() }
        return value
    }

    /// Whether `url` is a photo, music, or video library. Its files belong to the library's app, so none of them
    /// is offered as a copy, whatever its bytes.
    static func isAUserLibrary(_ url: URL) -> Bool {
        ProtectedData.extensions.contains(url.pathExtension.lowercased())
    }

    /// Whether `url` is a document its app keeps as a package. Launch Services knows one as a package only while its
    /// app is installed, so these are named here, each from its maker, and a file inside one is never offered alone.
    static func isAnAppsDocument(_ url: URL) -> Bool {
        appDocuments.contains(url.pathExtension.lowercased())
    }

    private static let appDocuments: Set<String> = [
        // Logic Pro, "a package or a project folder": support.apple.com/guide/logicpro/lgcpce128e82
        "logicx",
        // MainStage, "concert package": support.apple.com/101568
        "mainstage",
        // Scrivener, "packages of files": scrivener.tenderapp.com/help/kb/macos/password-protecting-your-work
        "scriv",
        // DEVONthink, "databases are packages": its help, Repairing a defective database
        "dtbase2",
        // Capture One, "a .cocatalog package": support.captureone.com/hc/en-us/articles/11019291187997
        "cocatalog",
        // Lightroom Classic's preview caches beside a catalog:
        // helpx.adobe.com/lightroom-classic/desktop/kb/preference-file-and-other-file-locations.html
        "lrdata",
    ]

    /// Finds folders whose whole contents are identical, then identical files. Files are compared by size, then
    /// by their first and last bytes, then by a SHA-256 of the whole file.
    @concurrent
    public func scan(
        _ options: DuplicateScanOptions,
        progress: @escaping @Sendable (DuplicateScanProgress) -> Void = { _ in }
    ) async throws(CancellationError) -> DuplicateScan {
        // Nothing is read before the exclusions are known, or what the person excluded would be read with the rest.
        guard exclusions.isKnown else {
            return DuplicateScan(groups: [], unreadableLocations: [], exclusionsNotKnown: true)
        }
        let environment = SearchEnvironment(homeDirectory: homeDirectory, rootDirectory: URL(filePath: "/"))
        let removalGuard = RemovalGuard(environment: environment, exclusions: exclusions)
        let skipped = options.folders.compactMap { folder in
            reasonToSetAside(folder).map { DuplicateScan.FolderSetAside(url: folder, reason: $0) }
        }
        let skippedPaths = Set(skipped.map { Self.path(of: $0.url) })
        let scannable = options.folders.filter { !skippedPaths.contains(Self.path(of: $0)) }
        let neverProjects = Self.neverProjects(chosen: scannable, home: homeDirectory)
        // Saved even when the scan is stopped: the digests computed by then are still correct.
        let known = digestMemory?.load()
        defer { if let known { digestMemory?.save(known) } }

        // Folders are compared only when no file kind is chosen: a kind, such as images, applies to files alone.
        let folderGroups = options.kind == .any
            ? try await FolderDuplicates(
                managed: Self.managedPaths(home: homeDirectory),
                exclusions: exclusions,
                neverProjects: neverProjects,
                isDataless: isDataless
            ).groups(
                in: scannable,
                minimumSize: options.minimumSize,
                keepOrder: KeepOrder(home: homeDirectory),
                removalGuard: removalGuard,
                known: known,
                progress: progress
            )
            : []
        let spokenFor = Set(folderGroups.flatMap { $0.folders.map { Self.path(of: $0.url) } })

        let collected = try await Self.walk { isGivenUp throws(CancellationError) in
            try collect(
                options,
                in: scannable,
                spokenFor: spokenFor,
                neverProjects: neverProjects,
                isGivenUp: isGivenUp,
                progress: progress
            )
        }
        // Each file is read once, under the first of its names, and an excluded name is never read.
        var names: [FileIdentity.Link: [Candidate]] = [:]
        var files: [Candidate] = []
        for candidate in collected.candidates where exclusions.isKnown && !exclusions.excludes(candidate.url) {
            if names[candidate.identity.link] == nil { files.append(candidate) }
            names[candidate.identity.link, default: []].append(candidate)
        }
        let sameSize = Dictionary(grouping: files, by: \.identity.size).values.filter { $0.count > 1 }.flatMap { $0 }

        let comparing = ReportThrottle()
        let sampled = await FileDigest.many(
            sameSize,
            digest: { FileDigest.sample(of: $0.url, identity: $0.identity, known: known) }
        ) { completed in
            if comparing.allows(isLast: completed == sameSize.count) {
                progress(.comparing(filesCompared: completed, filesToCompare: sameSize.count))
            }
        }
        guard !Task.isCancelled else { throw CancellationError() }
        let synced = SyncedFolders()
        let sampledGroups = try Self.movable(
            Self.grouped(sampled),
            names: names,
            refusal: removalGuard.refusal(of:),
            syncsToOtherDevices: { synced.syncsToOtherDevices($0) || Self.isInACloudFolder(Self.path(of: $0)) }
        )
        let finalGroups = sampledGroups.filter { !FileDigest.isSampled(size: $0[0].item.identity.size) }

        let toVerify = sampledGroups.filter { FileDigest.isSampled(size: $0[0].item.identity.size) }
            .flatMap { $0.map(\.item) }
        let reading = ReadProgress(
            bytesToRead: FileDigest.bytesToRead(toVerify.map(\.identity), known: known),
            report: progress
        )
        let verified = await FileDigest.many(toVerify) { candidate in
            FileDigest.full(of: candidate.url, identity: candidate.identity, known: known, onRead: reading.add)
        }
        guard !Task.isCancelled else { throw CancellationError() }

        let groups = (finalGroups + Self.grouped(verified)).map(makeGroup).sorted {
            ($0.reclaimableSize, $0.size, $1.id) > ($1.reclaimableSize, $1.size, $0.id)
        }
        return DuplicateScan(
            groups: groups,
            folderGroups: folderGroups,
            unreadableLocations: collected.unreadableLocations,
            skippedLocations: skipped,
            needsFullDiskAccess: collected.unreadableLocations.contains { FullDiskAccess.canList($0) == .missing }
        )
    }

    struct Candidate: Sendable {
        let url: URL
        let identity: FileIdentity
        /// Set by `movable` for a copy that is kept in its group but never moved.
        var heldBack: HoldBack? = nil
    }

    typealias HashedCandidate = (item: Candidate, digest: ContentDigest)

    private struct ContentKey: Hashable {
        let size: Int64
        let digest: ContentDigest
        let extras: [UInt8]
    }

    private final class UnreadableLocations {
        var urls: [URL] = []
    }

    private func collect(
        _ options: DuplicateScanOptions,
        in folders: [URL],
        spokenFor: Set<String>,
        neverProjects: Set<String>,
        isGivenUp: () -> Bool,
        progress: (DuplicateScanProgress) -> Void
    ) throws(CancellationError) -> (candidates: [Candidate], unreadableLocations: [URL]) {
        // The kind of a file is asked for only when a kind was chosen: working it out costs a lookup per
        // entry, and the walk sees every file in the chosen folders.
        var keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey]
        if options.kind != .any { keys.insert(.contentTypeKey) }
        let excludedFolders = Self.managedPaths(home: homeDirectory)
        let unreadable = UnreadableLocations()
        var walked: [Candidate] = []
        var projects = Set<String>()
        var visited = 0

        for folder in folders {
            guard !isGivenUp() else { throw CancellationError() }
            let root = folder.resolvingSymlinksInPath()
            // A chosen folder is never an entry of its own walk, so one offered whole, or inside one, is skipped here.
            guard !spokenFor.contains(Self.path(of: root)), !Self.isInside(spokenFor, root) else { continue }
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, _ in
                    unreadable.urls.append(url)
                    return true
                }
            ) else { continue }

            // The enumerator's answer and each look at it get an autorelease pool of their own, or what Foundation
            // reads for every entry would pile up in memory until the walk ends.
            while let url = autoreleasepool(invoking: { enumerator.nextObject() as? URL }) {
                visited += 1
                if visited.isMultiple(of: 256) {
                    guard !isGivenUp() else { throw CancellationError() }
                    progress(.collecting(filesFound: walked.count))
                }
                autoreleasepool {
                    if ProjectArtifacts.isMarker(url.lastPathComponent) {
                        let parent = Self.path(of: url.deletingLastPathComponent())
                        if !neverProjects.contains(parent) { projects.insert(parent) }
                    }
                    guard let values = try? url.resourceValues(forKeys: keys) else { return }
                    if values.isDirectory == true {
                        // The enumerator does not treat a library or an app's document as a package when its app is
                        // not installed, so they are skipped here: the guard would refuse every copy inside a library,
                        // and a file taken from a document breaks it. A folder already offered whole covers
                        // everything inside it, so its files are not offered again.
                        if url.lastPathComponent == "node_modules" || excludedFolders.contains(Self.path(of: url))
                            || spokenFor.contains(Self.path(of: url))
                            || exclusions.excludes(url) || Self.isRepository(url) || Self.isAUserLibrary(url)
                            || Self.isAnAppsDocument(url) || isDataless(url) {
                            enumerator.skipDescendants()
                        }
                        return
                    }
                    var info = stat()
                    guard
                        values.isRegularFile == true,
                        lstat(url.path(percentEncoded: false), &info) == 0,
                        info.st_mode & S_IFMT == S_IFREG,
                        info.st_flags & UInt32(SF_DATALESS) == 0,
                        ReclaimableSpace.held(info) >= options.minimumSize,
                        options.kind == .any || values.contentType.map(options.kind.includes) == true
                    else { return }
                    walked.append(Candidate(url: url, identity: FileIdentity(info)))
                }
            }
        }
        guard !isGivenUp() else { throw CancellationError() }
        let outsideProjects = projects.isEmpty ? walked : walked.filter { !Self.isInside(projects, $0.url) }
        progress(.collecting(filesFound: outsideProjects.count))
        return (outsideProjects, unreadable.urls)
    }

    /// The groups as they may move: each file under the first of its `names`, in the order the walk found them,
    /// that `refusal` allows, else under the first that syncs to other devices, held back, and a group only while
    /// two files are left. `refusal`, the guard, which opens the file and the folders above it, is asked only here,
    /// of files whose first and last bytes already match another's. A name the guard refuses that syncs is kept
    /// whatever the guard's own reason: the guard would refuse the move either way, and that it syncs is what the
    /// person needs to know.
    static func movable(
        _ groups: [[HashedCandidate]],
        names: [FileIdentity.Link: [Candidate]],
        refusal: (URL) -> GuardRefusal?,
        syncsToOtherDevices: (URL) -> Bool
    ) throws(CancellationError) -> [[HashedCandidate]] {
        var asked = 0
        var movable: [[HashedCandidate]] = []
        for group in groups {
            var kept: [HashedCandidate] = []
            for member in group {
                var synced: Candidate?
                for name in names[member.item.identity.link] ?? [member.item] {
                    asked += 1
                    if asked.isMultiple(of: 256) {
                        guard !Task.isCancelled else { throw CancellationError() }
                    }
                    if refusal(name.url) == nil {
                        kept.append((item: name, digest: member.digest))
                        synced = nil
                        break
                    }
                    if synced == nil, syncsToOtherDevices(name.url) {
                        var held = name
                        held.heldBack = .inTheCloud
                        synced = held
                    }
                }
                if let synced { kept.append((item: synced, digest: member.digest)) }
            }
            if kept.count > 1 { movable.append(kept) }
        }
        return movable
    }

    static func isInside(_ folders: Set<String>, _ url: URL) -> Bool {
        var url = url.deletingLastPathComponent()
        while true {
            let current = path(of: url)
            if folders.contains(current) { return true }
            let parent = url.deletingLastPathComponent()
            guard current != "/", !current.isEmpty, path(of: parent) != current else { return false }
            url = parent
        }
    }

    private static func grouped(_ hashed: [HashedCandidate]) -> [[HashedCandidate]] {
        let keyed = hashed.compactMap { candidate in
            FileExtras.of(candidate.item.url).map { extras in
                (candidate, ContentKey(size: candidate.item.identity.size, digest: candidate.digest, extras: extras))
            }
        }
        return Dictionary(grouping: keyed, by: \.1).values.filter { $0.count > 1 }.map { $0.map(\.0) }
    }

    private func makeGroup(_ members: [HashedCandidate]) -> DuplicateGroup {
        let order = KeepOrder(home: homeDirectory)
        let files = members
            .map { ($0.item, order.rank(of: $0.item.url, identity: $0.item.identity)) }
            .sorted { $0.1 < $1.1 }
            .map { candidate, _ in
                DuplicateFile(
                    url: candidate.url,
                    size: candidate.identity.size,
                    reclaimableSize: ReclaimableSpace.of(candidate.url),
                    allocatedSize: ReclaimableSpace.allocated(candidate.url),
                    identity: candidate.identity,
                    heldBack: candidate.heldBack
                )
            }
        return DuplicateGroup(id: members[0].digest.hexadecimal, files: files)
    }

    /// Which copy is kept, from the home folder: its Downloads, and the disk it is on.
    struct KeepOrder: Sendable {
        private let downloads: String
        private let homeDevice: dev_t?

        init(home: URL) {
            downloads = DuplicateFinder.path(of: home.appending(path: "Downloads"))
            var info = stat()
            homeDevice = stat(home.path(percentEncoded: false), &info) == 0 ? info.st_dev : nil
        }

        /// Ranks a copy for keeping, lower being better: outside Downloads, without a copy suffix, on the disk the
        /// home folder is on, created earlier, less deeply nested, then with a shorter name. The path breaks any tie
        /// that is left.
        func rank(of url: URL, identity: FileIdentity) -> (Int, Int, Int, Int, String) {
            let path = DuplicateFinder.path(of: url)
            let name = url.deletingPathExtension().lastPathComponent
            let flags = [
                path.isInside(downloads), DuplicateFinder.hasCopySuffix(name), identity.link.device != homeDevice,
            ]
            return (
                // Each flag outweighs those after it.
                flags.reduce(0) { $0 * 2 + ($1 ? 1 : 0) },
                identity.creationTime,
                url.pathComponents.count,
                name.count,
                path
            )
        }
    }

    /// Folders never treated as a project, even with a build file in them: the chosen folders, the home folder,
    /// and the folders every account starts with. Treated as a project, one of these would leave all its files
    /// out of the scan.
    static func neverProjects(chosen: [URL], home: URL) -> Set<String> {
        let home = path(of: home.resolvingSymlinksInPath())
        return Set(
            chosen.map { path(of: $0.resolvingSymlinksInPath()) } + [home]
                + ProtectedData.accountFolders.map { home + "/" + $0 }
        )
    }

    static func managedPaths(home: URL) -> Set<String> {
        let home = path(of: home)
        return Set(managedFolders.map { home + "/" + $0 })
    }

    /// Whether `name` ends with a suffix that Finder, a browser, or the Keep Both option adds to a copy: " copy",
    /// " copy 2", " (3)", or " 2", in any letter case, with "copy" in any language listed in `copyWords`. It works
    /// word by word rather than with a regular expression, to stay fast: it runs for every file in every group.
    static func hasCopySuffix(_ name: String) -> Bool {
        var words = name.split(separator: " ", omittingEmptySubsequences: false)
        guard words.count > 1, let last = words.popLast() else { return false }
        if isNumber(last) {
            return last.count <= 2 || words.count > 1 && copyWords.contains(words[words.count - 1].lowercased())
        }
        if last.count > 2, last.first == "(", last.last == ")" {
            return isNumber(last.dropFirst().dropLast())
        }
        return copyWords.contains(last.lowercased())
    }

    private static let copyWords: Set<String> = [
        "copy", "kopie", "copie", "copia", "cópia", "kopia", "копия", "копія", "kopyası", "のコピー", "副本", "拷貝", "복사본",
    ]

    /// True when `text` is one or more decimal digits, in any script.
    private static func isNumber(_ text: Substring) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { $0.properties.numericType == .decimal }
    }

    /// The entries that mark the top of a Git, Mercurial, or Subversion working copy.
    private static let repositoryMarks = [".git", ".hg", ".svn"]

    static func isRepository(_ directory: URL) -> Bool {
        repositoryMarks.contains { mark in
            var info = stat()
            return lstat(directory.appending(path: mark).path(percentEncoded: false), &info) == 0
        }
    }

    /// Whether `folder` is a repository or sits inside one, checking each folder above it up to the root, or up to
    /// the home folder, which is never asked: dotfiles kept in a repository there make no folder in it a project.
    /// The walk checks only the folders it finds, and the enumerator never yields the folder it starts from, so a
    /// chosen folder is checked here.
    static func isInsideARepository(_ folder: URL, home: URL) -> Bool {
        var url = folder.resolvingSymlinksInPath()
        let stop = Self.path(of: home.resolvingSymlinksInPath())
        while true {
            let path = Self.path(of: url)
            guard path != stop else { return false }
            if isRepository(url) { return true }
            guard path != "/", !path.isEmpty else { return false }
            let parent = url.deletingLastPathComponent()
            guard Self.path(of: parent) != path else { return false }
            url = parent
        }
    }

    static func path(of url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

final class ReadProgress: Sendable {
    private let bytesRead = Mutex<Int64>(0)
    private let bytesToRead: Int64
    private let report: @Sendable (DuplicateScanProgress) -> Void
    private let throttle = ReportThrottle()

    init(bytesToRead: Int64, report: @escaping @Sendable (DuplicateScanProgress) -> Void) {
        self.bytesToRead = bytesToRead
        self.report = report
    }

    func add(_ count: Int) {
        // Reports outside the lock: the report updates the interface, and every other read would wait for it.
        let total = bytesRead.withLock { total in
            total += Int64(count)
            return total
        }
        guard throttle.allows(isLast: total >= bytesToRead) else { return }
        report(.verifying(bytesRead: total, bytesToRead: bytesToRead))
    }
}

/// Lets a progress report through at most once every 50 ms, and always the last one, since each report is work
/// on the main actor.
final class ReportThrottle: Sendable {
    private let lastLetThrough = Mutex<ContinuousClock.Instant?>(nil)

    func allows(isLast: Bool) -> Bool {
        let now = ContinuousClock.now
        return lastLetThrough.withLock { last in
            guard isLast || last.map({ now - $0 >= .milliseconds(50) }) ?? true else { return false }
            last = now
            return true
        }
    }
}

private extension String {
    func isInside(_ base: String) -> Bool {
        PathComponents.isPath(self, atOrInside: base)
    }
}
