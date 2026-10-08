import Foundation
@testable import PeelCore
import Testing

struct SelectableRowsTests {
    private let repository = URL(filePath: "/tmp/org.example.Work")
    private let cache = URL(filePath: "/tmp/org.example.Cache")
    private let log = URL(filePath: "/tmp/org.example.Log")
    private let elsewhere = URL(filePath: "/tmp/org.example.Elsewhere")

    /// A row still selected that a click can no longer select goes with Deselect All too: otherwise it would stay
    /// selected unseen and move with the next small file.
    @Test func deselectAllTakesOutARowSelectedByHand() {
        let list = SelectableRows(
            rows: [repository, cache, log], selectable: [cache, log], recommended: [cache, log]
        )
        let selection: Set = [repository, cache, log, elsewhere]

        #expect(list.isAllSelected(in: selection))
        #expect(list.deselectingAll(in: selection) == [elsewhere])
    }

    @Test func selectAllAddsWhatAClickCanSelect() {
        let list = SelectableRows(
            rows: [repository, cache, log], selectable: [cache, log], recommended: [cache]
        )

        #expect(list.selectingAll(in: [elsewhere]) == [cache, log, elsewhere])
        #expect(list.isAllSelected(in: [cache, log]))
    }

    /// Select All selects every row a click can select, what Peel holds back included, and asks first about each
    /// one Peel doesn't recommend: whoever wants everything gone can have it, once they have read the question.
    @Test func selectAllTakesWhatEveryPageHoldsBackAfterAsking() {
        func orphan(_ name: String, heldBack: HoldBack?) -> OrphanItem {
            var item = OrphanItem(
                url: URL(filePath: "/tmp/\(name)"), kind: .caches, size: 10, modificationDate: nil,
                requiresPrivileges: false
            )
            item.heldBack = heldBack
            return item
        }
        let messages = orphan("org.example.Messages", heldBack: .holdsMessageHistory)
        let orphans = OrphanGroup(identifier: "org.example", items: [messages]).selectableRows(canUseHelper: true)
        #expect(orphans.selectingAll(in: []) == [messages.url])
        #expect(orphans.notRecommendedAdded(by: []) == [messages.url])

        let (cache, system) = (URL(filePath: "/tmp/org.example.Cache"), URL(filePath: "/tmp/com.apple.Cache"))
        let space = SpaceRemoval.Plan(
            removable: [cache, system], inUse: [], leftToDeveloper: [], sizes: [cache: 1, system: 1],
            heldBack: [system: .keptByMacOS], needsTheHelper: []
        ).selectableRows(canUseHelper: true)
        #expect(space.selectingAll(in: []) == [cache, system])
        #expect(space.notRecommendedAdded(by: []) == [system])

        let project = URL(filePath: "/tmp/org.example.Project")
        let build = ProjectArtifact(
            url: project.appending(path: "build"), project: project, name: "build", tool: "Xcode", size: 10,
            lastActivity: .now.addingTimeInterval(-ProjectArtifacts.recentlyActive * 2),
            hasGenericName: true, isEnvironment: false
        )
        #expect([build].selectableRows.selectingAll(in: []) == [build.url])

        let archive = DeveloperEnvironment.Location(
            url: URL(filePath: "/tmp/org.example.Archive"), kind: .archives, size: 10, source: "https://example.com"
        )
        let tool = DeveloperEnvironment(
            id: "org.example", name: "Example", systemImage: "hammer", appBundleIdentifiers: [], locations: [archive]
        )
        #expect(tool.selectableRows.selectingAll(in: []) == [archive.url])
        #expect(tool.selectableRows.isAllSelected(in: [archive.url]))
    }

    @Test func selectRecommendedTakesOutWhatPeelDoesNotRecommend() {
        let list = SelectableRows(
            rows: [repository, cache, log], selectable: [repository, cache, log], recommended: [cache]
        )
        let selection: Set = [repository, log, elsewhere]

        #expect(!list.isRecommendedSelected(in: selection))
        #expect(list.selectingRecommended(in: selection) == [cache, elsewhere])
        #expect(list.isRecommendedSelected(in: [cache, elsewhere]))
        #expect(!list.isRecommendedSelected(in: [cache, log]))
    }

    @Test func selectAllAsksOnlyAboutWhatPeelDoesNotRecommend() {
        let list = SelectableRows(
            rows: [repository, cache, log], selectable: [repository, cache, log], recommended: [cache]
        )

        #expect(list.notRecommendedAdded(by: []) == [repository, log])
        #expect(list.notRecommendedAdded(by: [repository]) == [log])
        #expect(list.notRecommendedAdded(by: [repository, log]).isEmpty)
        let everything = SelectableRows(
            rows: [cache, log], selectable: [cache, log], recommended: [cache, log]
        )
        #expect(everything.notRecommendedAdded(by: []).isEmpty)
    }

    @Test func peelNeverRecommendsWhatAClickCannotSelect() {
        let list = SelectableRows(
            rows: [repository, cache], selectable: [cache], recommended: [repository, cache]
        )

        #expect(list.recommended == [cache])
        #expect(list.selectingRecommended(in: []) == [cache])
    }

    @Test func deselectAllLeavesOtherListsAlone() {
        let list = SelectableRows(
            rows: [cache, log], selectable: [cache, log], recommended: [cache]
        )

        #expect(list.isNoneSelected(in: [elsewhere]))
        #expect(!list.isNoneSelected(in: [log, elsewhere]))
        #expect(list.deselectingAll(in: [log, elsewhere]) == [elsewhere])
        let locked = SelectableRows(
            rows: [repository, cache], selectable: [cache], recommended: [cache]
        )
        #expect(!locked.isNoneSelected(in: [repository]))
    }

    @Test func everyPageSelectsAsOneList() {
        let first = SelectableRows(
            rows: [repository, cache], selectable: [repository, cache], recommended: [cache]
        )
        let second = SelectableRows(
            rows: [repository, log], selectable: [repository, log], recommended: [log]
        )
        let locked = SelectableRows(rows: [elsewhere], selectable: [], recommended: [])
        let pages = SelectablePages([("first", first), ("second", second), ("locked", locked)])

        #expect(pages.rows.rows == [repository, cache, log, elsewhere])
        #expect(pages.rows.notRecommendedAdded(by: []) == [repository])
        #expect(pages.rows.selectingRecommended(in: [repository, elsewhere]) == [cache, log])
        #expect(pages.selectablePageCount == 2)
    }

    @Test func aPageCountsOnceSomethingOnItIsSelected() {
        let first = SelectableRows(
            rows: [repository, cache], selectable: [repository, cache], recommended: [cache]
        )
        let second = SelectableRows(
            rows: [repository, log], selectable: [repository, log], recommended: [log]
        )
        let pages = SelectablePages([("first", first), ("second", second)])

        #expect(pages.pages(selectedIn: [log, elsewhere]) == ["second"])
        #expect(pages.pages(selectedIn: [repository]) == ["first", "second"])
        #expect(pages.pages(selectedIn: [elsewhere]).isEmpty)
    }

    @Test func aRowOnAPageNotSeenYetCountsAsNotSelected() {
        let first = SelectableRows(rows: [cache], selectable: [cache], recommended: [cache])
        let second = SelectableRows(
            rows: [log, repository], selectable: [log, repository], recommended: [log]
        )
        let shared = SelectableRows(rows: [repository], selectable: [repository], recommended: [])
        let pages = SelectablePages([("first", first), ("second", second), ("shared", shared)])
        let preselected: Set = [cache, log, repository, elsewhere]

        let counted = pages.counted(preselected, seen: { $0 != "second" })
        #expect(counted == [cache, repository, elsewhere])
        #expect(!pages.rows.isRecommendedSelected(in: counted))
        #expect(pages.counted(preselected, seen: { _ in true }) == preselected)
    }

    @Test func anOrphanGroupLeavesALockedRowToTheHelper() {
        func orphan(_ name: String, heldBack: HoldBack? = nil, requiresPrivileges: Bool = false) -> OrphanItem {
            var item = OrphanItem(
                url: URL(filePath: "/tmp/\(name)"), kind: .caches, size: 10, modificationDate: nil,
                requiresPrivileges: requiresPrivileges
            )
            item.heldBack = heldBack
            return item
        }
        let plain = orphan("org.example.Plain")
        let unmeasured = orphan("org.example.Unmeasured", heldBack: .notMeasured)
        let library = orphan("org.example.Library", heldBack: .holdsALibrary)
        let system = orphan("org.example.System", requiresPrivileges: true)
        let refused = orphan("org.example.Refused", heldBack: .beyondTheHelper, requiresPrivileges: true)
        let group = OrphanGroup(identifier: "org.example", items: [plain, unmeasured, library, system, refused])

        let helped = group.selectableRows(canUseHelper: true)
        #expect(helped.rows == group.items.map(\.url))
        #expect(helped.selectable == [plain.url, unmeasured.url, system.url])
        #expect(helped.recommended == [plain.url, system.url])
        let alone = group.selectableRows(canUseHelper: false)
        #expect(alone.rows == group.items.map(\.url))
        #expect(alone.selectable == [plain.url, unmeasured.url])
        #expect(alone.recommended == [plain.url])
        #expect(system.isLocked(canUseHelper: false) && !system.isLocked(canUseHelper: true))
        #expect(!refused.isLocked(canUseHelper: false))
    }

    @Test func anOrphanGroupPeelIsUnsureAboutRecommendsNothing() {
        let cache = OrphanItem(
            url: URL(filePath: "/tmp/org.example.Running"), kind: .caches, size: 10, modificationDate: nil,
            requiresPrivileges: false
        )
        var group = OrphanGroup(identifier: "org.example.Running", items: [cache])
        group.confidence = OrphanConfidence(level: .unsure, reasons: [.running])

        #expect(group.selectableRows(canUseHelper: true).selectable == [cache.url])
        #expect(group.selectableRows(canUseHelper: true).recommended.isEmpty)
    }

    @Test func aDeveloperToolRecommendsWhatItSelectsForThePerson() {
        func location(
            _ name: String, _ kind: DeveloperEnvironment.ContentKind, size: Int64? = 10
        ) -> DeveloperEnvironment.Location {
            DeveloperEnvironment.Location(
                url: URL(filePath: "/tmp/\(name)"), kind: kind, size: size, source: "https://example.com"
            )
        }
        let cache = location("org.example.Cache", .cache)
        let unmeasured = location("org.example.Unmeasured", .cache, size: nil)
        let archive = location("org.example.Archive", .archives)
        let tool = DeveloperEnvironment(
            id: "org.example", name: "Example", systemImage: "hammer", appBundleIdentifiers: [],
            locations: [cache, unmeasured, archive]
        )

        #expect(tool.selectableRows.selectable == [cache.url, unmeasured.url, archive.url])
        #expect(tool.selectableRows.recommended == [cache.url])
    }

    @Test func aProjectRecommendsWhatItSelectsForThePerson() {
        let project = URL(filePath: "/tmp/org.example.Project")
        func artifact(_ name: String, generic: Bool) -> ProjectArtifact {
            ProjectArtifact(
                url: project.appending(path: name), project: project, name: name, tool: "Xcode", size: 10,
                lastActivity: .now.addingTimeInterval(-ProjectArtifacts.recentlyActive * 2),
                hasGenericName: generic, isEnvironment: false
            )
        }
        let derived = artifact("DerivedData", generic: false)
        let build = artifact("build", generic: true)

        #expect([derived, build].selectableRows.selectable == [derived.url, build.url])
        #expect([derived, build].selectableRows.recommended == [derived.url])
    }

    @Test func anInstallerKindNeverSelectsABackupOrALockedRow() {
        func installer(
            _ name: String, heldBack: HoldBack? = nil, privileged: Bool = false, readOnly: Bool = false
        ) -> InstallerItem {
            InstallerItem(
                url: URL(filePath: "/tmp/\(name)"), kind: .appInstaller, name: name, size: 10, date: nil,
                installedApp: nil, isReadOnly: readOnly, notes: [], requiresPrivileges: privileged, heldBack: heldBack
            )
        }
        let image = installer("org.example.dmg")
        let backup = installer("org.example.Backup", readOnly: true)
        let unmeasured = installer("org.example.pkg", heldBack: .notMeasured)
        let refused = installer("org.example.Refused", heldBack: .beyondTheHelper, privileged: true)
        let system = installer("org.example.System", privileged: true)
        let items = [image, backup, unmeasured, refused, system]

        let helped = items.selectableRows(canUseHelper: true)
        #expect(helped.selectable == [image.url, unmeasured.url, system.url])
        #expect(helped.recommended == [image.url, system.url])
        let alone = items.selectableRows(canUseHelper: false)
        #expect(alone.rows == items.map(\.url))
        #expect(alone.selectable == [image.url, unmeasured.url])
        #expect(alone.recommended == [image.url])
        #expect(system.isLocked(canUseHelper: false) && !refused.isLocked(canUseHelper: false))
    }

    @Test func aSpaceAreaRecommendsItsOwnSuggestion() {
        let (cache, unmeasured, documents, system, refused, unknown) = (
            URL(filePath: "/tmp/org.example.Cache"), URL(filePath: "/tmp/org.example.Unmeasured"),
            URL(filePath: "/tmp/org.example.Documents"), URL(filePath: "/tmp/org.example.System"),
            URL(filePath: "/tmp/org.example.Refused"), URL(filePath: "/tmp/org.example.Unknown")
        )
        let plan = SpaceRemoval.Plan(
            removable: [cache, unmeasured, documents, system, refused, unknown],
            inUse: [],
            leftToDeveloper: [],
            sizes: [cache: 1, documents: 2, system: 3, refused: 4],
            heldBack: [unmeasured: .notMeasured, documents: .holdsDocuments, refused: .beyondTheHelper],
            needsTheHelper: [system, refused]
        )

        let helped = plan.selectableRows(canUseHelper: true)
        #expect(helped.selectable == [cache, unmeasured, system, unknown])
        #expect(helped.recommended == [cache, system])
        let alone = plan.selectableRows(canUseHelper: false)
        #expect(alone.rows == plan.removable)
        #expect(alone.selectable == [cache, unmeasured, unknown])
        #expect(alone.recommended == [cache])
        #expect(plan.isLocked(system, canUseHelper: false) && !plan.isLocked(refused, canUseHelper: false))
    }
}
