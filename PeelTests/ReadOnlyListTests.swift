import AppKit
@testable import Peel
import PeelCore
import Synchronization
import SwiftUI
import Testing

@MainActor
struct ReadOnlyListTests {
    private final class Rows: RowSelection {
        var selectedURLs: Set<URL> = []
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
}
