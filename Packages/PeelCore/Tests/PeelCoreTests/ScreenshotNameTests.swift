import Foundation
@testable import PeelCore
import Testing

struct ScreenshotNameTests {
    @Test func namesAScreenshotInTheLanguageOfTheMacNotOfThisProcess() {
        let romanian = ScreenshotName.macOSDefault(preferring: ["ro-RO", "en"])
        let german = ScreenshotName.macOSDefault(preferring: ["de-DE"])
        let english = ScreenshotName.macOSDefault(preferring: ["en"])

        #expect(english == "Screenshot")
        #expect(romanian != nil && romanian != english)
        #expect(german != nil && german != english && german != romanian)
    }

    @Test func aNameIsAFileNameMacOSCanWriteAndShow() {
        #expect(ScreenshotName.problem(with: "ss") == nil)
        #expect(ScreenshotName.problem(with: "Captură de ecran") == nil)
        #expect(ScreenshotName.problem(with: "a/b") == .separator)
        #expect(ScreenshotName.problem(with: "a:b") == .separator)
        #expect(ScreenshotName.problem(with: ".shot") == .hidden)
        #expect(ScreenshotName.problem(with: String(repeating: "ă", count: 101)) == .tooLong)
        #expect(ScreenshotName.problem(with: String(repeating: "a", count: 200)) == nil)
    }

    @Test func readsTheNameMacOSGivesScreenshots() throws {
        let name = try #require(ScreenshotName.macOSDefault)
        #expect(!name.isEmpty)
    }

    @Test func screenshotsCanBeGivenAName() throws {
        let tweak = try #require(TweakCatalog.all.first { $0.domain == "com.apple.screencapture" && $0.key == "name" })
        #expect(tweak.kind == .name)
        #expect(tweak.group == .screenshots)
    }
}
