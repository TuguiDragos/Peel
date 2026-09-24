import SwiftUI

/// A list section's header: the heading at one end, and the count and the section's buttons at the other. A
/// macOS section header limits its children to one line, so when everything doesn't fit, the count is dropped
/// first, and then the heading wraps to a second line. The buttons always stay: nothing else on the page does
/// what Select All or Upgrade All does.
struct SectionHeaderLine<Heading: View, Count: View, Actions: View>: View {
    @ViewBuilder let heading: Heading
    @ViewBuilder let count: Count
    @ViewBuilder let actions: Actions

    var body: some View {
        ViewThatFits(in: .horizontal) {
            line(heading) {
                count
                actions
            }
            line(heading) { actions }
            line(heading.lineLimit(2).fixedSize(horizontal: false, vertical: true)) { actions }
        }
    }

    private func line(_ heading: some View, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 8) {
            heading
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension SectionHeaderLine where Count == EmptyView {
    init(@ViewBuilder heading: () -> Heading, @ViewBuilder actions: () -> Actions) {
        self.init(heading: heading, count: { EmptyView() }, actions: actions)
    }
}
