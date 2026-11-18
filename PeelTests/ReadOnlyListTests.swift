import AppKit
@testable import Peel
@testable import PeelCore
import Synchronization
import SwiftUI
import Testing

@MainActor
struct ReadOnlyListTests {
    private final class Rows: RowSelection {
        var selectedURLs: Set<URL> = []
    }

    private final class Carrying: CarriesSelection {
        var isRemoving = false
        var carriedParts: [CarriedSelection.Part]
        init(_ parts: [CarriedSelection.Part]) { carriedParts = parts }
        func move(_ part: CarriedSelection.Part, apps: AppLibrary) async -> TrashResult? { nil }
        func lists(_ moved: MovedItems) -> Bool { false }
        func refresh(after parts: [CarriedSelection.Part], moved: MovedItems, apps: AppLibrary) async {}
        func deselect(_ part: CarriedSelection.Part) {}
    }

    private func checkboxes(in view: NSView) -> Int {
        view.subviews.reduce(view is RowCheckboxButton ? 1 : 0) { $0 + checkboxes(in: $1) }
    }

    private func appWithASystemExtension(in root: URL) throws -> (app: InstalledApp, extensionIsIn: String) {
        let url = root.appending(path: "Example.app", directoryHint: .isDirectory)
        let helper = url.appending(path: "Contents/MacOS/Helper.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: helper, withIntermediateDirectories: true)
        let app = InstalledApp(url: url, bundleIdentifier: "org.example.app", name: "Example", teamIdentifier: "ABCDE12345")
        return (app, helper.path(percentEncoded: false))
    }

    nonisolated private static func guardExtension(
        _ election: AppExtension.Election, in helper: String
    ) -> AppExtension {
        AppExtension(
            identifier: "org.example.guard", name: "Example Guard", kind: .systemExtension, point: nil, owner: nil,
            url: nil, election: election, teamIdentifier: "ABCDE12345", reportedState: nil, installedFor: helper
        )
    }

    @Test func aRowOfAListToReadHasNoCheckbox() {
        func checkboxes(readOnly: Bool) -> Int {
            let row = RemovalRow(
                url: URL(filePath: "/org.example/file.txt"), icon: .symbol("doc"), detail: "Found by its name",
                kind: "Application", size: 1_000, isLeftAlone: true, isReadOnly: readOnly, selection: Rows(),
                isSelected: false
            )
            let host = NSHostingView(rootView: row.frame(width: 600))
            host.layoutSubtreeIfNeeded()
            return self.checkboxes(in: host)
        }

        #expect(checkboxes(readOnly: false) == 1)
        #expect(checkboxes(readOnly: true) == 0)
    }

    @Test func anAppsPageIsAListToReadUntilSomethingCanBeSelected() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ReadOnlyListTests-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let (app, helper) = try appWithASystemExtension(in: root)
        let election = Mutex(AppExtension.Election.on)
        let plan = RemovalPlan(app: app, jobsKeptRunning: { _ in [] }) {
            [Self.guardExtension(election.withLock { $0 }, in: helper)]
        }

        #expect(!AppDetailView.isOnlyToRead(plan), "a page still scanning was taken for a list to read")
        await plan.refresh(installedApps: [app], canUseHelper: false)
        #expect(AppDetailView.isOnlyToRead(plan))

        election.withLock { $0 = .off }
        await plan.followSystemExtensions()

        #expect(!AppDetailView.isOnlyToRead(plan))
    }

    @Test func severalAppsPageIsAListToReadUntilSomethingCanBeSelected() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ReadOnlyListTests-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let (app, helper) = try appWithASystemExtension(in: root)
        let election = Mutex(AppExtension.Election.on)
        let plan = BulkRemovalPlan(apps: [app]) {
            [Self.guardExtension(election.withLock { $0 }, in: helper)]
        }

        #expect(!MultipleAppsView.isOnlyToRead(plan), "a page still scanning was taken for a list to read")
        await plan.refresh(installedApps: [app], canUseHelper: false)
        #expect(MultipleAppsView.isOnlyToRead(plan))

        election.withLock { $0 = .off }
        await plan.followSystemExtensions()

        #expect(!MultipleAppsView.isOnlyToRead(plan))
    }

    @Test func anOrphanGroupIsAListToReadUntilTheHelperCanMoveIt() {
        var locked = OrphanItem(
            url: URL(filePath: "/Library/Application Support/org.example.gone"), kind: .applicationSupport, size: 10,
            modificationDate: nil, requiresPrivileges: true
        )
        let group = OrphanGroup(identifier: "org.example.gone", items: [locked])
        locked.heldBack = .holdsDocuments
        let documents = OrphanGroup(identifier: "org.example.gone", items: [locked])

        #expect(OrphanDetailView.isOnlyToRead(group, canUseHelper: false))
        #expect(!OrphanDetailView.isOnlyToRead(group, canUseHelper: true))
        #expect(OrphanDetailView.isOnlyToRead(documents, canUseHelper: true))
    }

    @Test func aReceiptIsAListToReadUntilTheHelperCanMoveWhatItInstalled() {
        let receipt = PackageReceipt(
            identifier: "org.example.pkg", version: nil, installDate: nil, volume: URL(filePath: "/"),
            items: [PackageReceipt.Item(url: URL(filePath: "/Library/LaunchDaemons/org.example.helper.plist"), size: 10, requiresPrivileges: true)]
        )
        let empty = PackageReceipt(
            identifier: "org.example.pkg", version: nil, installDate: nil, volume: URL(filePath: "/"), items: []
        )

        #expect(PackageDetailView.isOnlyToRead(receipt, canUseHelper: false))
        #expect(!PackageDetailView.isOnlyToRead(receipt, canUseHelper: true))
        #expect(!PackageDetailView.isOnlyToRead(empty, canUseHelper: false))
    }

    @Test func aCarriedBarStaysOnAListToReadOnlyWhileAnotherPageHoldsASelection() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PeelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let made = try MadeUpDefaults()
        defer { made.forget() }
        let npm = Tool.developer.page("npm")
        let holding = Carrying([CarriedSelection.Part(
            page: npm, title: "npm", source: "npm", sourceKey: nil, sizes: [URL(filePath: "/Users/me/.npm"): 4_096]
        )])
        let carrier = SelectionCarrier(
            tools: [.developer: holding],
            apps: AppLibrary(
                defaults: made.defaults, releaseNotesStore: ReleaseNotesStore(url: folder.appending(path: "notes.json"))
            ),
            history: RemovalHistoryStore(
                log: RemovalLog(url: folder.appending(path: "removals.json")),
                refusals: RefusalLog(url: folder.appending(path: "refusals.json")),
                knowsTheExclusions: { true }
            ),
            outcome: RemovalOutcome()
        )
        let group = Tool.orphans.page("org.example.gone")

        #expect(!carrier.movesSomething(from: group), "a page never seen carried its selection")
        carrier.saw(npm)
        #expect(carrier.movesSomething(from: group))
        holding.carriedParts = []
        #expect(!carrier.movesSomething(from: group))
    }

    @Test func aSpaceAreaIsAListToReadUntilTheHelperCanMoveWhatIsInside() {
        let caches = URL(filePath: "/Library/Caches/org.example.app", directoryHint: .isDirectory)
        var plan = SpaceRemoval.Plan(removable: [caches], inUse: [], leftToDeveloper: [], sizes: [caches: 10])
        plan.needsTheHelper = [caches]
        var heldBack = plan
        heldBack.heldBack = [caches: .holdsDocuments]
        let empty = SpaceRemoval.Plan(removable: [], inUse: [], leftToDeveloper: [], sizes: [:])

        #expect(SpaceDetailView.isOnlyToRead(plan, canUseHelper: false))
        #expect(!SpaceDetailView.offersItsBar(plan, canUseHelper: false))
        #expect(!SpaceDetailView.isOnlyToRead(plan, canUseHelper: true))
        #expect(SpaceDetailView.offersItsBar(plan, canUseHelper: true))
        #expect(SpaceDetailView.isOnlyToRead(heldBack, canUseHelper: true))
        #expect(!SpaceDetailView.isOnlyToRead(empty, canUseHelper: true))
        #expect(!SpaceDetailView.offersItsBar(empty, canUseHelper: true))
        #expect(SpaceDetailView.offersItsBar(nil, canUseHelper: false), "the bar left while the plan was being made")
    }

    @Test func anInstallersKindIsAListToReadUntilTheHelperCanMoveIt() {
        var installer = InstallerItem(
            url: URL(filePath: "/Applications/Install macOS.app"), kind: .macOSInstaller, name: "Install macOS",
            size: 10, date: nil, installedApp: nil, isReadOnly: false, notes: []
        )
        installer.requiresPrivileges = true

        #expect(InstallerDetailView.isOnlyToRead([installer], of: .macOSInstaller, canUseHelper: false))
        #expect(!InstallerDetailView.isOnlyToRead([installer], of: .macOSInstaller, canUseHelper: true))
        #expect(!InstallerDetailView.isOnlyToRead([], of: .macOSInstaller, canUseHelper: false))
    }
}
