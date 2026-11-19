import SwiftUI

/// Folders in a popover, each with its size when Peel knows it and Show in Finder, scrolling once they pass 320
/// points, then what more there is to know about them and Copy Details with every folder.
struct FolderListPopover: View {
    let folders: [URL]
    var sizes: [URL: Int64] = [:]
    var notes: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(folders, id: \.self) { folder in
                        HStack(spacing: 8) {
                            Text(verbatim: folder.abbreviatedPath)
                                .font(.callout)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let size = sizes[folder] {
                                Text(size.byteCount)
                                    .font(.callout)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            ShowInFinderButton(url: folder)
                        }
                    }
                }
            }
            .frame(maxHeight: 320)
            .fixedSize(horizontal: false, vertical: true)
            ForEach(notes, id: \.self) { note in
                Text(verbatim: note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                CopyButton(text: Self.details(of: folders, sizes: sizes), title: "Copy Details")
            }
        }
        .padding(14)
        .frame(width: 400)
    }

    /// Each folder on a line of its own, with its size when Peel knows it.
    static func details(of folders: [URL], sizes: [URL: Int64]) -> String {
        folders.map { folder in
            sizes[folder].map { String(localized: "\(folder.abbreviatedPath) (\($0.byteCount))") } ?? folder.abbreviatedPath
        }
        .joined(separator: "\n")
    }
}
