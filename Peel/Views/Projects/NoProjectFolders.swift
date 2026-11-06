import SwiftUI

/// What Build Artifacts shows before a folder is chosen: a button to choose one and, under it, the usual places for
/// projects on this Mac, a row each with its own Add.
struct NoProjectFolders: View {
    let suggested: [URL]
    let choose: () -> Void
    let add: (URL) -> Void

    var body: some View {
        VStack(spacing: 18) {
            ContentUnavailableView {
                Label("No Folders Yet", systemImage: "folder.badge.gearshape")
            } description: {
                Text("Choose where your projects live. Peel looks for what their builds left behind.")
            } actions: {
                Button("Choose a Folder…", action: choose)
                    .buttonStyle(.borderedProminent)
            }
            .fixedSize(horizontal: false, vertical: true)
            if !suggested.isEmpty {
                UsualProjectPlaces(folders: suggested, add: add)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The usual places for projects, in a list that scrolls once it holds more than the column has room for.
private struct UsualProjectPlaces: View {
    let folders: [URL]
    let add: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Usual Places for Projects")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.leading, 4)
            ViewThatFits(in: .vertical) {
                rows
                ScrollView { rows }
            }
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        }
        .padding(.horizontal, 16)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(folders.enumerated()), id: \.element) { index, folder in
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(verbatim: folder.abbreviatedPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(folder.fullPath)
                    Spacer(minLength: 8)
                    Button("Add") { add(folder) }
                        .accessibilityLabel(Text("Add “\(folder.lastPathComponent)”"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                if index < folders.count - 1 {
                    Divider()
                        .padding(.leading, 36)
                }
            }
        }
    }
}
