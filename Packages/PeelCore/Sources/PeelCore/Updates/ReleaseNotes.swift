public import Foundation

/// What a release says is new, as its store, its feed or its notes page writes it.
public struct ReleaseNotes: Sendable, Hashable, Codable {
    public enum Format: String, Sendable, Hashable, Codable {
        case plainText
        case markdown
        case html
    }

    /// A block of the notes as they are shown: a heading, a paragraph, or an item of a list nested `depth` deep.
    public enum Block: Sendable, Hashable {
        case heading(AttributedString)
        case paragraph(AttributedString)
        case item(AttributedString, depth: Int)
    }

    /// The most kept of one release's notes. A feed or a page can hold a whole history, which the box has no room
    /// for, so the rest stays behind the link.
    static let limit = 20_000

    public let format: Format
    public let text: String

    /// Nil for notes that show nothing once what cannot be shown is left out: images, scripts and styles.
    public init?(_ text: String, format: Format) {
        self.format = format
        self.text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.limit))
        guard !blocks.isEmpty else { return nil }
    }

    /// Notes read from a file keep the limit too, whoever wrote them: the stack HTML is read on is sized for it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(Format.self, forKey: .format)
        text = String(try container.decode(String.self, forKey: .text).prefix(Self.limit))
    }

    /// The notes as blocks of text. Nothing is loaded from anywhere, and a link is kept only when it is https.
    public var blocks: [Block] {
        switch format {
        case .plainText: Self.plainTextBlocks(text)
        case .markdown: Self.markdownBlocks(text)
        case .html: HTMLReader.blocks(of: text)
        }
    }

    /// Each line is a paragraph or, after a bullet, a list item, and an indented line goes on with the one above,
    /// the way plain text wraps a long item.
    private static func plainTextBlocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var goesOn = false
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let words = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if words.isEmpty {
                goesOn = false
            } else if let mark = words.first, "•-*".contains(mark), words.dropFirst().first?.isWhitespace ?? true {
                let item = words.dropFirst().trimmingCharacters(in: .whitespaces)
                if !item.isEmpty {
                    blocks.append(.item(AttributedString(item), depth: 0))
                }
                goesOn = !item.isEmpty
            } else if goesOn, line.first?.isWhitespace == true, let last = blocks.popLast() {
                blocks.append(last.goingOn(with: words))
            } else {
                blocks.append(.paragraph(AttributedString(words)))
                goesOn = true
            }
        }
        return blocks
    }

    private static func markdownBlocks(_ text: String) -> [Block] {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            return plainTextBlocks(text)
        }
        return parsed.runs[\.presentationIntent].compactMap { intent, range in
            var kept = AttributedString()
            for run in parsed[range].runs where run.imageURL == nil {
                var piece = AttributedString(parsed[run.range])
                piece.presentationIntent = nil
                if run.link?.scheme != "https" {
                    piece.link = nil
                }
                kept.append(piece)
            }
            guard let words = kept.trimmed else { return nil }
            let kinds = intent?.components.map(\.kind) ?? []
            if kinds.contains(where: { if case .header = $0 { true } else { false } }) {
                return .heading(words)
            }
            if kinds.contains(where: { if case .listItem = $0 { true } else { false } }) {
                let lists = kinds.count { $0 == .orderedList || $0 == .unorderedList }
                return .item(words, depth: max(lists - 1, 0))
            }
            return .paragraph(words)
        }
    }
}

extension ReleaseNotes.Block {
    /// The block with `words` after its own, as one line wrapped onto the next.
    fileprivate func goingOn(with words: String) -> ReleaseNotes.Block {
        switch self {
        case .heading(let text): .heading(text + AttributedString(" " + words))
        case .paragraph(let text): .paragraph(text + AttributedString(" " + words))
        case .item(let text, let depth): .item(text + AttributedString(" " + words), depth: depth)
        }
    }
}

extension AttributedString {
    /// The text without the white space around it, or nil when nothing else is left.
    fileprivate var trimmed: AttributedString? {
        let characters = self.characters
        guard let first = characters.firstIndex(where: { !$0.isWhitespace }),
              let last = characters.lastIndex(where: { !$0.isWhitespace })
        else { return nil }
        return AttributedString(self[first...last])
    }
}

/// Reads an HTML fragment into blocks, the way a browser lays it out in the large: headings, paragraphs, line breaks
/// and lists, with bold, italic, code and https links. What only loads or runs something (an image, a script, a
/// style, a frame) is left out, and nothing is fetched.
private struct HTMLReader {
    private static let leftOut: Set<String> = [
        "head", "script", "style", "noscript", "template", "iframe", "object", "embed", "img", "picture", "svg",
        "video", "audio", "canvas", "form", "input", "button", "select", "textarea",
    ]
    private static let separate: Set<String> = [
        "p", "div", "blockquote", "pre", "section", "article", "header", "footer", "main", "nav", "aside", "table",
        "tr", "dl", "dt", "dd", "figure", "figcaption", "details", "summary", "hr", "body", "html",
    ]

    private enum Kind {
        case heading
        case item(depth: Int)
    }

    /// What is left to do, the next step last. The steps wait in a list rather than on the stack, so notes nested
    /// however deep are read in the same room.
    private enum Step {
        case read(XMLNode, lists: Int, style: AttributeContainer)
        case endLine
        /// Ends the heading or list item being read.
        case close
    }

    /// The megabytes of stack the system's parser is given: it goes a step deeper for each tag open inside another,
    /// and the deepest notes `ReleaseNotes.limit` characters can hold take it about two.
    private static let parsersStack = 16

    private(set) var blocks: [ReleaseNotes.Block] = []
    private var line = AttributedString()
    /// The heading or list item the words being read belong to; none for a paragraph.
    private var open: [Kind] = []

    static func blocks(of html: String) -> [ReleaseNotes.Block] {
        // Read from text rather than bytes: HTML's parser takes bytes as Latin-1 unless an old-style meta tag says
        // otherwise.
        let options: XMLNode.Options = [.documentTidyHTML, .nodeLoadExternalEntitiesNever]
        return DeepStack.run(megabytes: parsersStack) {
            var reader = HTMLReader()
            if let root = (try? XMLDocument(xmlString: html, options: options))?.rootElement() {
                reader.read(root)
            } else if !html.contains("<") {
                // Text with no tag at all is no document to the parser, while a browser shows it as a paragraph.
                reader.add(html, style: AttributeContainer())
            }
            reader.endLine()
            return reader.blocks
        }
    }

    private mutating func read(_ root: XMLNode) {
        var steps: [Step] = [.read(root, lists: 0, style: AttributeContainer())]
        while let step = steps.popLast() {
            switch step {
            case .endLine:
                endLine()
            case .close:
                endLine()
                open.removeLast()
            case .read(let node, let lists, let style):
                if node.kind == .text {
                    add(node.stringValue ?? "", style: style)
                } else if let element = node as? XMLElement {
                    steps += read(element, lists: lists, style: style)
                }
            }
        }
    }

    /// Reads what `element` itself says and answers what is left to do for it, the next step last: its children, and
    /// after them the end of the block it opened.
    private mutating func read(_ element: XMLElement, lists: Int, style: AttributeContainer) -> [Step] {
        let name = element.name?.lowercased() ?? ""
        guard !Self.leftOut.contains(name) else { return [] }
        var (lists, style) = (lists, style)
        var after: Step?
        switch name {
        case "br":
            line.append(AttributedString("\n", attributes: style))
            return []
        case "h1", "h2", "h3", "h4", "h5", "h6":
            endLine()
            open.append(.heading)
            after = .close
        case "li":
            endLine()
            open.append(.item(depth: max(lists - 1, 0)))
            after = .close
        case "ul", "ol":
            endLine()
            lists += 1
            after = .endLine
        case "a":
            if let href = element.attribute(forName: "href")?.stringValue, let url = URL(string: href),
               url.scheme == "https" {
                style.link = url
            }
        case "b", "strong":
            style.inlinePresentationIntent = (style.inlinePresentationIntent ?? []).union(.stronglyEmphasized)
        case "i", "em":
            style.inlinePresentationIntent = (style.inlinePresentationIntent ?? []).union(.emphasized)
        case "code", "tt", "kbd", "samp":
            style.inlinePresentationIntent = (style.inlinePresentationIntent ?? []).union(.code)
        default:
            if Self.separate.contains(name) {
                endLine()
                after = .endLine
            }
        }
        let children = (element.children ?? []).reversed().map { Step.read($0, lists: lists, style: style) }
        return (after.map { [$0] } ?? []) + children
    }

    /// Adds text as a browser shows it: every run of white space is one space, and none starts a line.
    private mutating func add(_ text: String, style: AttributeContainer) {
        var words = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if text.first?.isWhitespace == true { words = " " + words }
        if text.last?.isWhitespace == true, !words.hasSuffix(" ") { words += " " }
        if line.characters.last.map({ $0.isWhitespace }) ?? true {
            words = String(words.drop(while: \.isWhitespace))
        }
        guard !words.isEmpty else { return }
        line.append(AttributedString(words, attributes: style))
    }

    private mutating func endLine() {
        defer { line = AttributedString() }
        guard let words = line.trimmed else { return }
        switch open.last {
        case .heading: blocks.append(.heading(words))
        case .item(let depth): blocks.append(.item(words, depth: depth))
        case nil: blocks.append(.paragraph(words))
        }
    }
}
