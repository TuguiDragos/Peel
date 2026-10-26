import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct IntelExplanationTests {
    private func plugin(_ category: Plugin.Category) -> IntelFinding {
        IntelFinding(
            url: URL(filePath: "/Library/Audio/Plug-Ins/Components/Synth.component"), kind: .plugin, name: "Synth",
            owner: nil, size: 10, pluginCategory: category
        )
    }

    @Test func saysWhereAnIntelPlugInCanLoad() {
        let words = { (finding: IntelFinding) in String(localized: finding.explanation(onAppleSilicon: true)) }

        #expect(words(plugin(.vst3)) == String(localized: "This plug-in is Intel only. It loads only inside an app that itself runs through Rosetta."))
        #expect(words(plugin(.audioDrivers)) == String(localized: "This plug-in is Intel only, so it needs Rosetta to load."))
        #expect(plugin(.vst3).loadsThroughAnApp && plugin(.audioUnits).loadsThroughAnApp)
        #expect(!plugin(.screenSavers).loadsThroughAnApp)
        #expect(String(localized: plugin(.vst3).explanation(onAppleSilicon: false)) == String(localized: "This plug-in is Intel only. On this Intel Mac it loads natively."))
    }

    @Test func tellsAPlugInsFormatsApart() {
        let words = { (finding: IntelFinding) in finding.subtitle.map { String(localized: $0) } }

        #expect(words(plugin(.vst3)) == String(localized: "VST3 Plug-ins"))
        #expect(words(plugin(.audioUnits)) == String(localized: "Audio Units"))
    }

    @Test func givesApplesCommandWhereNothingOpensToOfferRosetta() {
        #expect(IntelFinding.Kind.allCases.filter(\.offersRosettaWhenOpened) == [.app])
        #expect(Rosetta.installCommand == "softwareupdate --install-rosetta")
    }
}
