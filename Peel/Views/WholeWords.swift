import SwiftUI

/// Measures a text's longest word in the surrounding font, without drawing it. A word is the language's own, with
/// the punctuation beside it, which a line never separates from it, so a view at least this wide wraps only between
/// words and never cuts one in two.
struct LongestWord: View {
    let text: String
    @Binding var width: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.words(in: text).enumerated()), id: \.offset) { _, word in
                Text(verbatim: word)
            }
        }
        .fixedSize()
        .hidden()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private static func words(in text: String) -> [String] {
        let isAttached = { (character: Character) in character.isPunctuation || character.isSymbol }
        var words: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, range, _, _ in
            var start = range.lowerBound, end = range.upperBound
            while start > text.startIndex, isAttached(text[text.index(before: start)]) {
                start = text.index(before: start)
            }
            while end < text.endIndex, isAttached(text[end]) { end = text.index(after: end) }
            words.append(String(text[start..<end]))
        }
        return words
    }
}

extension View {
    /// Keeps this view at least as wide as the longest word of `text` in its font, so no word is split.
    func keepsWordsWhole(_ text: String) -> some View {
        modifier(WholeWords(text: text))
    }
}

private struct WholeWords: ViewModifier {
    let text: String
    @State private var longest: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .frame(minWidth: ceil(longest))
            .background { LongestWord(text: text, width: $longest) }
    }
}
