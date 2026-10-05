import PeelCore
import SwiftUI

/// What is new in a waiting update, as its notes say it: headings, paragraphs and lists, cut to a few lines until
/// the person asks for the rest.
struct ReleaseNotesView: View {
    let notes: ReleaseNotes
    @State private var blocks: [ReleaseNotes.Block] = []
    @State private var isLong = false
    @State private var isExpanded = false

    nonisolated private static let shortHeight: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: Bool.self) { $0.size.height > Self.shortHeight } action: { isLong = $0 }
                .frame(maxHeight: isLong && !isExpanded ? Self.shortHeight : nil, alignment: .top)
                .clipped()
                .mask {
                    if isLong && !isExpanded {
                        VStack(spacing: 0) {
                            Color.black
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: 28)
                        }
                    } else {
                        Color.black
                    }
                }
            if isLong {
                Button {
                    isExpanded.toggle()
                } label: {
                    Text(isExpanded ? "Show Less" : "Show More")
                        .minimumTarget()
                }
                .buttonStyle(.link)
            }
        }
        .font(.callout)
        .motion(value: isExpanded)
        // Reading HTML takes a moment, so it is read away from the page and only again when the notes change.
        .task(id: notes) {
            let notes = notes
            blocks = await Task.detached { notes.blocks }.value
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let words):
                    Text(words)
                        .fontWeight(.semibold)
                        .accessibilityAddTraits(.isHeader)
                case .paragraph(let words):
                    Text(words)
                case .item(let words, let depth):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: "•")
                            .accessibilityHidden(true)
                        Text(words)
                    }
                    .padding(.leading, CGFloat(depth) * 14)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The panel an app's page shows under its update: what is new in the version that waits, or, when no notes came
/// with the update, where the app says it.
struct ReleaseNotesBox: View {
    let version: String
    let notes: ReleaseNotes?
    let link: URL?
    let linkTitle: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("What’s New in \(version)")
                    .font(.callout.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let link {
                    Link(destination: link) {
                        Text(linkTitle)
                            .minimumTarget()
                    }
                    .font(.callout)
                    .help(Text(verbatim: link.absoluteString))
                }
            }
            if let notes {
                ReleaseNotesView(notes: notes)
            } else {
                Text("This update came with no notes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: .rect(cornerRadius: 8))
    }
}
