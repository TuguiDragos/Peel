import Foundation
@testable import PeelCore
import Testing

struct ReleaseNotesTests {
    /// Each block as one line: its kind, a list item's depth, and its words.
    private func outline(_ html: String) async -> [String] {
        await outline(await ReleaseNotes(html, format: .html))
    }

    private func outline(_ notes: ReleaseNotes?) async -> [String] {
        (await notes?.blocks() ?? []).map { block in
            switch block {
            case .heading(let text): "h " + String(text.characters)
            case .paragraph(let text): "p " + String(text.characters)
            case .item(let text, let depth): "i\(depth) " + String(text.characters)
            }
        }
    }

    private func links(_ notes: ReleaseNotes?) async -> [URL] {
        (await notes?.blocks() ?? []).flatMap { block -> [URL] in
            let text = switch block {
            case .heading(let text), .paragraph(let text), .item(let text, _): text
            }
            return text.runs.compactMap(\.link)
        }
    }

    @Test func readsPlainTextLineByLine() async {
        let notes = await ReleaseNotes("What’s new:\n\n• Faster search\n- Fixed a crash\n\nThanks for using it!", format: .plainText)

        #expect(await outline(notes) == ["p What’s new:", "i0 Faster search", "i0 Fixed a crash", "p Thanks for using it!"])
    }

    @Test func joinsTheIndentedLinesThatContinueAnItem() async {
        let text = "Bug Fixes:\r\n- Fixed the API not reporting\n  hyperlinks.\n- Fixed a crash\n- \nLine one\nLine two"

        #expect(await outline(await ReleaseNotes(text, format: .plainText)) == [
            "p Bug Fixes:", "i0 Fixed the API not reporting hyperlinks.", "i0 Fixed a crash", "p Line one", "p Line two",
        ])
    }

    @Test func readsMarkdownBlocksAndKeepsOnlySecureLinks() async {
        let markdown = """
        ## 2.0

        A new **search**.

        - One
          - Nested
        - [Site](https://example.com) and [script](javascript:alert(1)) and [plain](http://example.com)

        ![Tracker](https://example.com/pixel.png)
        """

        let notes = await ReleaseNotes(markdown, format: .markdown)

        #expect(await outline(notes) == ["h 2.0", "p A new search.", "i0 One", "i1 Nested", "i0 Site and script and plain"])
        #expect(await links(notes) == [URL(string: "https://example.com")!])
    }

    @Test func readsHTMLBlocksAndLeavesOutWhatWouldLoadOrRun() async {
        let html = """
        <h2>New</h2><p>Fast <b>search</b>.<br>Second line</p>
        <ul><li>One<ul><li>Two</li></ul></li>
        <li><a href="https://example.com">Site</a> and <a href="http://example.com">plain</a></li></ul>
        <script>alert(1)</script><style>p { color: red }</style><img src="https://example.com/pixel.gif">
        """

        let notes = await ReleaseNotes(html, format: .html)

        #expect(await outline(notes) == ["h New", "p Fast search.\nSecond line", "i0 One", "i1 Two", "i0 Site and plain"])
        #expect(await links(notes) == [URL(string: "https://example.com")!])
    }

    /// Each block's runs with what they carry: `b` strong, `i` emphasized, `c` code, `l` a link.
    private func styles(_ html: String) async -> [String] {
        (await ReleaseNotes(html, format: .html)?.blocks() ?? []).map { block in
            let text = switch block {
            case .heading(let text), .paragraph(let text), .item(let text, _): text
            }
            return text.runs.map { run in
                let intent = run.inlinePresentationIntent ?? []
                let marks = (intent.contains(.stronglyEmphasized) ? "b" : "") + (intent.contains(.emphasized) ? "i" : "")
                    + (intent.contains(.code) ? "c" : "") + (run.link == nil ? "" : "l")
                return "[\(marks)]" + String(text[run.range].characters)
            }.joined()
        }
    }

    @Test func readsNestedBlocksInTheOrderAndStyleABrowserShowsThem() async {
        let html = """
        Before<div>In <b>bold <i>both <a href="https://example.com/a">linked</a></i></b> after<h3>Head <code>code</code></h3>
        tail<ol><li>One <em>more</em><ul><li>Two<blockquote>Quoted<br>line</blockquote>rest</li><li>Three</li></ul>
        end</li><li><p>Four</p><p>Five</p></li></ol><table><tr><td>Cell</td><td><strong>Next</strong></td></tr></table>
        <iframe src="https://example.com">hidden <b>too</b></iframe></div>After
        """

        #expect(await outline(html) == [
            "p Before", "p In bold both linked after", "h Head code", "p tail", "i0 One more", "i1 Two", "i1 Quoted\nline",
            "i1 rest", "i1 Three", "i0 end", "i0 Four", "i0 Five", "p Cell Next", "p After",
        ])
        #expect(await styles(html) == [
            "[]Before", "[]In [b]bold [bi]both [bil]linked[] after", "[]Head [c]code", "[]tail", "[]One [i]more", "[]Two",
            "[]Quoted\nline", "[]rest", "[]Three", "[]end", "[]Four", "[]Five", "[]Cell [b]Next", "[]After",
        ])
    }

    /// Read where an update round and the notes' view read them, on a thread of Swift's pool, whose stack is small.
    @Test(arguments: ["<ul><li>", "<div>", "<dl>", "<blockquote>", "<q>"])
    func readsNotesNestedAsDeepAsTheLimitAllows(tags: String) async {
        let levels = (ReleaseNotes.limit - 5) / tags.count
        let html = String(repeating: tags, count: levels) + "words"

        let notes = await Task.detached { await ReleaseNotes(html, format: .html) }.value

        #expect(await outline(notes) == [tags == "<ul><li>" ? "i\(levels - 1) words" : "p words"])
    }

    @Test func keepsAtMostTheLimitOfNotesReadFromAFile() async throws {
        let long = String(repeating: "word ", count: ReleaseNotes.limit)
        let kept = try JSONEncoder().encode(["format": "plainText", "text": long])

        let notes = try JSONDecoder().decode(ReleaseNotes.self, from: kept)

        #expect(notes.text.count == ReleaseNotes.limit)
    }

    @Test func readsTextBesideBlocksInAnAppcastsDescription() async {
        let html = "v2.0.2: Fixes a couple of issues <p>v2.0:</p> <ul> <li>The UI has been redesigned</li> </ul>"

        #expect(await outline(await ReleaseNotes(html, format: .html)) == ["p v2.0.2: Fixes a couple of issues", "p v2.0:", "i0 The UI has been redesigned"])
    }

    @Test func readsHTMLWrittenInAnyLanguage() async {
        #expect(await outline(await ReleaseNotes("<p>Café déjà vu, 日本語, Ελληνικά</p>", format: .html)) == ["p Café déjà vu, 日本語, Ελληνικά"])
    }

    @Test func readsNoEntityAPageDeclares() async {
        let laughs = (1...5).map { level in
            "<!ENTITY l\(level) \"" + String(repeating: "&l\(level - 1);", count: 10) + "\">"
        }.joined()
        let bomb = "<!DOCTYPE html [<!ENTITY l0 \"laugh\">\(laughs)]><p>&l5;</p>"
        let outside = "<!DOCTYPE html [<!ENTITY secret SYSTEM \"file:///etc/passwd\">]><p>Notes &secret;</p>"

        let words = await outline(bomb) + outline(outside)
        #expect(words.joined().count < 100)
        #expect(!words.joined().contains("root"))
    }

    @Test func readsTextWithNoTagAsAParagraph() async {
        #expect(await outline(await ReleaseNotes("New   search\nand more", format: .html)) == ["p New search and more"])
    }

    @Test func keepsNothingFromNotesWithNoWords() async {
        #expect(await ReleaseNotes(" \n\t", format: .plainText) == nil)
        #expect(await ReleaseNotes("<p> </p><img src=\"https://example.com/a.png\">", format: .html) == nil)
        #expect(await ReleaseNotes("![Screenshot](https://example.com/a.png)", format: .markdown) == nil)
    }

    @Test func keepsAtMostTheLimit() async {
        let long = String(repeating: "word ", count: ReleaseNotes.limit)

        #expect(await ReleaseNotes(long, format: .plainText)?.text.count ?? 0 <= ReleaseNotes.limit)
    }
}
