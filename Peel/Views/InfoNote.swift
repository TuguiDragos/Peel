import SwiftUI

/// A circled i beside a title. What would otherwise be paragraphs under the row lives in here instead.
struct InfoNote: View {
    let heading: Text
    /// What VoiceOver calls the button.
    let label: Text
    /// Built when the note opens: a list draws hundreds of these, and few are ever opened.
    let detail: () -> Text?
    var symbol: String?
    /// The technical line, when there is one worth keeping but not worth a row of its own.
    var footnote: Text?
    /// A page the note leads to, shown as its last line.
    var link: URL?
    /// Already localized: the words the link goes by, in place of its address.
    var linkTitle: String?
    /// Something to know before acting. It draws the circle in the accent color.
    var caution: Text?
    /// Only Home passes this; see `noteTint`.
    var isAlbum = false
    /// True for the note in each row of a list of items, whose button takes `RowButtonStyle`.
    var isInRow = false
    /// Whether the note is open, when something beside the button opens it as well, such as a row's menu.
    var opening: Binding<Bool>?

    @State private var isOpenHere = false

    private var isOpen: Binding<Bool> {
        opening ?? $isOpenHere
    }

    /// `name` is already localized: the note's heading, and what its accessibility label names.
    init(
        name: String,
        detail: @autoclosure @escaping () -> Text?,
        symbol: String? = nil,
        footnote: Text? = nil,
        link: URL? = nil,
        caution: Text? = nil,
        isAlbum: Bool = false,
        isInRow: Bool = false,
        opening: Binding<Bool>? = nil
    ) {
        heading = Text(verbatim: name)
        label = caution == nil ? Text("What \(name) is for") : Text("A caution about \(name)")
        self.detail = detail
        self.symbol = symbol
        self.footnote = footnote
        self.link = link
        self.caution = caution
        self.isAlbum = isAlbum
        self.isInRow = isInRow
        self.opening = opening
    }

    /// A notice's circled i. Its title is a sentence, so VoiceOver calls it More Info, as an info button is called.
    init(about title: Text, detail: Text, link: URL? = nil, linkTitle: String? = nil, isAlbum: Bool) {
        heading = title
        label = Text("More Info")
        self.detail = { detail }
        self.link = link
        self.linkTitle = linkTitle
        self.isAlbum = isAlbum
    }

    private var isMarked: Bool {
        caution != nil
    }

    /// A marked note says so in its shape as well: by color alone it is the fainter of the two in light mode.
    private var mark: String {
        isMarked ? "exclamationmark.circle.fill" : "info.circle"
    }

    var body: some View {
        Button { isOpen.wrappedValue = true } label: {
            Image(systemName: mark)
                .font(.callout.weight(.semibold))
                .foregroundStyle(isOpen.wrappedValue || isMarked ? noteTint(isAlbum: isAlbum) : Color.secondary)
                .padding(4)
                .contentShape(.rect)
        }
        .noteButtonStyle(isInRow: isInRow)
        // The button takes clicks across its own frame, 4 points around the glyph; the layout keeps the glyph's.
        .padding(-4)
        .accessibilityLabel(label)
        .popover(isPresented: isOpen, arrowEdge: .bottom) {
            NoteCard(
                heading: heading, detail: detail(), symbol: symbol ?? mark, footnote: footnote, link: link,
                linkTitle: linkTitle, caution: caution, isAlbum: isAlbum
            )
        }
    }
}

/// What a note says once something has opened it. Shared, so a note a badge raises reads exactly like one
/// raised by the circled i beside a title.
struct NoteCard: View {
    let heading: Text
    let detail: Text?
    var symbol: String?
    var footnote: Text?
    var link: URL?
    /// Already localized: the words the link goes by, in place of its address.
    var linkTitle: String?
    var caution: Text?
    var isAlbum = false

    static let width: CGFloat = 262

    private var tint: Color { noteTint(isAlbum: isAlbum) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Every card keeps the symbol's column, so the text is one width whichever note is open.
            Image(systemName: symbol ?? "info.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 5) {
                heading
                    .font(.headline)
                    .foregroundStyle(isAlbum ? Album.ink : .primary)
                if let detail {
                    detail
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let caution {
                    StatusLabel(title: caution, tint: tint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let footnote {
                    footnote
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 2)
                }
                if let link, let linkTitle {
                    LinkedText(Self.words(linkTitle, leadingTo: link))
                        .font(.callout)
                        .padding(.top, 2)
                } else if let link {
                    LinkedText(Self.address(link))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        // A macOS section header hands its children a one-line limit, and a note opened from a header
        // inherits it through the popover. A note answers a question, so it takes as many lines as the answer
        // needs, wherever it was opened from.
        .lineLimit(nil)
        .minimumScaleFactor(1)
        .truncationMode(.tail)
        .textCase(nil)
        .padding(14)
        .frame(width: Self.width, alignment: .leading)
        // Only the album's note is papered; a system popover brings its own material.
        .background(isAlbum ? Album.sheet : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(link == nil ? [] : .isLink)
    }

    /// The page without its scheme, as the note shows it.
    private static func address(_ url: URL) -> AttributedString {
        words("\(url.host() ?? "")\(url.path())", leadingTo: url)
    }

    private static func words(_ words: String, leadingTo url: URL) -> AttributedString {
        var linked = AttributedString(words)
        linked.link = url
        return linked
    }
}

private extension View {
    @ViewBuilder
    func noteButtonStyle(isInRow: Bool) -> some View {
        if isInRow {
            buttonStyle(RowButtonStyle())
        } else {
            buttonStyle(.plain)
        }
    }
}

/// Home keeps the album's orange; everywhere else a note takes the accent color the user chose.
private func noteTint(isAlbum: Bool) -> Color {
    isAlbum ? Album.orangeInk : .accentColor
}

/// A section's heading, with a note beside it holding what would otherwise be a paragraph under it.
func heading(_ title: LocalizedStringResource, _ detail: LocalizedStringResource) -> some View {
    titled(title, detail, isHeading: true)
}

/// A title with its note beside it, which is safe as a row's label: the label of a `LabeledContent` never acts
/// on the row.
func titled(_ title: LocalizedStringResource, _ detail: LocalizedStringResource, isHeading: Bool = false) -> some View {
    HStack(spacing: 5) {
        Text(title)
            .accessibilityAddTraits(isHeading ? .isHeader : [])
            .accessibilityHeading(isHeading ? .h2 : .unspecified)
        InfoNote(name: String(localized: title), detail: Text(detail))
    }
}
