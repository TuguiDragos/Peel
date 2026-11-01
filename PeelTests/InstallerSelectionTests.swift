import Foundation
@testable import Peel
@testable import PeelCore
import Synchronization
import Testing

@MainActor
struct InstallerSelectionTests {
    private func item(_ name: String, kind: InstallerItem.Kind = .appInstaller, size: Int64 = 10) -> InstallerItem {
        InstallerItem(
            url: URL(filePath: "/Users/me/Downloads/\(name)"), kind: kind, name: name, size: size, date: nil,
            installedApp: nil, isReadOnly: false, notes: []
        )
    }

    @Test func scansAgainOnlyOnceItsLastScanIsOld() async {
        let scans = Mutex(0)
        let library = InstallerLibrary { _, _ in
            scans.withLock { $0 += 1 }
            return InstallerScan(items: [], unreadableLocations: [])
        }

        await library.refreshUnlessScanned(within: .seconds(3_600), installedApps: [])
        await library.refreshUnlessScanned(within: .seconds(3_600), installedApps: [])
        #expect(scans.withLock { $0 } == 1)
        await library.refreshUnlessScanned(within: .zero, installedApps: [])
        #expect(scans.withLock { $0 } == 2)
    }

    @Test func aSearchNarrowsThePageUnlessItNamesThePage() async {
        let items = [item("Firefox.dmg"), item("Chrome.dmg"), item("Install macOS", kind: .macOSInstaller)]
        let library = InstallerLibrary { _, _ in InstallerScan(items: items, unreadableLocations: []) }
        await library.refresh(installedApps: [])

        #expect(library.shownItems(in: .appInstaller).count == 2)
        library.searchText = "firefox"
        #expect(library.shownItems(in: .appInstaller).map(\.name) == ["Firefox.dmg"])
        library.searchText = "app installers"
        #expect(library.shownItems(in: .appInstaller).count == 2)
        #expect(library.shownItems(in: .macOSInstaller).isEmpty)
    }

    @Test func anUpdateChosenByHandWaitsForItsAppToQuit() async {
        var running = item("org.example.running", kind: .updateDownload)
        running.updatesApp = InstallerItem.UpdatedApp(identifier: "com.apple.finder", name: "Finder")
        var closed = item("org.example.closed", kind: .updateDownload)
        closed.updatesApp = InstallerItem.UpdatedApp(identifier: "org.example.closed", name: "Closed")
        let items = [running, closed]
        let library = InstallerLibrary { _, _ in InstallerScan(items: items, unreadableLocations: []) }
        await library.refresh(installedApps: [])
        let page = InstallerItem.Kind.updateDownload.page

        library.selectedURLs = [closed.url]
        let free = library.carriedParts.first { $0.page == page }
        #expect(free.flatMap(library.appToQuit(for:)) == nil)
        library.selectedURLs = [closed.url, running.url]
        let kept = library.carriedParts.first { $0.page == page }
        #expect(kept.flatMap(library.appToQuit(for:)) == "Finder")
    }

    @Test func takesWhatWaitsForTheHelperOutOfTheSelection() {
        let macOS = URL(filePath: "/Applications/Install macOS Tahoe.app", directoryHint: .isDirectory)
        let image = URL(filePath: "/Users/me/Downloads/Tool.dmg")
        var installer = InstallerItem(
            url: macOS, kind: .macOSInstaller, name: "Install macOS Tahoe", size: 10, date: nil, installedApp: nil,
            isReadOnly: false, notes: []
        )
        installer.requiresPrivileges = true
        let download = InstallerItem(
            url: image, kind: .appInstaller, name: "Tool.dmg", size: 10, date: nil, installedApp: nil,
            isReadOnly: false, notes: []
        )

        let items = [installer, download]
        #expect(InstallerLibrary.selection([macOS, image], in: items, canUseHelper: false) == [image])
        #expect(InstallerLibrary.selection([macOS, image], in: items, canUseHelper: true) == [macOS, image])
    }
}
