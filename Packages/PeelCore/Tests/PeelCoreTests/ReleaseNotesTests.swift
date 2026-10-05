import Foundation
@testable import PeelCore
import Testing

struct ReleaseNotesTests {
    /// Each block as one line: its kind, a list item's depth, and its words.
    private func outline(_ html: String) -> [String] {
        outline(ReleaseNotes(html, format: .html))
    }

    private func outline(_ notes: ReleaseNotes?) -> [String] {
        (notes?.blocks ?? []).map { block in
            switch block {
            case .heading(let text): "h " + String(text.characters)
            case .paragraph(let text): "p " + String(text.characters)
            case .item(let text, let depth): "i\(depth) " + String(text.characters)
            }
        }
    }

    private func links(_ notes: ReleaseNotes?) -> [URL] {
        (notes?.blocks ?? []).flatMap { block -> [URL] in
            let text = switch block {
            case .heading(let text), .paragraph(let text), .item(let text, _): text
            }
            return text.runs.compactMap(\.link)
        }
    }

    @Test func readsPlainTextLineByLine() {
        let notes = ReleaseNotes("What’s new:\n\n• Faster search\n- Fixed a crash\n\nThanks for using it!", format: .plainText)

        #expect(outline(notes) == ["p What’s new:", "i0 Faster search", "i0 Fixed a crash", "p Thanks for using it!"])
    }

    @Test func joinsTheIndentedLinesThatContinueAnItem() {
        let text = "Bug Fixes:\r\n- Fixed the API not reporting\n  hyperlinks.\n- Fixed a crash\n- \nLine one\nLine two"

        #expect(outline(ReleaseNotes(text, format: .plainText)) == [
            "p Bug Fixes:", "i0 Fixed the API not reporting hyperlinks.", "i0 Fixed a crash", "p Line one", "p Line two",
        ])
    }

    @Test func readsMarkdownBlocksAndKeepsOnlySecureLinks() {
        let markdown = """
        ## 2.0

        A new **search**.

        - One
          - Nested
        - [Site](https://example.com) and [script](javascript:alert(1)) and [plain](http://example.com)

        ![Tracker](https://example.com/pixel.png)
        """

        let notes = ReleaseNotes(markdown, format: .markdown)

        #expect(outline(notes) == ["h 2.0", "p A new search.", "i0 One", "i1 Nested", "i0 Site and script and plain"])
        #expect(links(notes) == [URL(string: "https://example.com")!])
    }

    @Test func readsHTMLBlocksAndLeavesOutWhatWouldLoadOrRun() {
        let html = """
        <h2>New</h2><p>Fast <b>search</b>.<br>Second line</p>
        <ul><li>One<ul><li>Two</li></ul></li>
        <li><a href="https://example.com">Site</a> and <a href="http://example.com">plain</a></li></ul>
        <script>alert(1)</script><style>p { color: red }</style><img src="https://example.com/pixel.gif">
        """

        let notes = ReleaseNotes(html, format: .html)

        #expect(outline(notes) == ["h New", "p Fast search.\nSecond line", "i0 One", "i1 Two", "i0 Site and plain"])
        #expect(links(notes) == [URL(string: "https://example.com")!])
    }

    @Test func readsTextBesideBlocksInAnAppcastsDescription() {
        let html = "v2.0.2: Fixes a couple of issues <p>v2.0:</p> <ul> <li>The UI has been redesigned</li> </ul>"

        #expect(outline(ReleaseNotes(html, format: .html)) == ["p v2.0.2: Fixes a couple of issues", "p v2.0:", "i0 The UI has been redesigned"])
    }

    @Test func readsHTMLWrittenInAnyLanguage() {
        #expect(outline(ReleaseNotes("<p>Café déjà vu, 日本語, Ελληνικά</p>", format: .html)) == ["p Café déjà vu, 日本語, Ελληνικά"])
    }

    @Test func readsNoEntityAPageDeclares() {
        let laughs = (1...5).map { level in
            "<!ENTITY l\(level) \"" + String(repeating: "&l\(level - 1);", count: 10) + "\">"
        }.joined()
        let bomb = "<!DOCTYPE html [<!ENTITY l0 \"laugh\">\(laughs)]><p>&l5;</p>"
        let outside = "<!DOCTYPE html [<!ENTITY secret SYSTEM \"file:///etc/passwd\">]><p>Notes &secret;</p>"

        let words = [bomb, outside].flatMap(outline)
        #expect(words.joined().count < 100)
        #expect(!words.joined().contains("root"))
    }

    @Test func readsTextWithNoTagAsAParagraph() {
        #expect(outline(ReleaseNotes("New   search\nand more", format: .html)) == ["p New search and more"])
    }

    @Test func keepsNothingFromNotesWithNoWords() {
        #expect(ReleaseNotes(" \n\t", format: .plainText) == nil)
        #expect(ReleaseNotes("<p> </p><img src=\"https://example.com/a.png\">", format: .html) == nil)
        #expect(ReleaseNotes("![Screenshot](https://example.com/a.png)", format: .markdown) == nil)
    }

    @Test func keepsAtMostTheLimit() {
        let long = String(repeating: "word ", count: ReleaseNotes.limit)

        #expect(ReleaseNotes(long, format: .plainText)?.text.count ?? 0 <= ReleaseNotes.limit)
    }
}
