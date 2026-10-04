import CryptoKit
import Darwin
import Foundation

/// Finds folders whose whole contents are identical. It lists the folders itself instead of reusing the file
/// scan, which keeps one candidate per inode and so cannot tell what a folder holds. Anything the walk cannot
/// look at leaves its folder, and every folder above it, out of the comparison.
struct FolderDuplicates: Sendable {
    private static let depthLimit = 64

    private let exclusions: Exclusions
    private let managed: Set<String>
    private let neverProjects: Set<String>

    init(managed: Set<String> = [], exclusions: Exclusions = .none, neverProjects: Set<String> = []) {
        self.managed = managed
        self.exclusions = exclusions
        self.neverProjects = neverProjects
    }

    private final class Folder {
        let url: URL
        let identity: FileIdentity
        /// A package, such as an app, a hidden folder, or a folder inside one of them: compared as part of the
        /// folder around it, and never offered on its own. Nothing here checks whether an app is running, and the
        /// file scan leaves hidden items out on purpose, since a hidden folder is a tool's settings or data.
        let isNeverOffered: Bool
        var files: [(name: String, identity: FileIdentity)] = []
        var children: [(name: String, folder: Folder)] = []
        var isWhole = true
        var isProject = false
        var fileCount = 0
        var size: Int64 = 0
        /// Its files' lengths less their holes: `held` for the files listed here, `totalHeld` with every folder inside.
        var held: Int64 = 0
        var totalHeld: Int64 = 0
        var shape: SHA256.Digest?

        init(url: URL, identity: FileIdentity, isNeverOffered: Bool) {
            self.url = url
            self.identity = identity
            self.isNeverOffered = isNeverOffered
        }
    }

    private struct ShapeKey: Hashable {
        let shape: SHA256.Digest
        let fileCount: Int
        let size: Int64
    }

    func groups(
        in roots: [URL],
        minimumSize: Int64,
        downloads: String,
        removalGuard: RemovalGuard,
        known: KnownDigests? = nil,
        progress: @escaping @Sendable (DuplicateScanProgress) -> Void
    ) async throws(CancellationError) -> [DuplicateFolderGroup] {
        var listed: [Folder] = []
        var visited = Set<String>()
        var found = 0
        let listing = ReportThrottle()
        for root in roots.map({ $0.resolvingSymlinksInPath() })
        where visited.insert(DuplicateFinder.path(of: root)).inserted {
            var info = stat()
            guard lstat(root.path(percentEncoded: false), &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { continue }
            let folder = try list(root, identity: FileIdentity(info), depth: 0, isNeverOffered: false) {
                found += 1
                if listing.allows(isLast: false) { progress(.listing(foldersFound: found)) }
            }
            listed.append(folder)
        }
        progress(.listing(foldersFound: found))

        let candidates = self.candidates(in: listed, minimumSize: minimumSize)
        // Only the candidates are needed from here, and each holds the folders inside it.
        listed.removeAll()
        guard !candidates.isEmpty else { return [] }

        let files = Self.files(in: candidates)
        let comparing = ReportThrottle()
        let sampled = await FileDigest.many(files, digest: { FileDigest.sample(of: $0.url, identity: $0.identity, known: known) }) { completed in
            if comparing.allows(isLast: completed == files.count) {
                progress(.comparing(filesCompared: completed, filesToCompare: files.count))
            }
        }
        guard !Task.isCancelled else { throw CancellationError() }
        let samples = Self.table(sampled)
        let alike = grouped(candidates, by: samples).flatMap(\.folders)

        let toRead = Self.files(in: alike).filter { FileDigest.isSampled(size: $0.identity.size) }
        let reading = ReadProgress(bytesToRead: FileDigest.bytesToRead(toRead.map(\.identity), known: known), report: progress)
        let read = await FileDigest.many(toRead) { file in
            FileDigest.full(of: file.url, identity: file.identity, known: known, onRead: reading.add)
        }
        guard !Task.isCancelled else { throw CancellationError() }
        var contents = samples.filter { !FileDigest.isSampled(size: $0.key.size) }
        contents.merge(Self.table(read)) { _, verified in verified }

        return build(grouped(alike, by: contents), downloads: downloads, removalGuard: removalGuard)
    }

    /// Whether `folder` still holds exactly what the scan compared, listed again the same way. The exclusions and
    /// managed folders are not needed: a folder that held an excluded or managed item was never offered.
    static func holdsTheSameContents(_ folder: DuplicateFolder) -> Bool {
        FolderDuplicates(neverProjects: folder.neverProjects).contents(of: folder.url).map { $0 == folder.contents } ?? false
    }

    private func contents(of url: URL) -> String? {
        var info = stat()
        guard lstat(url.path(percentEncoded: false), &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return nil }
        guard let folder = try? list(url, identity: FileIdentity(info), depth: 0, isNeverOffered: false, onListing: {}) else { return nil }
        return identity(of: folder).map(Self.hexadecimal)
    }

    private func identity(of folder: Folder) -> SHA256.Digest? {
        guard folder.isWhole else { return nil }
        var hasher = SHA256()
        for (name, identity) in folder.files.sorted(by: { $0.name < $1.name }) {
            hasher.update(data: Self.field("f", name, identity.numbers))
        }
        for (name, child) in folder.children.sorted(by: { $0.name < $1.name }) {
            guard let digest = identity(of: child) else { return nil }
            hasher.update(data: Self.field("d", name, Array(digest)))
        }
        return hasher.finalize()
    }

    private func list(
        _ url: URL,
        identity: FileIdentity,
        depth: Int,
        isNeverOffered: Bool,
        onListing: () -> Void
    ) throws(CancellationError) -> Folder {
        let folder = Folder(url: url, identity: identity, isNeverOffered: isNeverOffered)
        guard !Task.isCancelled else { throw CancellationError() }
        onListing()
        // The listing and each entry get an autorelease pool of their own, or what Foundation reads for every entry
        // would pile up in memory until the walk ends.
        guard depth < Self.depthLimit, let contents = autoreleasepool(invoking: { entries(of: url, depth: depth) }) else {
            folder.isWhole = false
            return folder
        }
        guard !contents.isProject else {
            folder.isProject = true
            return folder
        }

        for entry in contents.entries {
            switch autoreleasepool(invoking: { look(at: entry, isNeverOffered: isNeverOffered) }) {
            case .folder(let name, let identity, let isNeverOffered):
                let child = try list(entry, identity: identity, depth: depth + 1, isNeverOffered: isNeverOffered, onListing: onListing)
                guard !child.isProject else {
                    folder.isWhole = false
                    continue
                }
                folder.isWhole = folder.isWhole && child.isWhole
                folder.children.append((name, child))
            case .file(let name, let identity, let held):
                folder.files.append((name, identity))
                folder.held += held
            case .leftOut:
                folder.isWhole = false
            }
        }
        return folder
    }

    /// The entries of `url`, and whether a build file among them makes it a project.
    private func entries(of url: URL, depth: Int) -> (entries: [URL], isProject: Bool)? {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return nil
        }
        let isProject = depth > 0 && !neverProjects.contains(DuplicateFinder.path(of: url))
            && entries.contains { ProjectArtifacts.isMarker($0.lastPathComponent) }
        return (entries, isProject)
    }

    private enum Entry {
        case folder(name: String, identity: FileIdentity, isNeverOffered: Bool)
        case file(name: String, identity: FileIdentity, held: Int64)
        /// Something the comparison leaves out, and with it the folder around it.
        case leftOut
    }

    private func look(at entry: URL, isNeverOffered: Bool) -> Entry {
        var info = stat()
        guard lstat(entry.path(percentEncoded: false), &info) == 0, !exclusions.excludes(entry) else { return .leftOut }
        switch info.st_mode & S_IFMT {
        case S_IFDIR:
            guard !managed.contains(DuplicateFinder.path(of: entry)),
                  entry.lastPathComponent != "node_modules",
                  !DuplicateFinder.isAUserLibrary(entry),
                  !DuplicateFinder.isRepository(entry)
            else { return .leftOut }
            return .folder(
                name: entry.lastPathComponent,
                identity: FileIdentity(info),
                isNeverOffered: isNeverOffered || Self.isHidden(entry, info) || entry.isAPackage
            )
        case S_IFREG:
            guard info.st_flags & UInt32(SF_DATALESS) == 0, !entry.isInTheCloud else { return .leftOut }
            return .file(name: entry.lastPathComponent, identity: FileIdentity(info), held: ReclaimableSpace.held(info))
        default:
            return .leftOut
        }
    }

    /// A digest of the names and sizes in `folder`, so folders that cannot hold the same bytes are told apart
    /// without reading a file. It also fills in the folder's file count, size, and `totalHeld`.
    private func shape(of folder: Folder) -> SHA256.Digest {
        if let shape = folder.shape { return shape }
        var hasher = SHA256()
        var fileCount = folder.files.count
        var size = folder.files.reduce(0) { $0 + $1.identity.size }
        var held = folder.held
        for (name, identity) in folder.files.sorted(by: { $0.name < $1.name }) {
            hasher.update(data: Self.field("f", name, Self.number(identity.size)))
        }
        for (name, child) in folder.children.sorted(by: { $0.name < $1.name }) {
            let digest = shape(of: child)
            fileCount += child.fileCount
            size += child.size
            held += child.totalHeld
            hasher.update(data: Self.field("d", name, Array(digest)))
        }
        folder.fileCount = fileCount
        folder.size = size
        folder.totalHeld = held
        let digest = hasher.finalize()
        folder.shape = digest
        return digest
    }

    /// Returns every whole, non-empty folder whose shape matches another's. A folder reached twice (through a
    /// link, or as a chosen folder inside another) counts once, known by its inode as a file is. `minimumSize`
    /// is a floor on the bytes a folder holds, as it is for a file.
    private func candidates(in roots: [Folder], minimumSize: Int64) -> [Folder] {
        var byShape: [ShapeKey: [Folder]] = [:]
        var seen = Set<FileIdentity.Link>()

        func visit(_ folder: Folder) {
            if folder.isWhole, !folder.isNeverOffered, folder.fileCount > 0, folder.totalHeld >= minimumSize,
               seen.insert(folder.identity.link).inserted {
                let key = ShapeKey(shape: shape(of: folder), fileCount: folder.fileCount, size: folder.size)
                byShape[key, default: []].append(folder)
            }
            for (_, child) in folder.children {
                visit(child)
            }
        }
        for root in roots {
            // Fills in every folder's totals, which `visit` reads before it asks for a shape.
            _ = shape(of: root)
            visit(root)
        }
        return byShape.values.filter { $0.count > 1 }.flatMap { $0 }
    }

    private func grouped(
        _ folders: [Folder],
        by contents: [FileIdentity: ContentDigest]
    ) -> [(digest: SHA256.Digest, folders: [Folder])] {
        var byContent: [SHA256.Digest: [Folder]] = [:]
        for folder in folders {
            guard let digest = content(of: folder, using: contents) else { continue }
            byContent[digest, default: []].append(folder)
        }
        return byContent.filter { $0.value.count > 1 }.map { (digest: $0.key, folders: $0.value) }
    }

    private func content(of folder: Folder, using contents: [FileIdentity: ContentDigest]) -> SHA256.Digest? {
        var hasher = SHA256()
        guard let extras = FileExtras.of(folder.url) else { return nil }
        hasher.update(data: Self.number(extras.count) + extras)
        for (name, identity) in folder.files.sorted(by: { $0.name < $1.name }) {
            guard let digest = contents[identity], let extras = FileExtras.of(folder.url.appending(path: name)) else {
                return nil
            }
            hasher.update(data: Self.field("f", name, digest.bytes + Self.number(extras.count) + extras))
        }
        for (name, child) in folder.children.sorted(by: { $0.name < $1.name }) {
            guard let digest = content(of: child, using: contents) else { return nil }
            hasher.update(data: Self.field("d", name, Array(digest)))
        }
        return hasher.finalize()
    }

    /// Builds the groups to offer, keeping only the topmost folder of each identical tree, so two copies of one
    /// tree make one row, not a row for every folder in it.
    private func build(
        _ groups: [(digest: SHA256.Digest, folders: [Folder])],
        downloads: String,
        removalGuard: RemovalGuard
    ) -> [DuplicateFolderGroup] {
        let allowed = groups
            .map { (digest: $0.digest, folders: $0.folders.filter { removalGuard.allowsRemoval(of: $0.url) }) }
            .filter { $0.folders.count > 1 }
        let offered = Set(allowed.flatMap { $0.folders.map { DuplicateFinder.path(of: $0.url) } })

        return allowed.compactMap { group -> DuplicateFolderGroup? in
            let topmost = group.folders.filter { !DuplicateFinder.isInside(offered, $0.url) }
            guard topmost.count > 1 else { return nil }
            let sorted = topmost.sorted {
                DuplicateFinder.keepRank(of: $0.url, creationTime: $0.identity.creationTime, downloads: downloads)
                    < DuplicateFinder.keepRank(of: $1.url, creationTime: $1.identity.creationTime, downloads: downloads)
            }
            let folders = sorted.compactMap(duplicate)
            guard folders.count > 1 else { return nil }
            return DuplicateFolderGroup(id: Self.hexadecimal(group.digest), folders: folders)
        }
        .sorted { ($0.reclaimableSize, $0.size, $1.id) > ($1.reclaimableSize, $1.size, $0.id) }
    }

    private func duplicate(_ folder: Folder) -> DuplicateFolder? {
        guard let contents = identity(of: folder) else { return nil }
        return DuplicateFolder(
            url: folder.url,
            fileCount: folder.fileCount,
            size: folder.size,
            reclaimableSize: Self.reclaimable(folder),
            contents: Self.hexadecimal(contents),
            neverProjects: neverProjects
        )
    }

    /// Whether the entry is hidden the way Finder hides it: a leading dot, or the hidden flag.
    private static func isHidden(_ url: URL, _ info: stat) -> Bool {
        url.lastPathComponent.hasPrefix(".") || info.st_flags & UInt32(UF_HIDDEN) != 0
    }

    private static func reclaimable(_ folder: Folder) -> Int64 {
        folder.files.reduce(0) { $0 + ReclaimableSpace.of(folder.url.appending(path: $1.name)) }
            + folder.children.reduce(0) { $0 + reclaimable($1.folder) }
    }

    private static func files(in folders: [Folder]) -> [(url: URL, identity: FileIdentity)] {
        var seen = Set<FileIdentity>()
        var files: [(url: URL, identity: FileIdentity)] = []

        func visit(_ folder: Folder) {
            for (name, identity) in folder.files where seen.insert(identity).inserted {
                files.append((folder.url.appending(path: name), identity))
            }
            for (_, child) in folder.children {
                visit(child)
            }
        }
        for folder in folders {
            visit(folder)
        }
        return files
    }

    private static func table(
        _ digests: [(item: (url: URL, identity: FileIdentity), digest: ContentDigest)]
    ) -> [FileIdentity: ContentDigest] {
        Dictionary(digests.map { ($0.item.identity, $0.digest) }, uniquingKeysWith: { first, _ in first })
    }

    private static func hexadecimal(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Encodes one entry as a tag, the name's length, the name, and `tail`. The length comes first so a name
    /// cannot be misread as the end of one entry and the start of the next.
    private static func field(_ tag: String, _ name: String, _ tail: [UInt8]) -> [UInt8] {
        var bytes = Array(tag.utf8)
        let name = Array(name.utf8)
        bytes += number(name.count)
        bytes += name
        bytes += tail
        return bytes
    }

    private static func number(_ value: some FixedWidthInteger) -> [UInt8] {
        withUnsafeBytes(of: UInt64(truncatingIfNeeded: value).littleEndian, Array.init)
    }
}

private extension FileIdentity {
    /// The numbers `holdsTheSameContents` compares.
    var numbers: [UInt8] {
        [UInt64(truncatingIfNeeded: link.device), UInt64(link.inode), UInt64(bitPattern: size),
         UInt64(truncatingIfNeeded: modificationTime), UInt64(truncatingIfNeeded: creationTime)]
            .flatMap { withUnsafeBytes(of: $0.littleEndian, Array.init) }
    }
}
