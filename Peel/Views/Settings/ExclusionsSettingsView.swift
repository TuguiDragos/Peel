import PeelCore
import SwiftUI
import UniformTypeIdentifiers

struct ExclusionsSettingsView: View {
    @Environment(ExclusionsStore.self) private var exclusions
    @Environment(AppLibrary.self) private var library
    @Environment(OrphanLibrary.self) private var orphans
    @State private var isChoosingPaths = false
    @State private var refused: [String] = []
    @State private var selectedPaths: Set<URL> = []
    @State private var selectedApps: Set<String> = []
    @State private var selectedGroups: Set<String> = []

    private var paths: [URL] {
        exclusions.exclusions.paths.sorted { $0.path(percentEncoded: false) < $1.path(percentEncoded: false) }
    }

    private var apps: [String] {
        exclusions.exclusions.bundleIdentifiers.sorted()
    }

    private var isShowingRefusal: Binding<Bool> {
        Binding(get: { !refused.isEmpty }, set: { if !$0 { refused = [] } })
    }

    var body: some View {
        Form {
            if exclusions.exclusions.isUnreadable {
                Notice(
                    title: Text("Peel couldn’t read your exclusions"),
                    detail: Text("Until it can read them, or you start over, Peel removes nothing and puts nothing back, because it can’t tell what you asked it to leave alone. Adding or removing an entry below starts over too: the old file is kept beside the new one, but nothing in it counts anymore.")
                ) {
                    Button("Start Over") {
                        Task { await exclusions.startOver() }
                    }
                }
            }
            if exclusions.couldNotSave {
                Notice(
                    title: Text("Your exclusions couldn’t be saved"),
                    detail: Text("Your latest changes work in Peel until it quits. When it opens again, and in the peel command, the list is as it was last saved.")
                ) {}
            }
            Section {
                if paths.isEmpty {
                    Text("No file or folder is on this list yet.")
                        .foregroundStyle(.secondary)
                } else {
                    List(selection: $selectedPaths) {
                        ForEach(paths, id: \.self) { path in
                            HStack(spacing: 8) {
                                AppIcon(url: path)
                                    .frame(width: 16, height: 16)
                                Text(path.abbreviatedPath)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .tag(path)
                        }
                    }
                    .frame(height: settingsListHeight(rows: paths.count))
                    .scrollContentBackground(.hidden)
                    // The Delete key does what the Remove button does, as in other Mac lists.
                    .onDeleteCommand {
                        let removed = selectedPaths
                        selectedPaths = []
                        Task { await exclusions.remove(paths: Array(removed)) }
                    }
                }
                HStack {
                    Button("Add Files or Folders…", systemImage: "plus") {
                        isChoosingPaths = true
                    }
                    Spacer()
                    Button("Remove", systemImage: "minus") {
                        let removed = selectedPaths
                        selectedPaths = []
                        Task { await exclusions.remove(paths: Array(removed)) }
                    }
                    .disabled(selectedPaths.isEmpty)
                }
                .editingControls()
            } header: {
                heading("Files and Folders", "Peel never moves anything inside these to the Trash, nor a folder that holds one of them, though some pages may still list them. Homebrew’s own Clean Up doesn’t read this list.")
            }

            Section {
                if apps.isEmpty {
                    Text("No app is on this list yet.")
                        .foregroundStyle(.secondary)
                } else {
                    List(selection: $selectedApps) {
                        ForEach(apps, id: \.self) { identifier in
                            HStack(spacing: 8) {
                                if let app = library.apps.first(where: { $0.bundleIdentifier == identifier }) {
                                    AppIcon(url: app.url)
                                        .frame(width: 16, height: 16)
                                    Text(verbatim: app.name)
                                } else {
                                    Image(systemName: "questionmark.app")
                                        .foregroundStyle(.secondary)
                                }
                                Text(verbatim: identifier)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .tag(identifier)
                        }
                    }
                    .frame(height: settingsListHeight(rows: apps.count))
                    .scrollContentBackground(.hidden)
                    .onDeleteCommand {
                        let removed = selectedApps
                        selectedApps = []
                        Task { await exclusions.remove(bundleIdentifiers: Array(removed)) }
                    }
                }
                HStack {
                    Menu {
                        // An app with no identifier is left alone by where it is, as its Control-click menu does.
                        ForEach(
                            library.apps.filter { app in
                                app.bundleIdentifier.map { !exclusions.exclusions.excludes(bundleIdentifier: $0) }
                                    ?? !exclusions.exclusions.excludes(app.url)
                            }
                        ) { app in
                            Button(app.name) {
                                Task {
                                    if let identifier = app.bundleIdentifier {
                                        await exclusions.add(bundleIdentifier: identifier)
                                    } else {
                                        await exclusions.add(paths: [app.url])
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Add App", systemImage: "plus")
                    }
                    .menuStyle(.button)
                    .fixedSize()
                    Spacer()
                    Button("Remove", systemImage: "minus") {
                        let removed = selectedApps
                        selectedApps = []
                        Task { await exclusions.remove(bundleIdentifiers: Array(removed)) }
                    }
                    .disabled(selectedApps.isEmpty)
                }
                .editingControls()
            } header: {
                heading("Apps", "Excluded apps still appear in Applications, but Peel won’t offer to remove or reset them. A folder named with an excluded app’s identifier, such as its caches or its container, is left out of every page and never moved. The app’s other files, such as plug-ins or a folder named after it, go by files and folders only, so to protect them, exclude them above as well.")
            }

            Section {
                let groups = orphans.owners.keys.sorted()
                if groups.isEmpty {
                    Text("No orphaned files are said to belong to an app.")
                        .foregroundStyle(.secondary)
                } else {
                    List(selection: $selectedGroups) {
                        ForEach(groups, id: \.self) { group in
                            HStack(spacing: 8) {
                                Text(verbatim: group)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if let owner = orphans.owners[group] {
                                    Text(verbatim: library.apps.first { $0.bundleIdentifier == owner }?.name ?? owner)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .tag(group)
                        }
                    }
                    .frame(height: settingsListHeight(rows: groups.count))
                    .scrollContentBackground(.hidden)
                    .onDeleteCommand { forgetSelectedGroups() }
                }
                HStack {
                    Spacer()
                    Button("Remove", systemImage: "minus") { forgetSelectedGroups() }
                        .disabled(selectedGroups.isEmpty)
                }
                .editingControls()
            } header: {
                heading("Orphaned Files That Belong to an App", "Orphaned Files doesn’t list these while the app you said they belong to is installed. Nothing of them was moved. Remove one to list it again.")
            }
        }
        .formStyle(.grouped)
        // `.folder` is listed as well as `.item`: with `.item` alone, the panel doesn't let the user choose a
        // folder, even though a folder conforms to `.item`.
        .fileImporter(
            isPresented: $isChoosingPaths,
            allowedContentTypes: [.item, .folder],
            allowsMultipleSelection: true
        ) { result in
            guard let urls = try? result.get() else { return }
            // Excluding a folder as broad as the home folder or `/Applications` would leave the tools with little
            // or nothing to show, without saying why. A bare `/` would protect nothing: `Exclusions` ignores it.
            let tooBroad = urls.filter { ExclusionsStore.isTooBroad($0) }
            refused = tooBroad.map(\.abbreviatedPath)
            let keeping = urls.filter { url in !tooBroad.contains(url) }
            guard !keeping.isEmpty else { return }
            Task { await exclusions.add(paths: keeping) }
        }
        .alert(refused.count == 1 ? "That folder can’t be excluded." : "These folders can’t be excluded.", isPresented: isShowingRefusal) {
            Button("OK", role: .cancel) {}
        } message: {
            let paths = refused.joined(separator: "\n")
            refused.count == 1
                ? Text("That would hide too much from Peel. Choose the folders inside it that matter to you.\n\n\(paths)")
                : Text("That would hide too much from Peel. Choose the folders inside them that matter to you.\n\n\(paths)")
        }
    }
}

extension ExclusionsSettingsView {
    private func forgetSelectedGroups() {
        let forgotten = Array(selectedGroups)
        selectedGroups = []
        Task { await orphans.forget(forgotten, from: library) }
    }
}
