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

/// A state said in a few words, with what more there is to know in a circled i beside it.
struct NotedStatus: View {
    let title: Text
    let note: Text?
    var tint: Color = .orange

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            StatusLabel(title: title, tint: tint)
            if let note {
                InfoNote(about: title, detail: note, isAlbum: false)
            }
        }
    }
}
