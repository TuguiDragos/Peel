import Foundation
import PeelCore

struct AppRecord: Encodable {
    let name: String
    let bundleIdentifier: String?
    let version: String?
    let path: String
    let isFromAppStore: Bool

    init(_ app: InstalledApp) {
        name = app.name
        bundleIdentifier = app.bundleIdentifier
        version = app.version
        path = Output.path(app.url)
        isFromAppStore = app.isFromAppStore
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case bundleIdentifier
        case version
        case path
        case isFromAppStore
    }

    /// Encodes a missing identifier or version as `null`. The synthesized encoding would leave the key out, and a
    /// script needs every record to have the same keys.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(version, forKey: .version)
        try container.encode(path, forKey: .path)
        try container.encode(isFromAppStore, forKey: .isFromAppStore)
    }
}

struct LeftoverRecord: Encodable {
    let path: String
    /// Nil when the size isn't known, as for a folder that didn't answer in time. A script must not count it as zero.
    let size: Int64?
    let reason: String
    let confidence: String
    /// Why Peel left the item unselected on purpose, or `null` when it didn't.
    let heldBack: String?
    let sharedWith: [String]
    /// Other copies of the app that use the item too, by their place, since they share its identifier.
    let otherCopies: [String]
    let isRecommended: Bool
    let needsAdministrator: Bool

    init(_ leftover: Leftover) {
        path = Output.path(leftover.url)
        size = LeftoversCommand.measured(leftover)
        reason = leftover.match.reason.rawValue
        confidence = leftover.match.confidence.summary
        heldBack = leftover.match.heldBack?.rawValue
        sharedWith = leftover.match.sharedWith
        otherCopies = leftover.match.otherCopies.map(Output.path)
        isRecommended = leftover.match.isRecommended
        needsAdministrator = leftover.requiresPrivileges
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case size
        case reason
        case confidence
        case heldBack
        case sharedWith
        case otherCopies
        case isRecommended
        case needsAdministrator
    }

    /// Encodes an unknown size and a missing `heldBack` as `null`, for the reason `AppRecord` gives.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(size, forKey: .size)
        try container.encode(reason, forKey: .reason)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(heldBack, forKey: .heldBack)
        try container.encode(sharedWith, forKey: .sharedWith)
        try container.encode(otherCopies, forKey: .otherCopies)
        try container.encode(isRecommended, forKey: .isRecommended)
        try container.encode(needsAdministrator, forKey: .needsAdministrator)
    }
}

/// A size in bytes for JSON output. An unknown size is encoded as `null`: the key is never left out, and the
/// size is never given as zero.
struct MeasuredSize: Encodable {
    let bytes: Int64?

    init(_ bytes: Int64?) {
        self.bytes = bytes
    }

    /// A total is known only when all of its parts are. Otherwise the sum is only a lower bound, so it is `null`.
    init(_ total: SizeTotal) {
        bytes = total.isComplete ? total.known : nil
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let bytes {
            try container.encode(bytes)
        } else {
            try container.encodeNil()
        }
    }
}

struct FileRecord: Encodable {
    let path: String
    let size: MeasuredSize
}
