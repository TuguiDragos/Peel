import AppKit
import PeelCore
import SwiftUI

/// One file a search found: where it is and what Peel knows about moving it.
struct FileSearchFileView: View {
    let file: FoundFile

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 18) {
                    AppIcon(url: file.url)
                        .frame(width: 64, height: 64)
                    Text(verbatim: file.url.lastPathComponent)
                        .pageTitle()
                        .help(Text(verbatim: file.url.lastPathComponent))
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
            }

            Section {
                LabeledContent("Where") {
                    Text(verbatim: file.url.abbreviatedPath)
                        .textSelection(.enabled)
                        .help(Text(verbatim: file.url.path(percentEncoded: false)))
                }
                .labeledContentStyle(.oneLine)
                LabeledContent("Size") {
                    Text(file.size.byteCount).monospacedDigit()
                }
                LabeledContent("Modified") {
                    Text(file.modificationDate, format: .relative(presentation: .named))
                }
                if file.isInTheCloud {
                    Text("This file is in iCloud Drive, so moving it to the Trash removes it from iCloud and from your other devices.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if file.belongsToAnApp {
                    Text("An app keeps this in its Library folder, and may be using it right now.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if file.requiresPrivileges {
                    Text("Needs administrator access")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Details")
            }

            Section {
                HStack {
                    Spacer()
                    Button("Show in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([file.url])
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text(verbatim: file.url.lastPathComponent))
        .toolbar(removing: .title)
    }
}
