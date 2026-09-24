public import Foundation

public struct RemovalRecord: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    /// Everything removed in one go shares a batch, so History can show it as one entry.
    public let batch: UUID
    public let originalURL: URL
    public let trashedURL: URL
    public let date: Date
    public let size: Int64
    /// What the items belonged to: an app, an orphan group, a file name.
    public let source: String
    public let tool: String
    /// A key for a source Peel names itself (a tool, a Space area, a kind of installer, or a count of apps), so
    /// History can show it in the user's language. `source` then holds the English name, which `peel` prints.
    public let sourceKey: String?

    public init(id: UUID = UUID(), batch: UUID, item: TrashedItem, size: Int64, source: String, sourceKey: String? = nil, tool: String) {
        self.id = id
        self.batch = batch
        originalURL = item.originalURL
        trashedURL = item.trashedURL
        date = item.date
        self.size = size
        self.source = source
        self.sourceKey = sourceKey
        self.tool = tool
    }

    /// Reads a negative size as zero, since any process of the user can rewrite the History file.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        batch = try container.decode(UUID.self, forKey: .batch)
        originalURL = try container.decode(URL.self, forKey: .originalURL)
        trashedURL = try container.decode(URL.self, forKey: .trashedURL)
        date = try container.decode(Date.self, forKey: .date)
        size = max(0, try container.decode(Int64.self, forKey: .size))
        source = try container.decode(String.self, forKey: .source)
        tool = try container.decode(String.self, forKey: .tool)
        sourceKey = try container.decodeIfPresent(String.self, forKey: .sourceKey)
    }

    public var trashedItem: TrashedItem {
        TrashedItem(originalURL: originalURL, trashedURL: trashedURL, date: date)
    }

    public var isStillInTrash: Bool {
        trashedURL.isThere
    }

    /// False while the disk whose Trash holds the item is not connected. The item may still be there, so the
    /// record is not treated as missing.
    public var isOnAConnectedDisk: Bool {
        let components = trashedURL.pathComponents
        guard components.count > 2, components[1] == "Volumes" else { return true }
        return URL(filePath: "/Volumes/" + components[2]).isThere
    }
}

extension Sequence<RemovalRecord> {
    /// The sum of the sizes, capped at `Int64.max` rather than crashing on overflow: the sizes come from a file.
    public var totalSize: Int64 {
        reduce(0) { $0.addingCapped($1.size) }
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
