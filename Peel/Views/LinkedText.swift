import SwiftUI

/// A sentence with a link in it. macOS gives a link inside a `Text` no press for VoiceOver and no keyboard focus, so
/// the sentence takes both and opens its link, as a click on the link does.
struct LinkedText: View {
    @Environment(\.openURL) private var openURL
    private let words: AttributedString
    private let link: URL?
    /// How far the sentence reaches above and below its line, for the pointer and VoiceOver alike. The layout gives
    /// it back, so the spacing stays as it was.
    private let reach: CGFloat

    init(_ sentence: LocalizedStringResource, reach: CGFloat = 0) {
        self.init(AttributedString(localized: sentence), reach: reach)
    }

    init(_ words: AttributedString, reach: CGFloat = 0) {
        self.words = words
        link = words.runs.lazy.compactMap(\.link).first
        self.reach = reach
    }

    var body: some View {
        Text(words)
            .padding(.vertical, reach)
            .contentShape(.rect)
            // As a button does, it takes focus only while keyboard navigation is on.
            .focusable(link != nil, interactions: .activate)
            .onKeyPress(.space, phases: .down) { _ in open() ? .handled : .ignored }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: String(words.characters)))
            .accessibilityAddTraits(link == nil ? [] : .isLink)
            .accessibilityAction { _ = open() }
            .padding(.vertical, -reach)
    }

    private func open() -> Bool {
        guard let link else { return false }
        openURL(link)
        return true
    }
}
