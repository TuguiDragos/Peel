@testable import Peel
import Testing

struct UnreadableFoldersTests {
    @Test func namesTheFirstFourFoldersAndCountsTheRest() {
        let paths = (1...60).map { "/Volumes/Old/f\($0)x" }

        let sentence = RemovalFailureAlert.listedFolders(paths)

        #expect(sentence.contains("f4x") && !sentence.contains("f5x") && !sentence.contains("f60x"))
        #expect(sentence.contains("56"))
        #expect(RemovalFailureAlert.listedFolders(["/a", "/b"]).contains("/b"))
    }

    @Test func namesTheFoldersAndAddsTheAdviceOnlyWhenFullDiskAccessWouldHelp() {
        let paths = ["/Users/me/Documents/app", "/Users/me/work/pgdata"]
        let advice = UnreadableFoldersNotice.detail(naming: [], needsFullDiskAccess: true)

        let both = UnreadableFoldersNotice.detail(naming: paths, needsFullDiskAccess: true)
        let named = UnreadableFoldersNotice.detail(naming: paths, needsFullDiskAccess: false)

        #expect(!advice.isEmpty)
        #expect(both.contains("pgdata") && both.hasSuffix(advice))
        #expect(named.contains("pgdata") && !named.contains(advice))
    }

    @Test func anAlertsFirstItemsAndHowManyMore() {
        let (shown, more) = RemovalFailureAlert.first(Array(1...60))

        #expect(shown == [1, 2, 3, 4] && more == 56)
        #expect(RemovalFailureAlert.first([1, 2]) == ([1, 2], 0))
    }
}

struct CleanUpWarningTests {
    @Test func namesTheFirstFourFormulaeItUninstalls() {
        let formulae = (1...30).map { "formula\($0)x" }

        let sentence = HomebrewList.uninstalls(formulae)

        #expect(sentence.contains("formula4x") && !sentence.contains("formula5x") && !sentence.contains("formula30x"))
        #expect(sentence.contains("26"))
    }
}
