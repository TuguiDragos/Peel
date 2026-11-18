import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct IntelHomebrewWordsTests {
    @Test func aCommandFromHomebrewSaysSoAndWhichFormula() {
        let formula = IntelFinding.Formula(name: "wget", prefix: URL(filePath: "/usr/local"))
        let finding = IntelFinding(
            url: URL(filePath: "/usr/local/Cellar/wget/1.24/bin/wget"), kind: .commandLineTool, name: "wget",
            owner: nil, size: nil, commandFolder: .homebrew, formula: formula
        )
        let explained = IntelFinding.CommandFolder.homebrew.explanation(onAppleSilicon: true)
            .map { String(localized: $0) }

        #expect(explained?.contains("/opt/homebrew") == true)
        #expect(finding.subtitle.map { String(localized: $0) } == "from wget in Homebrew")
    }

    @Test func aCommandFromACaskOnAppleSiliconSaysSoAndWhichCask() {
        let cask = IntelFinding.Cask(token: "inso", prefix: URL(filePath: "/opt/homebrew"))
        let finding = IntelFinding(
            url: URL(filePath: "/opt/homebrew/Caskroom/inso/12.0/inso"), kind: .commandLineTool, name: "inso",
            owner: nil, size: nil, commandFolder: .optHomebrew, cask: cask
        )

        #expect(String(localized: finding.explanation(onAppleSilicon: true)).contains("needs Rosetta"))
        #expect(finding.subtitle.map { String(localized: $0) } == "from inso in Homebrew")
    }
}
