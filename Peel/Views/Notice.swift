import SwiftUI

/// A short notice on a page (a problem, a caution, or a note), with the actions that go with it.
///
/// On Home it is drawn as an album sticker. Everywhere else it looks like a system notice: a colored symbol,
/// system type, and a quiet rounded panel.
struct Notice<Actions: View>: View {
    /// The kind of notice, which sets its color and its symbol.
    enum Kind {
        /// What Peel cannot do until something is fixed.
        case problem
        /// What is worth a second look before going on.
        case caution
        /// What is simply true and nobody has to act on, like an extension macOS owns.
        case note
    }

    let title: Text
    let detail: Text
    var kind = Kind.problem
    /// A symbol to use instead of the default, such as the one a list row shows for the same fact.
    var systemImage: String?
    /// True on Home, which draws the notice in the album's look.
    var isAlbum = false
    @ViewBuilder let actions: Actions

    /// The narrowest the words may get beside the buttons. With less room, the buttons move under the words,
    /// so a narrow column doesn't break a long word in two.
    private static var wordsFloor: CGFloat { 200 }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                mark
                words
                    .frame(minWidth: Self.wordsFloor, idealWidth: Self.wordsFloor, maxWidth: .infinity, alignment: .leading)
                buttons
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    mark
                    words
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                buttons
                    .padding(.leading, 36)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .modifier(NoticeBackground(isAlbum: isAlbum))
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 1) {
            title
                .font(isAlbum ? .system(size: 12.5, weight: .bold, design: .rounded) : .callout.weight(.semibold))
                .foregroundStyle(titleColor)
            detail
                .font(isAlbum ? .system(size: 11) : .caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Bordered buttons outside the album, so a page's one prominent button stays its main action.
    @ViewBuilder
    private var buttons: some View {
        if isAlbum {
            actions
        } else {
            actions.buttonStyle(.bordered)
        }
    }

    /// Only a problem gets a colored title, in red. Orange text is too faint to read, and gray would look
    /// like the detail line under it.
    private var titleColor: Color {
        guard kind != .problem else { return isAlbum ? Album.red : .red }
        return isAlbum ? Album.ink : .primary
    }

    private var tint: Color {
        switch kind {
        case .problem: .red
        case .caution: .orange
        case .note: .secondary
        }
    }

    @ViewBuilder
    private var mark: some View {
        if isAlbum {
            // A caution or a note uses `Album.slot`, the quiet color of an empty permission slot. Red is kept
            // for problems.
            let isQuiet = kind != .problem
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isQuiet ? Album.slot : Album.redFill)
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: isQuiet ? "info" : "exclamationmark")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(isQuiet ? Color.secondary : .white)
                )
        } else {
            Image(systemName: systemImage ?? (kind == .note ? "info.circle.fill" : "exclamationmark.triangle.fill"))
                .font(.system(size: 16))
                .foregroundStyle(tint)
                .frame(width: 26)
        }
    }
}

/// The notice's panel: a sticker on Home, a rounded quaternary fill elsewhere. It is a modifier so it can
/// choose between `sticker()` and `background`, which return different view types.
private struct NoticeBackground: ViewModifier {
    let isAlbum: Bool

    func body(content: Content) -> some View {
        if isAlbum {
            content.sticker()
        } else {
            content.background(.quaternary, in: .rect(cornerRadius: 8))
        }
    }
}
