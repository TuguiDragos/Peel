import SwiftUI

/// The label of a menu in a toolbar. For VoiceOver, the toolbar names the menu after its symbol, which for some
/// symbols is the symbol's file name (such as "doc.badge.arrow.up") or a word that doesn't fit, so the symbol
/// is given the menu's title as its accessibility label.
struct ToolbarMenuLabel: View {
    let title: LocalizedStringResource
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .accessibilityLabel(Text(title))
        }
    }
}
