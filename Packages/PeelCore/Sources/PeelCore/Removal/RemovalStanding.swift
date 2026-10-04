public import Foundation

/// Where the records of one removal stand, read from the disk once: which are still in the Trash, which are in the
/// Trash of a disk that isn't connected, and which Peel can't look at. Any other record has left the Trash. History's
/// page is drawn again at every change of its selection, so what follows from the disk is worked out here, once.
public struct RemovalStanding: Sendable {
    public private(set) var inTrash: Set<RemovalRecord.ID> = []
    public private(set) var away: Set<RemovalRecord.ID> = []
    public private(set) var notKnown: Set<RemovalRecord.ID> = []
    /// What can be put back, in the removal's order.
    public private(set) var restorable: [RemovalRecord.ID] = []
    public private(set) var restorableSize = SizeTotal([])
    /// How many records have left the Trash.
    public private(set) var missingCount = 0

    /// Reads the disk off the main actor.
    @concurrent
    public static func of(_ records: [RemovalRecord]) async -> RemovalStanding {
        RemovalStanding(records)
    }

    /// The records among `records` that have left the Trash, looked at again.
    @concurrent
    public static func stillGone(_ records: [RemovalRecord]) async -> [RemovalRecord] {
        records.filter { $0.standing == .gone && $0.isOnAConnectedDisk }
    }

    init(_ records: [RemovalRecord]) {
        var restorableRecords: [RemovalRecord] = []
        for record in records {
            let place = record.standing
            if place == .inTheTrash {
                inTrash.insert(record.id)
                restorableRecords.append(record)
            } else if !record.isOnAConnectedDisk {
                away.insert(record.id)
            } else if place == .notKnown {
                notKnown.insert(record.id)
            } else {
                missingCount += 1
            }
        }
        restorable = restorableRecords.map(\.id)
        restorableSize = restorableRecords.totalSize
    }

    /// The records among `records` that have left the Trash.
    public func missing(among records: [RemovalRecord]) -> [RemovalRecord] {
        records.filter { !inTrash.contains($0.id) && !away.contains($0.id) && !notKnown.contains($0.id) }
    }

    /// The records among `records` that are selected and can be put back, in their order.
    public func selected(among records: [RemovalRecord], in selection: Set<RemovalRecord.ID>) -> [RemovalRecord] {
        records.filter { inTrash.contains($0.id) && selection.contains($0.id) }
    }

    public func selectedCount(in selection: Set<RemovalRecord.ID>) -> Int {
        selection.count(where: inTrash.contains)
    }
}
