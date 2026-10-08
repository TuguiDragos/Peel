import SwiftUI

/// A warning or a state beside a setting or under a row. The symbol takes the color and the words keep the text's
/// own: a colored word reads under 4.5:1 on a light background, orange at about 2.3.
struct StatusLabel: View {
    let title: Text
    var systemImage = "exclamationmark.triangle"
    var tint: Color = .orange

    var body: some View {
        LeavesRowSeparatorAlone {
            Label {
                title
            } icon: {
                Image(systemName: systemImage)
                    .rowTint(tint)
            }
        }
    }
}
