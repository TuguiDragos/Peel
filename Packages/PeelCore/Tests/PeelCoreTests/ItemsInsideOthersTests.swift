import Foundation
@testable import PeelCore
import Testing

struct ItemsInsideOthersTests {
    private let steam = URL(filePath: "/Users/me/Library/Application Support/Steam", directoryHint: .isDirectory)
    private var bundle: URL { steam.appending(path: "Steam.AppBundle", directoryHint: .isDirectory) }

    @Test func namesTheListedFolderAnItemSitsIn() {
        let caches = URL(filePath: "/Users/me/Library/Caches/Steam")
        let inside = ItemsInsideOthers([bundle, caches, steam])
        #expect(inside.holder(of: bundle) == steam)
        #expect(inside.holder(of: steam) == nil)
        #expect(inside.holder(of: caches) == nil)
    }

    @Test func namesTheNearestOfSeveralFolders() {
        let app = bundle.appending(path: "Steam", directoryHint: .isDirectory)
        let inside = ItemsInsideOthers([steam, app, bundle])
        #expect(inside.holder(of: app) == bundle)
        #expect(inside.holder(of: bundle) == steam)
    }

    @Test func goesByWholeNames() {
        let beside = URL(filePath: "/Users/me/Library/Application Support/Steam 2")
        let again = URL(filePath: "/Users/me/Library/Application Support/Steam")
        let inside = ItemsInsideOthers([steam, beside, again])
        #expect(inside.holder(of: beside) == nil)
        #expect(inside.holder(of: again) == nil)
        #expect(inside.holder(of: steam) == nil)
    }

    /// The temporary folder is `/var/folders` to `confstr` and `/private/var/folders` to the kernel.
    @Test func readsAFolderUnderPrivateAsTheSameFolder() throws {
        let directory = try TemporaryDirectory()
        let file = try directory.file("steam/state.json")
        let path = file.deletingLastPathComponent().path(percentEncoded: false)
        #expect(path.hasPrefix("/var/") || path.hasPrefix("/private/var/"))
        let other = path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : "/private" + path
        let folder = URL(filePath: other, directoryHint: .isDirectory)
        #expect(ItemsInsideOthers([folder, file]).holder(of: file) == folder)
    }

    @Test func namesNothingForAnItemNotOnTheList() {
        #expect(ItemsInsideOthers([steam]).holder(of: bundle) == nil)
    }
}
