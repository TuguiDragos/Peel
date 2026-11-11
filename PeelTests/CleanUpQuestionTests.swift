import Foundation
@testable import Peel
import Testing

struct CleanUpQuestionTests {
    @Test func theQuestionDescribesTheFormulaeOnceThenNamesThem() {
        let size = Int64(2_000_000_000)
        let formulae = ["alpha", "beta"]

        let warning = HomebrewList.cleanUpWarning(
            reclaimable: size, keepsDependencies: false, prefix: nil, formulae: formulae
        )

        #expect(warning == [
            String(localized: "Homebrew deletes these for good: about \(size.byteCount) of downloads and old versions, and the formulae nothing needs anymore, which that figure leaves out. Nothing goes to the Trash, and History can’t put it back."),
            String(inflecting: "Right now that is ^[\(formulae.count) formula](inflect: true): \(RemovalFailureAlert.listedFormulae(formulae))."),
        ].joined(separator: "\n\n"))
    }
}
