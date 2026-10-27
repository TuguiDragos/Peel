import PeelCore
import SwiftUI
import UniformTypeIdentifiers

struct AppFoldersSection: View {
    @Environment(AppLibrary.self) private var library
    @State private var isChoosing = false
    @State private var selected: Set<URL> = []
    @State private var refusedAsTooBroad: [String] = []
    @State private var refusedAsLookedIn: [String] = []
    @State private var refusedInATrash: [String] = []
    @State private var refusedInTheCloud: [String] = []

    private var isShowingRefusal: Binding<Bool> {
        Binding(
            get: { !(refusedAsTooBroad + refusedAsLookedIn + refusedInATrash + refusedInTheCloud).isEmpty },
            set: {
                guard !$0 else { return }
                refusedAsTooBroad = []
                refusedAsLookedIn = []
                refusedInATrash = []
                refusedInTheCloud = []
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
                    StartOverButton(file: AppFolders.defaultURL, startedOver: "Started the list of app folders over.") {
                        library.startFoldersOver()
                    }
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
            refusedAsTooBroad = refusals.filter { $0.refusal == .tooBroad }.map(\.url.abbreviatedPath)
            refusedAsLookedIn = refusals.filter { $0.refusal == .alreadyLookedIn }.map(\.url.abbreviatedPath)
            refusedInATrash = refusals.filter { $0.refusal == .inATrash }.map(\.url.abbreviatedPath)
            refusedInTheCloud = refusals.filter { $0.refusal == .inTheCloud }.map(\.url.abbreviatedPath)
            let adding = urls.filter { url in !refusals.contains { $0.url == url } }
            guard !adding.isEmpty else { return }
            library.addFolders(adding)
        }
        .alert(
            (refusedAsTooBroad + refusedAsLookedIn + refusedInATrash + refusedInTheCloud).count == 1
                ? "That folder can’t be added." : "These folders can’t be added.",
            isPresented: isShowingRefusal
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            refusalMessage
        }
    }

    private var refusalMessage: Text {
        let tooBroad = Text("A folder as wide as a whole disk, your home folder, a Library, or one of macOS’s own would slow down every look for apps. Choose the folder that holds the apps.\n\n\(RemovalFailureAlert.firstItems(refusedAsTooBroad).joined(separator: "\n"))")
        let lookedIn = Text("Peel already looks in the Applications folders and in the folders inside them, three levels deep.\n\n\(RemovalFailureAlert.firstItems(refusedAsLookedIn).joined(separator: "\n"))")
        let inATrash = Text("The Trash holds what is on its way out, so Peel doesn’t look for apps there.\n\n\(RemovalFailureAlert.firstItems(refusedInATrash).joined(separator: "\n"))")
        let inTheCloud = Text("Reading a folder that iCloud or another cloud keeps can download what it holds, so Peel doesn’t look for apps there.\n\n\(RemovalFailureAlert.firstItems(refusedInTheCloud).joined(separator: "\n"))")
        let parts = [
            (refusedAsTooBroad, tooBroad), (refusedAsLookedIn, lookedIn), (refusedInATrash, inATrash),
            (refusedInTheCloud, inTheCloud),
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
