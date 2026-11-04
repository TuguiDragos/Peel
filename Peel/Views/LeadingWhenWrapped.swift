import SwiftUI

extension LabeledContentStyle where Self == LeadingWhenWrapped {
    static var leadingWhenWrapped: LeadingWhenWrapped { LeadingWhenWrapped() }
}

/// A value beside its label while it fits, else under it from the leading edge, where a grouped form puts it at the
/// trailing one.
struct LeadingWhenWrapped: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                configuration.label
                Spacer(minLength: 0)
                configuration.content
            }
            VStack(alignment: .leading, spacing: 4) {
                configuration.label
                configuration.content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
