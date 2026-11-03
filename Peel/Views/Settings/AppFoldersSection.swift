import PeelCore
import SwiftUI
import UniformTypeIdentifiers

struct AppFoldersSection: View {
    @Environment(AppLibrary.self) private var library
    @State private var isChoosing = false
    @State private var selected: Set<URL> = []
    @State private var refused: [AppFolders.LeftOut] = []

    private var isShowingRefusal: Binding<Bool> {
        Binding(get: { !refused.isEmpty }, set: { if !$0 { refused = [] } })
    }

    var body: some View {
        Section {
            if let folders = library.folders, !folders.isEmpty {
                List(selection: $selected) {
                    ForEach(folders, id: \.self) { folder in
                        HStack(spacing: 8) {
                            AppIcon(url: folder)
                                .frame(width: 16, height: 16)
                            Text(folder.abbreviatedPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .tag(folder)
                    }
                }
                .frame(height: settingsListHeight(rows: folders.count))
                .scrollContentBackground(.hidden)
                .onDeleteCommand { removeSelected() }
            } else if library.folders != nil {
                Text("No other folder is on this list yet.")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    StatusLabel(title: Text(verbatim: library.unreadableListOfFolders(saying: String(localized: "Peel can’t read its list of app folders, so Orphaned Files lists nothing. Starting over keeps the old list beside a new one."))))
                    Spacer(minLength: 8)
                    StartOverButton(file: library.foldersFile, startedOver: "Started the list of app folders over.") {
                        library.startFoldersOver()
                    }
                }
            }
            if !library.foldersLeftOut.isEmpty {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        StatusLabel(title: Text("Peel no longer looks in these folders, so the apps in them aren’t listed."))
                        Self.message(for: library.foldersLeftOut)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 8)
                    Button("Remove From List") { library.removeFolders(library.foldersLeftOut.map(\.folder)) }
                }
            }
            if library.couldNotSaveFolders {
                StatusLabel(title: Text(verbatim: library.foldersNotSaved))
            }
            ListEditingButtons {
                Button("Add Folder…", systemImage: "plus") {
                    isChoosing = true
                }
                .help(Text("Add Folder…"))
                Button("Remove", systemImage: "minus") { removeSelected() }
                    .disabled(selected.isEmpty)
                    .help(Text("Remove"))
            }
        } header: {
            titled("App Folders", "Peel looks for apps in the Applications folders and in the folders on this list, such as one on another disk. While that disk isn’t connected, its apps still count as installed, so their files aren’t listed as orphaned.")
        }
        .fileImporter(
            isPresented: $isChoosing, allowedContentTypes: [.folder], allowsMultipleSelection: true
        ) { result in
            guard let urls = try? result.get() else { return }
            refused = urls.compactMap { url in AppFolders.refusal(of: url).map { .init(folder: url, refusal: $0) } }
            let adding = urls.filter { url in !refused.contains { $0.folder == url } }
            guard !adding.isEmpty else { return }
            library.addFolders(adding)
        }
        .alert(
            refused.count == 1 ? "That folder can’t be added." : "These folders can’t be added.",
            isPresented: isShowingRefusal
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Self.message(for: refused)
        }
    }

    /// Why each of `folders` isn't taken, a paragraph for each reason, with the folders it holds for.
    private static func message(for folders: [AppFolders.LeftOut]) -> Text {
        func paths(_ refusal: AppFolders.Refusal) -> [String] {
            folders.filter { $0.refusal == refusal }.map(\.folder.abbreviatedPath)
        }
        func named(_ refusal: AppFolders.Refusal) -> String {
            RemovalFailureAlert.firstItems(paths(refusal)).joined(separator: "\n")
        }
        let parts = [
            (paths(.tooBroad), Text("A folder as wide as a whole disk, your home folder, a Library, or one of macOS’s own would slow down every look for apps. Choose the folder that holds the apps.\n\n\(named(.tooBroad))")),
            (paths(.alreadyLookedIn), Text("Peel already looks in the Applications folders and in the folders inside them, three levels deep.\n\n\(named(.alreadyLookedIn))")),
            (paths(.inATrash), Text("The Trash holds what is on its way out, so Peel doesn’t look for apps there.\n\n\(named(.inATrash))")),
            (paths(.inTheCloud), Text("Reading a folder that iCloud or another cloud keeps can download what it holds, so Peel doesn’t look for apps there.\n\n\(named(.inTheCloud))")),
        ]
            .filter { !$0.0.isEmpty }.map(\.1)
        return parts.dropFirst().reduce(parts.first ?? Text(verbatim: "")) { Text("\($0)\n\n\($1)") }
    }

    private func removeSelected() {
        let removed = Array(selected)
        selected = []
        library.removeFolders(removed)
    }
}
