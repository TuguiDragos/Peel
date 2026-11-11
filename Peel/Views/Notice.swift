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
    /// Nil when there is nothing to add, so the title stands alone in the middle of the panel.
    let detail: Text?
    var kind = Kind.problem
    /// A symbol to use instead of the default, such as the one a list row shows for the same fact.
    var systemImage: String?
    /// True on Home, which draws the notice in the album's look.
    var isAlbum = false
    @ViewBuilder let actions: Actions

    var body: some View {
        NoticeLayout(markGap: isAlbum ? 10 : 8) {
            mark
                .noticePart(.mark)
            title
                .font(isAlbum ? .system(size: 12.5, weight: .bold, design: .rounded) : .callout.weight(.semibold))
                .foregroundStyle(titleColor)
                .noticePart(.words)
            if let detail {
                detail
                    .font(isAlbum ? .system(size: 11) : .caption)
                    .foregroundStyle(.secondary)
                    .noticePart(.detail)
            }
            ActionRow { buttons }
                .noticePart(.actions)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .modifier(NoticeBackground(isAlbum: isAlbum))
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

    /// Only a problem's title takes a color, and only on Home, in the album's red. Elsewhere the red is the
    /// symbol's: red words read under the 4.5:1 text needs on a light background.
    private var titleColor: Color {
        guard isAlbum else { return .primary }
        return kind == .problem ? Album.red : Album.ink
    }

    private var tint: Color {
        switch kind {
        case .problem: .red
        case .caution: .orange
        case .note: .secondary
        }
    }

    /// The symbol VoiceOver hears for the notice's kind, Info or Warning, whichever symbol is drawn.
    private var kindSymbol: String {
        kind == .note ? "info.circle.fill" : "exclamationmark.triangle.fill"
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
                .accessibilityRepresentation { Image(systemName: kindSymbol) }
        } else {
            Image(systemName: systemImage ?? kindSymbol)
                .font(.system(size: 16))
                .foregroundStyle(tint)
                // At the panel's inset, as the buttons are on the other side; 24 holds the widest symbol, hammer.
                .frame(width: 24, alignment: .leading)
                .accessibilityRepresentation { Image(systemName: kindSymbol) }
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
