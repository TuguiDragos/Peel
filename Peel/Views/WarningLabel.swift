import SwiftUI

/// A warning beside a setting or under a row. The symbol takes the warning's color and the words keep the text's
/// own: orange words read at about 2.3 to 1 on a light background, under the 4.5 to 1 text needs.
struct WarningLabel: View {
    let title: Text
    var systemImage = "exclamationmark.triangle"

    var body: some View {
        Label {
            title
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
        }
    }
}
