import Foundation
@testable import PeelCore
import Testing

/// What moves when Move to Trash is pressed on any page of the storage tools: what is selected on every page the
/// person has seen, one part to a page, in one batch.
struct CarriedSelectionTests {
    private typealias Page = CarriedSelection.Page
    private typealias Part = CarriedSelection.Part

    private let tools = ["orphans", "developer", "projects", "installers", "duplicates", "space", "fileSearch"]

    private func part(_ tool: String, _ scope: String, _ sizes: [String: Int64?], source: String? = nil) -> Part {
        Part(
            page: Page(tool: tool, scope: scope),
            title: scope,
            source: source ?? scope,
            sourceKey: nil,
            sizes: Dictionary(uniqueKeysWithValues: sizes.map { (URL(filePath: "/Users/x/\($0.key)"), $0.value) })
        )
    }

    /// A tool can select for the person on pages they never opened, so only a page they have seen is carried.
    @Test func aPageNeverSeenIsNotCarried() {
        var selection = CarriedSelection()
        selection.saw(Page(tool: "developer", scope: "Xcode"))

        let parts = selection.parts(from: [
            part("developer", "Xcode", ["DerivedData": 900]),
            part("developer", "npm", ["_cacache": 300]),
        ], order: tools)

        #expect(parts.map(\.page.scope) == ["Xcode"])
    }

    /// The parts move in the sidebar's order of the tools, and within a tool in the order its pages were seen.
    @Test func partsFollowTheToolsThenTheOrderSeen() {
        var selection = CarriedSelection()
        for page in [Page(tool: "projects", scope: "Peel"), Page(tool: "developer", scope: "npm"), Page(tool: "developer", scope: "Xcode")] {
            selection.saw(page)
        }
        selection.saw(Page(tool: "developer", scope: "npm"))

        let parts = selection.parts(from: [
            part("developer", "Xcode", ["DerivedData": 900]),
            part("projects", "Peel", ["node_modules": 300]),
            part("developer", "npm", ["_cacache": 300]),
        ], order: tools)

        #expect(parts.map(\.page) == [
            Page(tool: "developer", scope: "npm"),
            Page(tool: "developer", scope: "Xcode"),
            Page(tool: "projects", scope: "Peel"),
        ])
    }

    /// A page with nothing selected carries nothing.
    @Test func aPageWithNothingSelectedIsLeftOut() {
        var selection = CarriedSelection()
        selection.saw(Page(tool: "duplicates", scope: ""))

        #expect(selection.parts(from: [part("duplicates", "", [:])], order: tools).isEmpty)
    }

    /// The whole is every part's items together, and it says "Over" when one of their sizes is not known.
    @Test func theWholeCountsEveryPart() {
        let parts = [
            part("developer", "Xcode", ["DerivedData": 900, "ModuleCache": 100]),
            part("developer", "npm", ["_cacache": nil]),
            part("space", "logs", ["a.log": 50]),
        ]

        #expect(parts.itemCount == 4)
        #expect(parts.total == SizeTotal(known: 1_050, isComplete: false))
        #expect(parts.tools == ["developer", "space"])
    }

    /// Every part is tried in turn, whatever came of the ones before: a part whose tool kept it (an app it waits
    /// for was opened) stays whole, and the others still move.
    @Test func aPartKeptByItsToolDoesNotStopTheOthers() async {
        let parts = [
            part("developer", "Xcode", ["DerivedData": 900], source: "Xcode"),
            part("projects", "Peel", ["node_modules": 300], source: "Peel"),
        ]
        var tried: [String] = []
        let pass = await CarriedSelection.pass(parts) { part in
            tried.append(part.page.scope)
            guard part.page.tool != "developer" else { return nil }
            return TrashResult(
                trashed: part.sizes.keys.map { TrashedItem(originalURL: $0, trashedURL: $0, date: .now) }
            )
        }

        #expect(tried == ["Xcode", "Peel"])
        #expect(pass.kept.map(\.page.scope) == ["Xcode"])
        #expect(pass.moved.map(\.part.page.scope) == ["Peel"])
    }

    /// What a pass did is told once, whichever parts it came from: every item the parts moved, and every one
    /// their tools refused.
    @Test func aPassTellsWhatEveryPartMovedAndRefused() async {
        let parts = [
            part("developer", "Xcode", ["DerivedData": 900, "ModuleCache": 100]),
            part("space", "caches", ["com.gone.app": 50]),
        ]
        let pass = await CarriedSelection.pass(parts) { part in
            var result = TrashResult()
            for url in part.sizes.keys {
                if url.lastPathComponent == "ModuleCache" {
                    result.failures.append(TrashFailure(url: url, reason: .guarded(.protectedLocation)))
                } else {
                    result.trashed.append(TrashedItem(originalURL: url, trashedURL: url, date: .now))
                }
            }
            return result
        }

        #expect(Set(pass.result.trashed.map(\.originalURL.lastPathComponent)) == ["DerivedData", "com.gone.app"])
        #expect(pass.result.failures.map(\.url.lastPathComponent) == ["ModuleCache"])
    }

    /// What a pass moved is one History batch, each record under its own part's source and tool, with the size
    /// its page measured, and none for an item whose size was not known.
    @Test func whatMovedIsOneBatchWithEachPartsName() async {
        let parts = [
            part("developer", "Xcode", ["DerivedData": 900], source: "Xcode"),
            part("duplicates", "", ["copy.bin": nil], source: "Duplicates"),
        ]
        let batch = UUID()
        var records: [RemovalRecord] = []
        _ = await CarriedSelection.pass(parts) { part in
            let result = TrashResult(
                trashed: part.sizes.keys.map { TrashedItem(originalURL: $0, trashedURL: $0, date: .now) }
            )
            records += part.removalPart.records(of: result, sizes: part.measuredSizes, batch: batch)
            return result
        }

        #expect(records.allSatisfy { $0.batch == batch })
        #expect(Set(records.map(\.tool)) == ["developer", "duplicates"])
        #expect(records.first { $0.tool == "developer" }?.source == "Xcode")
        #expect(records.first { $0.tool == "developer" }?.size == 900)
        #expect(records.first { $0.tool == "duplicates" }?.size == nil)
        #expect(RemovalRecord.grouped(records).first?.parts.map(\.source) == ["Xcode", "Duplicates"])
    }
}
