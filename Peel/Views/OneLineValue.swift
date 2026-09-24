import SwiftUI

extension LabeledContentStyle where Self == OneLineValue {
    /// Keeps a path, an identifier, or an address on one line beside its label, cut in the middle if too long.
    static var oneLine: OneLineValue { OneLineValue() }
}

/// A labeled value kept on one line beside its label. A grouped form moves a value that doesn't fit below
/// its label, where a long path or identifier can break in the middle of a word. Here the label keeps its
/// width, and the value is cut in the middle, where a path or an identifier says least.
struct OneLineValue: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            configuration.label
                .layoutPriority(1)
            Spacer(minLength: 0)
            configuration.content
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
        }
    }
}
