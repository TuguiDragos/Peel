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

    @Test func saysWhereAnIntelCommandIsAndMacPortsOwnStep() {
        func words(_ place: IntelFinding.CommandFolder?, onAppleSilicon: Bool = true) -> String {
            var command = IntelFinding(
                url: URL(filePath: "/opt/local/bin/tool"), kind: .commandLineTool, name: "tool", owner: nil, size: 10
            )
            command.commandFolder = place
            return String(localized: command.explanation(onAppleSilicon: onAppleSilicon))
        }

        #expect(words(.macPorts) == String(localized: "This tool from MacPorts is Intel only, so it needs Rosetta to run. MacPorts reinstalls its ports for this Mac with `sudo port migrate`."))
        #expect(words(.home) == String(localized: "This tool in your home folder is Intel only, so it needs Rosetta to run. If its maker offers a version for Apple silicon, install that one instead."))
        #expect(words(.home, onAppleSilicon: false) == String(localized: "This tool in your home folder is Intel only. On this Intel Mac it runs natively."))
        #expect(words(.macPorts, onAppleSilicon: false) == String(localized: "This tool from MacPorts is Intel only. On this Intel Mac it runs natively."))
        #expect(words(.usrLocal) == String(localized: "This tool in /usr/local is Intel only, so it needs Rosetta to run."))
        #expect(words(nil) == words(.usrLocal))
    }

    @Test func saysNothingLoadsAPlugInOfAKindMacOSLeftBehind() {
        var generator = plugin(.quickLook)
        generator.noLongerLoaded = .quickLookGenerator
        var part = IntelFinding(
            url: URL(filePath: "/Applications/Example.app/Contents/Library/QuickLook/Old.qlgenerator"),
            kind: .insideApp, name: "Old.qlgenerator", owner: "Example", size: 10
        )
        part.noLongerLoaded = .quickLookGenerator

        #expect(String(localized: generator.explanation(onAppleSilicon: true)).contains("no longer loads"))
        #expect(String(localized: part.explanation(onAppleSilicon: true)).contains("no longer loads"))
    }

    @Test func aUniversalAppIsNotCalledIntelOnly() {
        let app = IntelFinding(
            url: URL(filePath: "/Applications/Example.app"), kind: .app, name: "Example", owner: nil, size: 10,
            prefersIntel: true
        )
        let intel = IntelFinding(
            url: URL(filePath: "/Applications/Old.app"), kind: .app, name: "Old", owner: nil, size: 10
        )

        #expect(String(localized: app.badge.title) == String(localized: "Opens as Intel"))
        #expect(String(localized: app.withoutRosetta).contains("its Intel version can’t run here"))
        #expect(String(localized: intel.badge.title) == String(localized: "Intel only"))
        #expect(String(localized: intel.withoutRosetta).contains("doesn’t run at all"))
    }

    @Test func saysWhyAUniversalAppStillRunsThroughRosetta() {
        let app = IntelFinding(
            url: URL(filePath: "/Applications/Example.app"), kind: .app, name: "Example", owner: nil, size: 10,
            prefersIntel: true
        )

        #expect(String(localized: app.explanation(onAppleSilicon: true)) == String(localized: "This app has a version for Apple silicon, but it asks macOS to open it as an Intel app, so it runs through Rosetta."))
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
