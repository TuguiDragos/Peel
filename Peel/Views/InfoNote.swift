import SwiftUI

/// A circled i beside a title. What would otherwise be paragraphs under the row lives in here instead.
struct InfoNote: View {
    /// Already localized: the heading of the note, and the name its accessibility label uses.
    let name: String
    /// Built when the note opens: a list draws hundreds of these, and few are ever opened.
    let detail: () -> Text
    var symbol: String?
    /// The technical line, when there is one worth keeping but not worth a row of its own.
    var footnote: Text?
    /// Draws the circle in the accent color, for a note holding something to know before acting.
    var isMarked = false
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

    init(
        name: String,
        detail: @autoclosure @escaping () -> Text,
        symbol: String? = nil,
        footnote: Text? = nil,
        isMarked: Bool = false,
        isAlbum: Bool = false,
        isInRow: Bool = false,
        opening: Binding<Bool>? = nil
    ) {
        self.name = name
        self.detail = detail
        self.symbol = symbol
        self.footnote = footnote
        self.isMarked = isMarked
        self.isAlbum = isAlbum
        self.isInRow = isInRow
        self.opening = opening
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
        .accessibilityLabel(isMarked ? Text("A caution about \(name)") : Text("What \(name) is for"))
        .popover(isPresented: isOpen, arrowEdge: .bottom) {
            NoteCard(name: name, detail: detail(), symbol: symbol ?? mark, footnote: footnote, isAlbum: isAlbum)
        }
    }
}

/// What a note says once something has opened it. Shared, so a note a badge raises reads exactly like one
/// raised by the circled i beside a title.
struct NoteCard: View {
    /// Already localized: the heading of the note.
    let name: String
    let detail: Text
    var symbol: String?
    var footnote: Text?
    var isAlbum = false

    private var tint: Color { noteTint(isAlbum: isAlbum) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Every card keeps the symbol's column, so the text is one width whichever note is open.
            Image(systemName: symbol ?? "info.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: name)
                    .font(.headline)
                    .foregroundStyle(isAlbum ? Album.ink : .primary)
                detail
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let footnote {
                    footnote
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
        .frame(width: 262, alignment: .leading)
        // Only the album's note is papered; a system popover brings its own material.
        .background(isAlbum ? Album.sheet : Color.clear)
        .accessibilityElement(children: .combine)
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
