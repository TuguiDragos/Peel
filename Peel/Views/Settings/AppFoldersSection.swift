import PeelCore
import SwiftUI
import UniformTypeIdentifiers

struct AppFoldersSection: View {
    @Environment(AppLibrary.self) private var library
    @State private var isChoosing = false
    @State private var selected: Set<URL> = []
    @State private var refused: [String] = []

    private var isShowingRefusal: Binding<Bool> {
        Binding(get: { !refused.isEmpty }, set: { if !$0 { refused = [] } })
    }

    var body: some View {
        Section {
            if library.folders.isEmpty {
                Text("No other folder is on this list yet.")
                    .foregroundStyle(.secondary)
            } else {
                List(selection: $selected) {
                    ForEach(library.folders, id: \.self) { folder in
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
                .frame(height: settingsListHeight(rows: library.folders.count))
                .scrollContentBackground(.hidden)
                .onDeleteCommand { removeSelected() }
            }
            if library.couldNotSaveFolders {
                WarningLabel(title: Text("Peel couldn’t save the app folders."))
            }
            HStack {
                Button("Add Folder…", systemImage: "plus") {
                    isChoosing = true
                }
                Spacer()
                Button("Remove", systemImage: "minus") { removeSelected() }
                    .disabled(selected.isEmpty)
            }
            .editingControls()
        } header: {
            titled("App Folders", "Peel looks for apps in the Applications folders and in the folders on this list, such as one on another disk. While that disk isn’t connected, its apps still count as installed, so their files aren’t listed as orphaned.")
        }
        .fileImporter(
            isPresented: $isChoosing, allowedContentTypes: [.folder], allowsMultipleSelection: true
        ) { result in
            guard let urls = try? result.get() else { return }
            let refusedURLs = urls.filter { AppFolders.refusal(of: $0) != nil }
            refused = refusedURLs.map(\.abbreviatedPath)
            let adding = urls.filter { !refusedURLs.contains($0) }
            guard !adding.isEmpty else { return }
            library.addFolders(adding)
        }
        .alert(refused.count == 1 ? "That folder can’t be added." : "These folders can’t be added.", isPresented: isShowingRefusal) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Peel already looks in the Applications folders, and a folder as wide as a whole disk, your home folder, or a Library would slow down every look for apps. Choose the folder that holds the apps.\n\n\(refused.joined(separator: "\n"))")
        }
    }

    private func removeSelected() {
        let removed = Array(selected)
        selected = []
        library.removeFolders(removed)
    }
}
