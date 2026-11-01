import SwiftUI

/// A section's heading with the section's buttons beside it, at the right, for a section that holds nothing else. Where
/// a language's words leave no room on one line, the buttons go under the heading.
struct HeadingWithActions<Heading: View, Actions: View>: View {
    @ViewBuilder let heading: Heading
    @ViewBuilder let actions: Actions

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                heading
                Spacer(minLength: 8)
                actions
            }
            VStack(alignment: .leading, spacing: 8) {
                heading
                ActionRow { actions }
            }
        }
    }
}
