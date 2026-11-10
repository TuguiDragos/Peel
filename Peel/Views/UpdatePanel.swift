import PeelCore
import SwiftUI

/// The update an app waits for, in a panel of its own under the app: the version it brings, how to get it, and what
/// is new in it or where the app says so.
struct UpdatePanel<Detail: View, Action: View>: View {
    let version: String
    let notes: ReleaseNotesMemory.Standing
    let link: ReleaseNotesLink?
    @ViewBuilder let detail: Detail
    @ViewBuilder let action: Action

    var body: some View {
        HStack(alignment: .words, spacing: 12) {
            mark
            VStack(alignment: .leading, spacing: 12) {
                NoticeLayout(actionsGap: 12, actionsTop: 10) {
                    words
                    ActionRow { action }
                        .noticePart(.actions)
                }
                switch notes {
                case .found(let notes):
                    Divider()
                    ReleaseNotesView(notes: notes, version: version, link: link)
                case .notGiven where link != nil:
                    saying("This update came with no notes.")
                case .unanswered:
                    saying("Peel couldn’t get this update’s notes. It asks again later.")
                case .notGiven, .notAskedYet:
                    if let link {
                        HStack { Spacer(minLength: 8); link }
                            .font(.callout)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: .rect(cornerRadius: 8))
    }

    private var mark: some View {
        Image(systemName: "arrow.down.circle.fill")
            .font(.title)
            .foregroundStyle(Color.accentColor)
            .accessibilityHidden(true)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Update to \(version)")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            detail
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .alignmentGuide(.words) { $0[VerticalAlignment.center] }
    }

    /// A line on what is known of the notes, with the link to where the app tells of the update, when there is one.
    private func saying(_ sentence: LocalizedStringResource) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(sentence)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            link
        }
        .font(.callout)
    }
}

extension VerticalAlignment {
    /// The middle of an update panel's title and the line under it, which its mark lines up with.
    private enum Words: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    fileprivate static let words = VerticalAlignment(Words.self)
}
