import SwiftUI

struct RemovalRow: View {
    enum Icon {
        case symbol(String)
        case file(URL)
    }

    let url: URL
    let icon: Icon
    let detail: LocalizedStringResource?
    /// The kind of item, shown in a column of its own. Tools with nothing to show there pass nil, and the
    /// column is left out.
    var kind: LocalizedStringResource?
    var warning: String?
    /// The newest write inside the item, which its note tells when the page knows it.
    var lastWritten: Date?
    /// On a page that lists several apps' files, the apps the item was found for, named first in its note.
    var foundFor: String?
    let size: Int64
    /// False when the size is not known, such as for a folder that did not answer in time. The row then
    /// reads "Unknown", never zero.
    var isMeasured = true
    var isLocked = false
    var isExcluded = false
    /// True for an item that is shown but can never be moved. The note beside the row says why.
    var isLeftAlone = false
    /// The app's bundle identifier, when the row is an app. The row's menu excludes an app by its
    /// identifier, as Settings does.
    var appIdentifier: String?
    var isFirst = false
    /// False when no row of the table has a note. The note column is then left out, so the sizes end at the
    /// same edge as the page's totals and Select All.
    var hasNoteColumn = true
    /// A click on the row chooses it for the detail column, and only the checkbox selects the item.
    var isChoosable = false
    /// The object the checkbox writes to. A `Binding` here would rebuild every row in the list: see `RowSelection`.
    let selection: any RowSelection
    let isSelected: Bool

    static let controlWidth: CGFloat = 20
    /// The least width a path keeps. With less, the kind and size move under the path, and so does the badge.
    private static let pathFloor: CGFloat = 160
    /// The width of a row's fixed parts: the checkbox, the icon, the note, and the gaps between them.
    private static let fixedParts: CGFloat = 86

    /// The width below which a table moves each row's kind and size to a second line. Every row and the
    /// column headers compare it with their own width, which is the list's, so the whole table switches at once.
    static func compactBelow(hasKind: Bool) -> CGFloat {
        fixedParts + pathFloor + RowColumns.size + (hasKind ? RowColumns.kind + 10 : 0)
    }

    @State private var isCompact = false
    @State private var isNoteOpen = false

    private var hasNote: Bool {
        hasNoteColumn && hasExplanation
    }

    private var hasExplanation: Bool {
        detail != nil || warning != nil || lastWritten != nil
    }

    var body: some View {
        HStack(spacing: 6) {
            checkboxAndItem
            if hasNoteColumn {
                note
            }
        }
        .tableRow(isFirst: isFirst)
        .onGeometryChange(for: Bool.self) { [limit = Self.compactBelow(hasKind: kind != nil)] proxy in
            proxy.size.width < limit
        } action: { isCompact = $0 }
        .contextMenu {
            ItemMenu(url: url, appIdentifier: appIdentifier, isExcluded: isExcluded, showNote: hasNote ? { isNoteOpen = true } : nil)
        }
    }

    private var checkboxAndItem: some View {
        HStack(alignment: .checkboxTitleLine, spacing: 5) {
            NativeCheckbox(
                isOn: Binding(get: { isSelected }, set: { selection.setSelected($0, for: url) }),
                label: spokenItem,
                // What the note says, since its button takes no keyboard focus.
                hint: hasExplanation ? String(explanation.characters) : nil
            )
            clickableItem
                .checkboxTitle()
                // The checkbox's label already reads the item.
                .accessibilityHidden(true)
        }
        .disabled(isLocked || isExcluded || isLeftAlone)
    }

    @ViewBuilder
    private var clickableItem: some View {
        if isChoosable {
            item
        } else {
            item
                .contentShape(.rect)
                .onTapGesture { selection.setSelected(!isSelected, for: url) }
        }
    }

    private var spokenItem: String {
        let badge = badgeKind.map { String(localized: $0.title) }
        let size = isMeasured ? size.byteCount : String(localized: "Unknown")
        return [url.abbreviatedPath, badge, kind.map { String(localized: $0) }, size]
            .compactMap(\.self)
            .joined(separator: ", ")
    }

    @ViewBuilder
    private var item: some View {
        if isCompact {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                iconView
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    pathAndBadge
                    HStack(spacing: 8) {
                        if let kind {
                            Text(kind)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        sizeText
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                iconView
                    .frame(width: 20)
                pathAndBadge
                if let kind {
                    Text(kind)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: RowColumns.kind, alignment: .leading)
                        .help(Text(kind))
                }
                sizeText
                    .foregroundStyle(.secondary)
                    .frame(width: RowColumns.size, alignment: .trailing)
            }
        }
    }

    private var path: some View {
        Text(url.abbreviatedPath)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(Text(verbatim: url.path(percentEncoded: false)))
            .checkboxTitleLine()
    }

    /// The path with its badge beside it, or under it when the path would get less than `pathFloor`.
    @ViewBuilder
    private var pathAndBadge: some View {
        if isExcluded || isLeftAlone || isLocked {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    path
                        .frame(minWidth: 0, idealWidth: Self.pathFloor, maxWidth: .infinity, alignment: .leading)
                    badge
                }
                VStack(alignment: .leading, spacing: 2) {
                    path
                        .frame(maxWidth: .infinity, alignment: .leading)
                    badge
                }
            }
        } else {
            path
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Why the row's checkbox can't be selected, which would otherwise look like a fault, as its badge says it.
    private var badgeKind: (title: LocalizedStringResource, symbol: String)? {
        if isExcluded { return ("Excluded in Settings", "hand.raised.fill") }
        if isLeftAlone { return ("Left alone", "hand.raised") }
        if isLocked { return ("Needs administrator access", "lock.fill") }
        return nil
    }

    /// Never cut, so the path is what gets shortened instead.
    private var badge: some View {
        Group {
            if let badgeKind {
                Badge(title: Text(badgeKind.title), systemImage: badgeKind.symbol)
            }
        }
        .fixedSize()
    }

    /// A `Text`, so `.secondary` applies to the text itself. Applied to a view in a disabled row, it would dim
    /// the row's already dimmed color, and the size would be hard to see.
    private var sizeText: Text {
        (isMeasured ? Text(size.byteCount) : Text("Unknown"))
            .monospacedDigit()
    }

    /// The info button at the end of the row. Its note holds the detail, the warning, and the full path,
    /// which the row cuts short. It sits outside the toggle on purpose: a checkbox makes its whole label
    /// one button, and this would be a button inside a button.
    private var note: some View {
        noteButton.frame(width: Self.controlWidth)
    }

    @ViewBuilder
    private var noteButton: some View {
        if hasExplanation {
            InfoNote(
                name: url.lastPathComponent,
                detail: Text(explanation),
                footnote: Text(verbatim: url.path(percentEncoded: false)),
                isMarked: warning != nil,
                isInRow: true,
                opening: $isNoteOpen
            )
        } else {
            blank
        }
    }

    private var explanation: AttributedString {
        var text = AttributedString()
        if let foundFor {
            text += AttributedString(String(localized: "Found for \(foundFor)"))
            if detail != nil {
                text += AttributedString("\n\n")
            }
        }
        if let detail {
            text += AttributedString(String(localized: detail))
        }
        if let lastWritten {
            let written = String(localized: "Last changed \(lastWritten, format: .relative(presentation: .named))")
            text += AttributedString(text.characters.isEmpty ? written : "\n\n\(written)")
        }
        if let warning {
            var marked = Self.commandsMarked(text.characters.isEmpty ? warning : "\n\n\(warning)")
            marked.foregroundColor = Color.accentColor
            text += marked
        }
        return text
    }

    /// Marks the text between backticks as code, as `Text` does, and keeps the rest as written. It doesn't
    /// parse Markdown, because a path in a warning can hold characters Markdown would read as emphasis.
    private static func commandsMarked(_ string: String) -> AttributedString {
        var text = AttributedString()
        for (index, part) in string.split(separator: "`", omittingEmptySubsequences: false).enumerated() {
            var run = AttributedString(part)
            if !index.isMultiple(of: 2) {
                run.inlinePresentationIntent = .code
            }
            text += run
        }
        return text
    }

    /// Fills the note's slot in a row without a note, so the sizes still line up in a column. A frame on an
    /// empty branch takes no space, and the row's size would sit further right.
    private var blank: some View {
        Color.clear.frame(width: Self.controlWidth, height: 1)
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .foregroundStyle(.secondary)
        case .file(let url):
            AppIcon(url: url)
                .frame(width: 18, height: 18)
                // Centers the icon on the first line of text.
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
        }
    }
}

extension View {
    /// Lays out a row of a removal table, with a divider above every row but the first in place of the list's
    /// own separators. The `ForEach` that lists the rows hides those separators, never the row itself: a repeated
    /// row that hides its own separator, or that is itself a `Toggle`, makes `List` build far more rows than are
    /// on screen as soon as it appears. A row that stands alone, such as the column headers, costs nothing.
    func tableRow(isFirst: Bool) -> some View {
        padding(.vertical, 4)
            .overlay(alignment: .top) {
                if !isFirst {
                    Divider().padding(.top, -4)
                }
            }
    }
}

/// The column headers of a removal table: Item, Kind, and Size. "Item" sits at the leading edge, as Finder's
/// Name header does, and the other two use the rows' own column widths so they line up.
struct RemovalColumnHeaders: View {
    /// Matches the rows below. Without the note column, the headers end where the sizes do.
    var hasNoteColumn = true
    /// True when the rows below show their kind and size under the path, so those headers are hidden.
    @State private var isCompact = false

    var body: some View {
        HStack(spacing: 0) {
            Text("Item")
            Spacer(minLength: 12)
            if !isCompact {
                // The same gaps as the row (10 points between kind and size, 6 before the note), so each header
                // lines up with its column.
                HStack(spacing: 10) {
                    Text("Kind")
                        .frame(width: RowColumns.kind, alignment: .leading)
                    Text("Size")
                        .frame(width: RowColumns.size, alignment: .trailing)
                }
                if hasNoteColumn {
                    Color.clear
                        .frame(width: RemovalRow.controlWidth + 6, height: 1)
                }
            }
        }
        .onGeometryChange(for: Bool.self) { [limit = RemovalRow.compactBelow(hasKind: true)] proxy in
            proxy.size.width < limit
        } action: { isCompact = $0 }
        .font(.caption.weight(.semibold))
        .textCase(.uppercase)
        .tracking(0.4)
        .foregroundStyle(.secondary)
        .padding(.bottom, 3)
        .listRowSeparator(.hidden)
        .accessibilityHidden(true)
    }
}

