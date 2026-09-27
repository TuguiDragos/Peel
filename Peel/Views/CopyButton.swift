import Accessibility
import AppKit
import SwiftUI

/// A button that says it worked. Copying to the pasteboard changes nothing on screen, so without an answer
/// the only way to know it took is to paste somewhere and look.
struct CopyButton: View {
    let text: String
    var title: LocalizedStringResource = "Copy"

    /// Counted, so a second click while "Copied" shows starts its time again.
    @State private var copies = 0

    private var hasCopied: Bool { copies > 0 }

    var body: some View {
        Button {
            // The button exists to say the copy took, so it says so only when the pasteboard agrees.
            NSPasteboard.general.clearContents()
            copies = NSPasteboard.general.setString(text, forType: .string) ? copies + 1 : 0
            // VoiceOver does not read a title that changes under its cursor, so the copy is announced as well.
            if hasCopied {
                AccessibilityNotification.Announcement(AttributedString(localized: "Copied")).post()
            }
        } label: {
            Label {
                // Both words are laid out and one is drawn, so the button keeps its width.
                ZStack(alignment: .leading) {
                    Text(title)
                        .opacity(hasCopied ? 0 : 1)
                        .accessibilityHidden(hasCopied)
                    Text("Copied")
                        .opacity(hasCopied ? 1 : 0)
                        .accessibilityHidden(!hasCopied)
                }
            } icon: {
                Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
            }
            .contentTransition(.symbolEffect(.replace))
        }
        .motion(.step, value: hasCopied)
        // Tied to the state rather than to a timer, so leaving the page cancels it and coming back is clean.
        .task(id: copies) {
            guard hasCopied else { return }
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            copies = 0
        }
    }
}
