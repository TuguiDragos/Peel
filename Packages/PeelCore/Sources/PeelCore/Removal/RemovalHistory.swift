public import Foundation
internal import PeelPrivileged

public struct RemovalRecord: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    /// Everything removed in one go shares a batch, so History can show it as one entry.
    public let batch: UUID
    public let originalURL: URL
    public private(set) var trashedURL: URL
    /// The disk the item moved on, when it isn't the startup disk. Nil in a record written before Peel kept it.
    public let disk: TrashedDisk?
    public let date: Date
    /// Which item went to the Trash, so one that lands in the same place later is never taken for it. Nil in a record
    /// written before Peel kept it.
    public let identity: TrashedItem.Identity?
    /// Nil when Peel could not measure the item. It is never read as zero.
    public let size: Int64?
    /// What the items belonged to: an app, an orphan group, a file name.
    public let source: String
    public let tool: String
    /// A key for a source Peel names itself (a tool, a Space area, a kind of installer, or a count of apps), so
    /// History can show it in the user's language. `source` then holds the English name, which `peel` prints.
    public let sourceKey: String?
    public let stoppedJob: String?
    /// True when the item shared most of its storage with another copy, so moving it freed only its own part.
    public let sharedStorage: Bool?

    public init(
        id: UUID = UUID(),
        batch: UUID,
        item: TrashedItem,
        size: Int64?,
        source: String,
        sourceKey: String? = nil,
        tool: String,
        sharedStorage: Bool? = nil
    ) {
        self.id = id
        self.batch = batch
        originalURL = item.originalURL
        trashedURL = item.trashedURL
        disk = TrashedDisk(of: item.trashedURL)
        date = item.date
        identity = item.identity
        self.size = size
        self.source = source
        self.sourceKey = sourceKey
        self.tool = tool
        stoppedJob = item.stoppedJob
        self.sharedStorage = sharedStorage
    }

    /// Reads a negative size as zero, since any process of the user can rewrite the History file.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        batch = try container.decode(UUID.self, forKey: .batch)
        originalURL = try container.decode(URL.self, forKey: .originalURL)
        trashedURL = try container.decode(URL.self, forKey: .trashedURL)
        disk = try? container.decodeIfPresent(TrashedDisk.self, forKey: .disk)
        date = try container.decode(Date.self, forKey: .date)
        identity = try container.decodeIfPresent(TrashedItem.Identity.self, forKey: .identity)
        size = try container.decodeIfPresent(Int64.self, forKey: .size).map { max(0, $0) }
        source = try container.decode(String.self, forKey: .source)
        tool = try container.decode(String.self, forKey: .tool)
        sourceKey = try container.decodeIfPresent(String.self, forKey: .sourceKey)
        stoppedJob = try container.decodeIfPresent(String.self, forKey: .stoppedJob)
        sharedStorage = try container.decodeIfPresent(Bool.self, forKey: .sharedStorage)
    }

    public var trashedItem: TrashedItem {
        TrashedItem(
            originalURL: originalURL, trashedURL: trashedURL, date: date, identity: identity, stoppedJob: stoppedJob
        )
    }

    public var isStillInTrash: Bool {
        trashedItem.isInTheTrash
    }

    /// Where the item stands now: in the Trash, gone from it, or not known when macOS won't let Peel look.
    public var standing: TrashedItem.Standing {
        trashedItem.standing
    }

    /// False while the disk whose Trash holds the item is not connected. The item may still be there, so the
    /// record is not treated as missing. A disk is known by its volume, which stays with it when it is renamed, while
    /// its name and place can be another disk's; a record written before Peel kept it goes by the name in its path.
    public func isOnAConnectedDisk(_ disks: MountedDisks) -> Bool {
        if let disk { return disks.place(of: disk.volume) != nil }
        let components = trashedURL.pathComponents
        guard components.count > 2, components[1] == "Volumes" else { return true }
        return URL(filePath: "/Volumes/" + components[2]).isThere
    }

    /// The record with its place in the Trash where its disk is mounted now.
    public func located(on disks: MountedDisks) -> RemovalRecord {
        guard let disk, let place = disks.place(of: disk.volume) else { return self }
        var located = self
        located.trashedURL = URL(filePath: place == "/" ? "/" + disk.path : place + "/" + disk.path)
        return located
    }
}

/// The disk an item moved on: its volume's UUID, and where the item was on that disk.
public struct TrashedDisk: Sendable, Codable, Hashable {
    public let volume: String
    /// The item's path from the top of the disk, without the place the disk was mounted at.
    public let path: String

    /// The disk `url` is on, or nil for the startup disk, which is always there, or when macOS doesn't say. The home's
    /// Trash is on the home's disk, which is there while anyone uses it, so nothing is asked for what is in the home.
    init?(of url: URL) {
        let home = URL.homeDirectory.path(percentEncoded: false)
        guard !PathComponents.isPath(url.path(percentEncoded: false), inside: home) else { return nil }
        let keys: Set<URLResourceKey> = [.volumeURLKey, .volumeUUIDStringKey, .volumeIsRootFileSystemKey]
        guard let values = try? url.resourceValues(forKeys: keys), values.volumeIsRootFileSystem != true,
              let volume = values.volumeUUIDString, let mount = values.volume
        else { return nil }
        // The kernel's spelling, as the mount point is spelled: `resolvingSymlinksInPath` drops `/private`.
        let place = MountedDisks.path(of: mount)
        guard let item = PathPattern.located(url.path(percentEncoded: false)),
              PathComponents.isPath(item, inside: place)
        else { return nil }
        self.volume = volume
        path = String(item.dropFirst(place.count).drop { $0 == "/" })
    }
}

/// The disks mounted now, each by its volume's UUID, read once for whatever asks about many records.
public struct MountedDisks: Sendable {
    private let places: [String: String]

    public static func now() -> MountedDisks {
        let key = URLResourceKey.volumeUUIDStringKey
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [key], options: []) ?? []
        let places = volumes.compactMap { url in
            (try? url.resourceValues(forKeys: [key]).volumeUUIDString).flatMap(\.self).map { ($0, path(of: url)) }
        }
        return MountedDisks(places: Dictionary(places, uniquingKeysWith: { first, _ in first }))
    }

    func place(of volume: String) -> String? {
        places[volume]
    }

    static func path(of url: URL) -> String {
        let path = url.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

extension [URL: Int64] {
    /// The sizes History records, by item: those that were measured. An item whose size is not known is left out,
    /// and is recorded as unknown rather than as zero.
    public init(measured sizes: some Sequence<(URL, Int64?)>) {
        self.init(sizes.compactMap { url, size in size.map { (url, $0) } }, uniquingKeysWith: { first, _ in first })
    }
}

extension Sequence<RemovalRecord> {
    /// The sum of the sizes, incomplete when one of them is not known.
    public var totalSize: SizeTotal {
        SizeTotal(map(\.size))
    }

    /// Shallowest first, so a folder is put back before anything that was inside it. A child put back first would
    /// make a new folder at its parent's path, and the parent could then not be put back.
    public var inPutBackOrder: [RemovalRecord] {
        let depth = { (record: RemovalRecord) in
            PathComponents.of(record.originalURL.path(percentEncoded: false)).count
        }
        return sorted { depth($0) < depth($1) }
    }
}

/// Where the History file lives: the record of everything Peel moved to the Trash. Only `RemovalLog` reads and
/// writes it, so the file is changed from one place.
public enum RemovalHistory {
    public static var defaultURL: URL {
        PeelFolder.url.appending(path: "removals.json")
    }

    /// The record of what Peel refused to move. It is a file of its own because Put Back reads every row of the
    /// History file as a request to move something back.
    public static var refusalsURL: URL {
        PeelFolder.url.appending(path: "refusals.json")
    }
}
