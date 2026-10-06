import Foundation
@testable import PeelCore
import Testing

struct AppListFilterTests {
    private let app = InstalledApp(
        url: URL(filePath: "/Applications/Studio.app"), bundleIdentifier: "org.example.studio", name: "Studio"
    )

    private func keeps(_ filter: AppListFilter, source: AppSource = .direct, developer: String? = "Example Inc.",
                       isUnused: Bool = false) -> Bool {
        filter.keeps(app, source: source, developer: developer, isUnused: isUnused)
    }

    @Test func searchFindsAnAppByItsNameItsIdentifierOrItsDeveloper() {
        #expect(keeps(AppListFilter(text: "stud")))
        #expect(keeps(AppListFilter(text: "example.studio")))
        #expect(keeps(AppListFilter(text: "example inc")))
        #expect(!keeps(AppListFilter(text: "editor")))
        #expect(!keeps(AppListFilter(text: "example inc"), developer: nil))
    }

    @Test func eachFilterOnNarrowsTheList() {
        #expect(keeps(AppListFilter()))
        #expect(keeps(AppListFilter(sources: [.appStore, .direct])))
        #expect(!keeps(AppListFilter(sources: [.homebrew])))
        #expect(keeps(AppListFilter(developer: "Example Inc.")))
        #expect(!keeps(AppListFilter(developer: "Someone Else")))
        #expect(!keeps(AppListFilter(onlyUnused: true)))
        #expect(keeps(AppListFilter(onlyUnused: true), isUnused: true))
    }

    @Test func anAppComesFromTheAppStoreSetappHomebrewOrADownload() {
        #expect(AppSource.of(app, installedByHomebrew: false) == .direct)
        #expect(AppSource.of(app, installedByHomebrew: true) == .homebrew)
    }
}
