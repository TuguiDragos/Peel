public import Foundation
internal import PeelPrivileged

/// Running totals of what Peel and `peel` have moved to the Trash since Peel was installed, kept in `totals.json`
/// beside History. They are not worked out from History, which is capped and drops whole batches once it is full,
/// so a total taken from it would go down over time. `RemovalLog` adds to them as it records, whoever records.
public struct RemovalTotals: Sendable, Equatable, Codable {
    /// Incomplete once a removal held something Peel could not measure: the total is then only the least it can be.
    public private(set) var bytes = SizeTotal(known: 0, isComplete: true)
    public private(set) var items = 0
    public private(set) var apps = 0
    public private(set) var biggest = SizeTotal(known: 0, isComplete: true)
    /// The removal counted last and what it has moved so far: a removal of several parts is recorded a part at a
    /// time, and it is the whole of it that can be the biggest.
    private var last: Removal?
    /// Whether the totals the app kept on its own, before `peel` counted too, were added.
    private var tookInEarlier = false

    private struct Removal: Sendable, Equatable, Codable {
        let batch: UUID
        let bytes: SizeTotal
    }

    private static let maximumBytes = 64 * 1_024

    public init() {}

    public init(bytes: SizeTotal, items: Int, apps: Int, biggest: SizeTotal) {
        (self.bytes, self.items, self.apps, self.biggest) = (bytes, items, apps, biggest)
    }

    /// Counts what `records` moved. Apps are counted by the bundles that moved, so five apps removed together
    /// count as five, and a helper app kept under a Library folder is a leftover rather than an app.
    mutating func add(_ records: [RemovalRecord]) {
        for record in records {
            let size = SizeTotal([record.size])
            bytes = bytes.adding(size)
            items = items.addingCapped(1)
            let url = record.originalURL
            if url.pathExtension.lowercased() == "app", !url.pathComponents.contains("Library") {
                apps = apps.addingCapped(1)
            }
            let soFar = last?.batch == record.batch ? last?.bytes : nil
            let removal = Removal(batch: record.batch, bytes: soFar.map { $0.adding(size) } ?? size)
            last = removal
            if removal.bytes.known > biggest.known {
                biggest = removal.bytes
            }
        }
    }

    /// Adds, once, the totals the app kept before `peel` counted too, which share no removal with these.
    mutating func takeIn(_ other: RemovalTotals) {
        guard !tookInEarlier else { return }
        tookInEarlier = true
        bytes = bytes.adding(other.bytes)
        items = items.addingCapped(other.items)
        apps = apps.addingCapped(other.apps)
        if other.biggest.known > biggest.known {
            biggest = other.biggest
        }
    }

    static func url(beside history: URL) -> URL {
        history.deletingLastPathComponent().appending(path: "totals.json")
    }

    /// The totals kept beside `history`, or none when they cannot be read.
    public static func read(beside history: URL = RemovalHistory.defaultURL) -> RemovalTotals {
        stored(at: url(beside: history)) ?? RemovalTotals()
    }

    /// Changes the totals at `url`. A file that opens and is not the totals is kept aside under another name, and
    /// counting starts again; one that cannot be opened is left as it is. False when nothing was written.
    @discardableResult
    static func change(at url: URL, _ change: (inout RemovalTotals) -> Void) -> Bool {
        guard var totals = stored(at: url) ?? startedAgain(at: url) else { return false }
        change(&totals)
        guard let data = try? JSONEncoder().encode(totals) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// The totals at `url`: none yet when there is no file, and nil when the file cannot be read as the totals.
    private static func stored(at url: URL) -> RemovalTotals? {
        guard !url.isMissing else { return RemovalTotals() }
        guard let data = BoundedRead.data(at: url, maximum: maximumBytes) else { return nil }
        return try? JSONDecoder().decode(RemovalTotals.self, from: data)
    }

    private static func startedAgain(at url: URL) -> RemovalTotals? {
        guard BoundedRead.data(at: url, maximum: maximumBytes) != nil, DamagedFile.setAside(url) != nil else { return nil }
        return RemovalTotals()
    }
}
