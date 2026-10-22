import PeelCore
import SwiftUI
import UniformTypeIdentifiers

struct AppFoldersSection: View {
    @Environment(AppLibrary.self) private var library
    @State private var isChoosing = false
    @State private var selected: Set<URL> = []
    @State private var refused: [String] = []
    @State private var refusedInATrash: [String] = []

    private var isShowingRefusal: Binding<Bool> {
        Binding(
            get: { !refused.isEmpty || !refusedInATrash.isEmpty },
            set: {
                guard !$0 else { return }
                refused = []
                refusedInATrash = []
            }
        )
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
                HStack {
                    StatusLabel(title: Text("Peel can’t read its list of app folders, so Orphaned Files lists nothing. Starting over keeps the old list beside a new one."))
                    Spacer()
                    Button("Start Over") { library.startFoldersOver() }
                }
            }
            if library.couldNotSaveFolders {
                StatusLabel(title: Text("Peel couldn’t save the app folders."))
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
            let refusals = urls.compactMap { url in AppFolders.refusal(of: url).map { (url: url, refusal: $0) } }
            refused = refusals.filter { $0.refusal != .inATrash }.map(\.url.abbreviatedPath)
            refusedInATrash = refusals.filter { $0.refusal == .inATrash }.map(\.url.abbreviatedPath)
            let adding = urls.filter { url in !refusals.contains { $0.url == url } }
            guard !adding.isEmpty else { return }
            library.addFolders(adding)
        }
        .alert(
            refused.count + refusedInATrash.count == 1 ? "That folder can’t be added." : "These folders can’t be added.",
            isPresented: isShowingRefusal
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            refusalMessage
        }
    }

    private var refusalMessage: Text {
        let others = Text("Peel already looks in the Applications folders, and a folder as wide as a whole disk, your home folder, or a Library would slow down every look for apps. Choose the folder that holds the apps.\n\n\(RemovalFailureAlert.firstItems(refused).joined(separator: "\n"))")
        let inATrash = Text("The Trash holds what is on its way out, so Peel doesn’t look for apps there.\n\n\(RemovalFailureAlert.firstItems(refusedInATrash).joined(separator: "\n"))")
        switch (refused.isEmpty, refusedInATrash.isEmpty) {
        case (false, true): return others
        case (true, false): return inATrash
        default: return Text("\(others)\n\n\(inATrash)")
        }
    }

    private func removeSelected() {
        let removed = Array(selected)
        selected = []
        library.removeFolders(removed)
    }
}
