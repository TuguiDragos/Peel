import SwiftUI

/// The header of a tool's page: the tool's symbol in a circle, the title with details under it, and usually
/// the page's total at the trailing edge.
struct PageHeader<Title: View, Details: View, Trailing: View>: View {
    let systemImage: String
    @ViewBuilder let title: Title
    @ViewBuilder let details: Details
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 76, height: 76)
                .background(.quaternary, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                title
                details
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 8)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(systemImage: String, @ViewBuilder title: () -> Title, @ViewBuilder details: () -> Details) {
        self.init(systemImage: systemImage, title: title, details: details, trailing: { EmptyView() })
    }
}

extension Text {
    /// Styles a page title that is a name, such as an app's: bold title type on one line (see `titleLine()`).
    func pageTitle() -> some View {
        font(.title.bold()).titleLine()
    }

    /// Styles a page title that is a phrase in the user's language. It wraps to a second line rather than
    /// being cut in the middle, which suits a name but not a phrase.
    func pageHeading() -> some View {
        font(.title.bold())
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
