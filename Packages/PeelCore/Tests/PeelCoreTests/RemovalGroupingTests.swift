import Foundation
@testable import PeelCore
import Testing

/// What History shows: one row per removal, newest first, and inside it the largest item first.
struct RemovalGroupingTests {
    private func record(
        _ batch: UUID,
        _ name: String,
        size: Int64?,
        at date: Date,
        source: String = "Example",
        tool: String = "applications"
    ) -> RemovalRecord {
        RemovalRecord(
            batch: batch,
            item: TrashedItem(
                originalURL: URL(filePath: "/Users/x/\(name)"),
                trashedURL: URL(filePath: "/Users/x/.Trash/\(name)"),
                date: date
            ),
            size: size,
            source: source,
            tool: tool
        )
    }

    /// A source title Peel writes itself is also stored as a key, so History can show it in the user's current
    /// language. A record saved without a key still decodes, with `source` as it was written.
    @Test func aSourceKeyIsKeptAndAnOldRecordReadsWithoutOne() throws {
        let item = TrashedItem(
            originalURL: URL(filePath: "/Users/x/a"),
            trashedURL: URL(filePath: "/Users/x/.Trash/a"),
            date: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let keyed = RemovalRecord(batch: UUID(), item: item, size: 1, source: "Duplicates", sourceKey: "tool", tool: "duplicates")
        let copy = try JSONDecoder().decode(RemovalRecord.self, from: JSONEncoder().encode(keyed))
        #expect(copy.sourceKey == "tool")
        #expect(RemovalRecord.grouped([copy]).first?.parts.first?.sourceKey == "tool")

        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(keyed)) as! [String: Any]
        old.removeValue(forKey: "sourceKey")
        let before = try JSONDecoder().decode(RemovalRecord.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(before.sourceKey == nil)
        #expect(before.source == "Duplicates")
    }

    @Test func groupsARemovalAndPutsTheNewestFirst() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let older = UUID()
        let newer = UUID()
        let records = [
            record(older, "small.bin", size: 10, at: now.addingTimeInterval(-60)),
            record(older, "big.bin", size: 100, at: now.addingTimeInterval(-50)),
            record(newer, "one.bin", size: 5, at: now, source: "Caches", tool: "space"),
        ]

        let groups = RemovalRecord.grouped(records)

        #expect(groups.map(\.id) == [newer, older])
        #expect(groups.last?.records.map(\.originalURL.lastPathComponent) == ["big.bin", "small.bin"])
        // The batch's own time is the first record written, not the last.
        #expect(groups.last?.date == now.addingTimeInterval(-60))
        #expect(groups.last?.size == SizeTotal(known: 110, isComplete: true))
        #expect(groups.first?.parts == [RemovalPart(source: "Caches", sourceKey: nil, tool: "space")])
    }

    /// A removal that moved what was selected in several tools has a part for each, in the order they moved, so
    /// History names it by all of them rather than by its largest item. A removal from one page has one part.
    @Test func aRemovalFromSeveralToolsHasAPartForEach() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let batch = UUID()
        let groups = RemovalRecord.grouped([
            record(batch, "copy.bin", size: 2_000, at: now.addingTimeInterval(2), source: "Duplicates", tool: "duplicates"),
            record(batch, "DerivedData", size: 900, at: now, source: "Xcode", tool: "developer"),
            record(batch, "node_modules", size: 300, at: now.addingTimeInterval(1), source: "Peel", tool: "projects"),
            record(batch, "ModuleCache", size: 50, at: now.addingTimeInterval(0.5), source: "Xcode", tool: "developer"),
        ])

        #expect(groups.count == 1)
        #expect(groups.first?.parts.map(\.source) == ["Xcode", "Peel", "Duplicates"])
        #expect(groups.first?.parts.map(\.tool) == ["developer", "projects", "duplicates"])

        let single = RemovalRecord.grouped([record(UUID(), "one.bin", size: 5, at: now, source: "Caches", tool: "space")])
        #expect(single.first?.parts == [RemovalPart(source: "Caches", sourceKey: nil, tool: "space")])
    }

    /// An item whose size is not known comes first, since what could not be measured is most likely the biggest,
    /// and the removal's total says it is only the least the size can be.
    @Test func anItemNobodyMeasuredComesFirst() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let batch = UUID()
        let groups = RemovalRecord.grouped([
            record(batch, "big.bin", size: 100, at: now),
            record(batch, "unknown.bin", size: nil, at: now),
            record(batch, "small.bin", size: 10, at: now),
        ])

        #expect(groups.first?.records.map(\.originalURL.lastPathComponent) == ["unknown.bin", "big.bin", "small.bin"])
        #expect(groups.first?.size == SizeTotal(known: 110, isComplete: false))
    }

    @Test func itemsOfTheSameSizeAreListedByPath() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let batch = UUID()
        let groups = RemovalRecord.grouped([
            record(batch, "b.bin", size: 10, at: now),
            record(batch, "d.bin", size: nil, at: now),
            record(batch, "a.bin", size: 10, at: now),
            record(batch, "c.bin", size: nil, at: now),
        ])

        #expect(groups.first?.records.map(\.originalURL.lastPathComponent) == ["c.bin", "d.bin", "a.bin", "b.bin"])
    }

    /// Two removals made at the same moment must keep their order from one render to the next.
    @Test func keepsTheOrderOfTwoRemovalsAtTheSameMoment() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = UUID()
        let second = UUID()
        let records = [record(first, "a.bin", size: 1, at: now), record(second, "b.bin", size: 1, at: now)]

        let once = RemovalRecord.grouped(records).map(\.id)
        let again = RemovalRecord.grouped(records.reversed()).map(\.id)

        #expect(once == again)
    }

    @Test func saysNothingAboutAnEmptyLog() {
        #expect(RemovalRecord.grouped([]).isEmpty)
    }
}
