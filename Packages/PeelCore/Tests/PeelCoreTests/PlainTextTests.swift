@testable import PeelCore
import Testing

struct PlainTextTests {
    /// Unicode's own line and paragraph separators end a line for a script as a newline does, and the
    /// bidirectional controls can show a path in another order than it has.
    @Test func showsLineSeparatorsAndDirectionControlsAsQuestionMarks() {
        #expect(PlainText.of("Orphan\u{2028}com.apple.Mail") == "Orphan?com.apple.Mail")
        #expect(PlainText.of("Orphan\u{2029}Folder") == "Orphan?Folder")
        #expect(PlainText.of("/Users/me/\u{202E}gpj.app") == "/Users/me/?gpj.app")
        #expect(PlainText.of("\u{2066}Evil\u{2069}") == "?Evil?")
        #expect(PlainText.of("\u{200F}Evil\u{FEFF}") == "?Evil?")
        #expect(PlainText.of("Evil\u{E0041}\u{E0042}") == "Evil??")
        #expect(PlainText.of("Evil\u{1B}[2J\u{85}\t") == "Evil?[2J??")
    }

    /// The joiners only join the letters or emoji around them, which Persian, the Indic scripts and emoji
    /// sequences need, so they stay, as letters, marks and spaces do.
    @Test func keepsTheJoinersAndEverythingPrintable() {
        let names = ["می\u{200C}خواهم", "क्\u{200D}ष", "👩\u{200D}💻 Studio", "Café", "e\u{301}", "日本語 アプリ", "Editor Pro 2"]
        for name in names {
            #expect(PlainText.of(name) == name)
        }
    }
}
