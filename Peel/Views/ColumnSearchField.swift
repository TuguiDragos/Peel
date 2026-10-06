import SwiftUI

/// A search field that lives in the column it filters, rather than in the window's title bar.
///
/// `searchable` hands its field to an `NSSearchToolbarItem`, which keeps the field on its own layout: a
/// width constraint set from outside is ignored at any priority, and the field is pinned to the trailing
/// edge of whichever title bar section owns it. A field of its own can sit above the list and span its width.
struct ColumnSearchField: View {
    @Binding var text: String
    let prompt: LocalizedStringResource
    var isAvailable = true

    @FocusState private var isFocused: Bool
    @State private var isRequested = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(text: $text) { Text(prompt) }
                .textFieldStyle(.plain)
                .focused($isFocused)
                // What `NSSearchField` does with Escape: the text goes, and a second press gives the field up.
                .onExitCommand {
                    if text.isEmpty {
                        isFocused = false
                    } else {
                        text = ""
                    }
                }
                // `searchable` marks its field as a search field; a plain text field in a drawn box isn't marked.
                .accessibilityAddTraits(.isSearchField)
                .accessibilityLabel(Text(prompt))
            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                // As in `InfoNote`: clicks land 4 points around the glyph, and the layout keeps the glyph's size.
                .padding(-4)
                .help(Text("Clear the search"))
                .accessibilityLabel(Text("Clear the search"))
            }
        }
        .font(.body)
        .padding(.horizontal, 10)
        .frame(height: 24)
        // Glass, as the system's own search field is: the list scrolls under it, and a flat fill would let the
        // rows' text show through the prompt.
        .glassEffect(.regular, in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(isFocused ? 1 : 0)
        }
        .motion(.touch, value: isFocused)
        .opacity(isAvailable ? 1 : 0)
        .disabled(!isAvailable)
        .accessibilityHidden(!isAvailable)
        .motion(value: isAvailable)
        // Read by ⌘F in the Edit menu.
        .focusedSceneValue(\.searchField, isAvailable ? $isRequested : nil)
        .onChange(of: isRequested) { _, wants in
            guard wants else { return }
            isFocused = true
            isRequested = false
        }
    }
}

extension View {
    /// Puts a search field across the top of this column. `when` must come from the unfiltered rows: from the
    /// filtered ones, a query that matched nothing would hide the field and leave no way to clear it. While
    /// `when` is false, the field is hidden but keeps its place.
    func columnSearch(text: Binding<String>, prompt: LocalizedStringResource, when hasRows: Bool) -> some View {
        edgeBar(.top) {
            ColumnSearchField(text: text, prompt: prompt, isAvailable: hasRows)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }
}
