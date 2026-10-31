import PeelCore
import SwiftUI

/// The update an app waits for, in a panel of its own under the app: the version it brings, how to get it, and what
/// is new in it or where the app says so.
struct UpdatePanel<Detail: View, Action: View>: View {
    let version: String
    let notes: ReleaseNotes?
    let link: ReleaseNotesLink?
    @ViewBuilder let detail: Detail
    @ViewBuilder let action: Action

    /// The narrowest the words may get beside the button. With less room, the button moves under the words.
    private static var wordsFloor: CGFloat { 200 }

    var body: some View {
        HStack(alignment: .words, spacing: 12) {
            mark
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        words
                            .frame(
                                minWidth: Self.wordsFloor,
                                idealWidth: Self.wordsFloor,
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                        action
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        words
                        action
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let notes {
                    Divider()
                    ReleaseNotesView(notes: notes, version: version, link: link)
                } else if let link {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("This update came with no notes.")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        link
                    }
                    .font(.callout)
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
