import SwiftUI

extension View {
    /// Centers this on a surface that covers its column from top to bottom.
    ///
    /// The empty list is that surface. A pane whose root is a plain view paints nothing of its own, so the
    /// surface changes at the title bar, and that edge reads as a line across the pane. A scroll view with its
    /// background hidden covers the whole column instead, so no line shows.
    func centeredOnColumn() -> some View {
        List {}
            .scrollContentBackground(.hidden)
            .overlay { self }
    }
}

/// What a detail pane shows when nothing is selected. Every tool uses this one view, so an empty pane reads
/// the same everywhere.
struct DetailPlaceholder: View {
    let title: LocalizedStringResource
    let systemImage: String
    let description: LocalizedStringResource?
    /// What the tool holds, in numbers, before anything is chosen. The detail column is the widest in the
    /// window, and a pane that only says "choose something" spends it on what the list beside it already says.
    var summary: Text?

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
            }
        } description: {
            if let summary {
                VStack(spacing: 10) {
                    summary
                        .foregroundStyle(.primary)
                    if let description {
                        Text(description)
                    }
                }
            } else if let description {
                Text(description)
            }
        }
        .centeredOnColumn()
    }
}

extension DetailPlaceholder {
    /// A tool's own pane: its name, what it holds, and the instruction only when there is something to choose.
    init(tool: Tool, summary: AttributedString?, instruction: LocalizedStringResource) {
        self.init(title: tool.title, systemImage: tool.systemImage, description: summary == nil ? nil : instruction, summary: summary.map { Text($0) })
    }
}
