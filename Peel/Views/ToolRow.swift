import SwiftUI

/// A row in a tool's list: its symbol in a small circle, the title with details under it, and a figure or a
/// mark at the trailing edge.
struct ToolRow<Title: View, Details: View, Trailing: View>: View {
    let systemImage: String
    /// What VoiceOver says of the symbol when it tells something the row's words don't, such as an item's kind.
    var symbolName: LocalizedStringResource?
    @ViewBuilder let title: Title
    @ViewBuilder let details: Details
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(.quaternary, in: .circle)
                .accessibilityLabel(symbolName.map { Text($0) } ?? Text(verbatim: ""))
                .accessibilityHidden(symbolName == nil)
            VStack(alignment: .leading, spacing: 1) {
                title
                details
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            trailing
        }
        .padding(.vertical, 2)
    }
}

extension ToolRow where Trailing == EmptyView {
    init(
        systemImage: String,
        symbolName: LocalizedStringResource? = nil,
        @ViewBuilder title: () -> Title,
        @ViewBuilder details: () -> Details
    ) {
        self.init(
            systemImage: systemImage, symbolName: symbolName, title: title, details: details, trailing: { EmptyView() }
        )
    }
}

extension View {
    /// Styles the size or count at a row's trailing edge, with monospaced digits so the figures line up.
    func rowFigure() -> some View {
        font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
    }
}
