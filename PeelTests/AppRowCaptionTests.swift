import Foundation
@testable import Peel
import PeelCore
import Testing

struct AppRowCaptionTests {
    private func app(
        lastUsed: Date? = nil, version: String? = nil, isUseRecorded: Bool = true, added: Date? = nil
    ) -> InstalledApp {
        InstalledApp(
            url: URL(filePath: "/Applications/Tide.app"), bundleIdentifier: "org.example.tide", name: "Tide",
            version: version, lastUsedDate: lastUsed, isUseRecorded: isUseRecorded, dateAdded: added
        )
    }

    @Test func saysNothingWhenItKnowsNothing() {
        #expect(AppRowCaption(app: app(isUseRecorded: false), sort: .lastOpened) == nil)
        #expect(AppRowCaption(app: app(isUseRecorded: false), sort: .name) == nil)
        #expect(AppRowCaption(app: app(), sort: .dateAdded) == nil)
    }

    @Test func saysWhatItKnows() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(AppRowCaption(app: app(lastUsed: date, version: "2.0"), sort: .size) == .opened(date))
        #expect(AppRowCaption(app: app(version: "2.0"), sort: .lastOpened) == .version("2.0"))
        #expect(AppRowCaption(app: app(), sort: .name) == .neverOpened)
        #expect(AppRowCaption(app: app(version: "2.0", added: date), sort: .dateAdded) == .added(date))
        #expect(AppRowCaption(app: app(version: "2.0"), sort: .dateAdded) == .version("2.0"))
    }
}
