import SwiftUI

/// A small tag beside a row, saying what something is or what state it is in.
///
/// It has the system's look: caption type, a quiet filled capsule, and the tint carried by the text. Home
/// keeps the album's own marks; everything outside it reads as macOS.
struct Badge: View {
    let title: Text
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        Label {
            title
        } icon: {
            Image(systemName: systemImage)
        }
        // One line: a badge that doesn't fit goes to the next line of its row whole, and is cut only when it
        // is wider than the row itself.
        .lineLimit(1)
        .font(.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(.quaternary, in: .capsule)
    }
}

/// A badge that raises a question, so it opens a note with the answer, like the circled i beside a title.
struct NoteBadge: View {
    let title: Text
    let systemImage: String
    let tint: Color
    /// Already localized: the heading of the note.
    let name: String
    let detail: Text
    /// What VoiceOver reads for it, the title when there is nothing more to say.
    var label: Text?

    @State private var isOpen = false

    var body: some View {
        Button { isOpen = true } label: {
            Badge(title: title, systemImage: systemImage, tint: isOpen ? .accentColor : tint)
                .minimumTarget()
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .accessibilityLabel(label ?? title)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            NoteCard(name: name, detail: detail, symbol: systemImage)
        }
    }
}
