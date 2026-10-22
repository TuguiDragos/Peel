import Foundation
@testable import Peel
import PeelCore
import Testing

@Suite(.serialized) struct HomebrewLibraryTests {
    @Test func readsHomebrewAgainOnceItCheckedForNewVersions() async {
        guard Homebrew.executableURL != nil, await Homebrew.hasLocalDefinitions() else { return }
        let homebrew = HomebrewLibrary()
        await homebrew.refresh()
        let read = homebrew.revision
        let checked = await Homebrew.lastUpdateCheck()

        #expect(await !homebrew.readAgain(ifHomebrewCheckedAt: checked))
        #expect(homebrew.revision == read)
        #expect(await homebrew.readAgain(ifHomebrewCheckedAt: (checked ?? .now) + 1))
        #expect(homebrew.revision == read + 1)
    }
}
