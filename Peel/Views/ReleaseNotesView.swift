import PeelCore
import SwiftUI

/// What is new in a waiting update, as its notes say it: headings, paragraphs and lists, cut to a few lines with the
/// rest in a popover, so long notes never make the page longer.
struct ReleaseNotesView: View {
    let notes: ReleaseNotes
    /// The version the notes are for, which the popover is titled with.
    let version: String
    /// Shown at the end of the notes, beside Show More when they are cut.
    var link: ReleaseNotesLink?
    @State private var blocks: [ReleaseNotes.Block] = []
    @State private var isTall = false
    @State private var isShowingAll = false

    nonisolated private static let shortHeight: CGFloat = 132
    /// More blocks than the cut ever shows, since each is at least a line: only these are built on the page, so a long
    /// changelog doesn't put hundreds of views there.
    private static let shownBlocks = 10

    private var isLong: Bool {
        isTall || blocks.count > Self.shownBlocks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ReleaseNotesBlocks(blocks: blocks.prefix(Self.shownBlocks))
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: Bool.self) { $0.size.height > Self.shortHeight } action: { isTall = $0 }
                .frame(maxHeight: isLong ? Self.shortHeight : nil, alignment: .top)
                .clipped()
                .mask {
                    if isLong {
                        VStack(spacing: 0) {
                            Color.black
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: 28)
                        }
                    } else {
                        Color.black
                    }
                }
            if isLong || link != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if isLong {
                        Button {
                            isShowingAll = true
                        } label: {
                            Text("Show More\u{2026}")
                                .minimumTarget()
                        }
                        .buttonStyle(.link)
                        // A popover, not a sheet: a sheet dims the window, which makes SwiftUI measure every row on
                        // screen again as it opens and again as it closes.
                        .popover(isPresented: $isShowingAll, arrowEdge: .bottom) {
                            AllReleaseNotes(version: version, blocks: blocks)
                        }
                    }
                    Spacer(minLength: 8)
                    link
                }
            }
        }
        .font(.callout)
        // Reading HTML takes a moment, so it is read away from the page and only again when the notes change.
        .task(id: notes) {
            let notes = notes
            blocks = await Task.detached { notes.blocks }.value
        }
    }
}

/// Blocks of an update's notes, from the top. In a scroll view they are lazy, built as they come into sight.
private struct ReleaseNotesBlocks: View {
    let blocks: ArraySlice<ReleaseNotes.Block>
    var isLazy = false

    var body: some View {
        Group {
            if isLazy {
                LazyVStack(alignment: .leading, spacing: 6) { rows }
            } else {
                VStack(alignment: .leading, spacing: 6) { rows }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rows: some View {
        ForEach(blocks.indices, id: \.self) { index in
            switch blocks[index] {
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
}

/// All of an update's notes, in a popover as tall as they are up to a limit, past which they scroll. The link to
/// them stays beside Show More, under the notes the page shows.
private struct AllReleaseNotes: View {
    let version: String
    let blocks: [ReleaseNotes.Block]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What’s New in \(version)")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                ReleaseNotesBlocks(blocks: blocks[...], isLazy: true)
            }
            .frame(maxHeight: 400)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 440)
    }
}

/// Where an update's notes are on the web: the app's own page of release notes, or a cask's homepage.
struct ReleaseNotesLink: View {
    let url: URL
    let title: LocalizedStringResource

    var body: some View {
        Link(destination: url) {
            Text(title)
                .minimumTarget()
        }
        .fixedSize()
        .help(Text(verbatim: url.absoluteString))
    }
}
