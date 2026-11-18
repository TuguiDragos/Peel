public import Foundation

/// Where the records of one removal stand, read from the disk once: which are still in the Trash, which are in the
/// Trash of a disk that isn't connected, and which Peel can't look at. Any other record has left the Trash. History's
/// page is drawn again at every change of its selection, so what follows from the disk is worked out here, once.
public struct RemovalStanding: Sendable {
    public private(set) var inTrash: Set<RemovalRecord.ID> = []
    public private(set) var away: Set<RemovalRecord.ID> = []
    public private(set) var notKnown: Set<RemovalRecord.ID> = []
    public private(set) var backInItsPlace: Set<RemovalRecord.ID> = []
    /// What macOS answered when Peel looked for those, each answer once.
    public private(set) var whyNotKnown: [SystemError] = []
    /// What can be put back, in the removal's order.
    public private(set) var restorable: [RemovalRecord.ID] = []
    public private(set) var restorableSize = SizeTotal([])
    /// How many records have left the Trash.
    public private(set) var missingCount = 0
    private var locatedRecords: [RemovalRecord.ID: RemovalRecord] = [:]

    /// Reads the disk off the main actor.
    @concurrent
    public static func of(_ records: [RemovalRecord]) async -> RemovalStanding {
        RemovalStanding(records)
    }

    /// The records among `records` that have left the Trash, looked at again.
    @concurrent
    public static func stillGone(_ records: [RemovalRecord]) async -> [RemovalRecord] {
        let disks = MountedDisks.now()
        return records.filter { $0.isOnAConnectedDisk(disks) && $0.located(on: disks).standing == .gone }
    }

    /// Every record among `records` that has left the Trash, looked at once: never one still in the Trash, and one on
    /// a disk that isn't connected, or that Peel can't look at, is counted apart.
    @concurrent
    public static func leftTheTrash(_ records: [RemovalRecord]) async -> LeftTheTrash {
        let standing = RemovalStanding(records)
        return LeftTheTrash(
            standing.missing(among: records), away: standing.away.count, notKnown: standing.notKnown.count
        )
    }

    /// The records among `records` still on a disk that isn't connected, looked at again.
    @concurrent
    public static func stillAway(_ records: [RemovalRecord]) async -> [RemovalRecord] {
        let disks = MountedDisks.now()
        return records.filter { !$0.isOnAConnectedDisk(disks) }
    }

    init(_ records: [RemovalRecord], disks: MountedDisks = .now()) {
        var restorableRecords: [RemovalRecord] = []
        for record in records {
            // Another disk can have this one's name and place, so a disk that isn't connected is asked about first.
            guard record.isOnAConnectedDisk(disks) else {
                away.insert(record.id)
                continue
            }
            let located = record.located(on: disks)
            locatedRecords[record.id] = located
            let place = located.standing
            if place == .inTheTrash {
                inTrash.insert(record.id)
                restorableRecords.append(record)
            } else if case .notKnown(let error) = place {
                notKnown.insert(record.id)
                if !whyNotKnown.contains(error) { whyNotKnown.append(error) }
            } else if place == .backInItsPlace {
                backInItsPlace.insert(record.id)
            } else {
                missingCount += 1
            }
        }
        restorable = restorableRecords.map(\.id)
        restorableSize = restorableRecords.totalSize
    }

    /// `record` with its places as they are now: its disk may be mounted at another place than when it moved.
    public func located(_ record: RemovalRecord) -> RemovalRecord {
        locatedRecords[record.id] ?? record
    }

    /// The records among `records` that have left the Trash.
    public func missing(among records: [RemovalRecord]) -> [RemovalRecord] {
        records.filter {
            !inTrash.contains($0.id) && !away.contains($0.id) && !notKnown.contains($0.id)
                && !backInItsPlace.contains($0.id)
        }
    }

    /// The records among `records` that are selected and can be put back, in their order.
    public func selected(among records: [RemovalRecord], in selection: Set<RemovalRecord.ID>) -> [RemovalRecord] {
        records.filter { inTrash.contains($0.id) && selection.contains($0.id) }
    }

    public func selectedCount(in selection: Set<RemovalRecord.ID>) -> Int {
        selection.count(where: inTrash.contains)
    }
}

/// What has left the Trash among History's records: those records, in History's order, and the removals they belong
/// to, one only partly gone among them.
public struct LeftTheTrash: Sendable {
    public let records: [RemovalRecord]
    public let removals: Set<UUID>
    /// How many of the other records are on a disk that isn't connected, and how many Peel can't look at: whether
    /// those have left is not known.
    public let away: Int
    public let notKnown: Int

    init(_ records: [RemovalRecord], away: Int = 0, notKnown: Int = 0) {
        self.records = records
        removals = Set(records.map(\.batch))
        self.away = away
        self.notKnown = notKnown
    }
}
