import PeelCore
import SwiftUI
import UniformTypeIdentifiers

struct ExclusionsSettingsView: View {
    @Environment(ExclusionsStore.self) private var exclusions
    @Environment(AppLibrary.self) private var library
    @Environment(OrphanLibrary.self) private var orphans
    @State private var isChoosingPaths = false
    @State private var isChoosingApp = false
    @State private var refused: [String] = []
    @State private var selectedPaths: Set<URL> = []
    @State private var selectedApps: Set<String> = []
    @State private var selectedGroups: Set<String> = []
    @State private var notForgotten: ListChange?

    private var paths: [URL] {
        exclusions.exclusions.paths.sorted { $0.path(percentEncoded: false) < $1.path(percentEncoded: false) }
    }

    private var apps: [String] {
        exclusions.exclusions.bundleIdentifiers.sorted()
    }

    /// What an empty list says once the list is known: nothing while it can't be read, since the file holds what the
    /// person chose, and Checking… until it has been read.
    @ViewBuilder
    private func emptyList(_ words: LocalizedStringResource) -> some View {
        if exclusions.exclusions.isKnown {
            Text(words)
                .foregroundStyle(.secondary)
        } else if !exclusions.exclusions.isUnreadable {
            Text("Checking…")
                .foregroundStyle(.secondary)
        }
    }

    private var unreadableDetail: String {
        exclusions.exclusions.whyUnreadable.said(after: String(localized: "Until it can read them, or you start over, Peel removes nothing and puts nothing back, because it can’t tell what you asked it to leave alone. Adding or removing an entry below starts over too: the old file is kept beside the new one, but nothing in it counts anymore."), about: exclusions.file)
    }

    private var notSavedDetail: String {
        exclusions.whyNotSaved.said(after: String(localized: "Your latest changes work in Peel until it quits. When it opens again, and in the peel command, the list is as it was last saved."), about: exclusions.file)
    }

    private var ownersUnreadable: String {
        orphans.whyOwnersUnreadable.said(after: String(localized: "Peel can’t read this list, so Orphaned Files lists these files again. Starting over keeps the old list beside a new one."), about: OrphanOwners.defaultURL)
    }

    private var isShowingRefusal: Binding<Bool> {
        Binding(get: { !refused.isEmpty }, set: { if !$0 { refused = [] } })
    }

    static let filesAndFoldersNote: LocalizedStringResource = "Peel never moves these, anything inside them, or a folder that holds one of them to the Trash, and never puts anything back into them. Its lists leave them out. Two pages still show them: Applications marks an app inside them as excluded, and Homebrew lists a package inside them but won’t upgrade or uninstall it. History still shows what moved before. Homebrew’s Clean Up keeps the formulae whose folder you exclude here, but this list doesn’t cover what else it deletes, such as its downloads."

    static let appsNote: LocalizedStringResource = "Excluded apps still appear in Applications, but Peel won’t offer to remove or reset them, and won’t put one back from the Trash. A folder named exactly with an excluded app’s identifier, such as its caches or its container, and an update it downloaded are left out of every page and never moved. This list doesn’t cover the app’s other files, such as plug-ins or a folder named after it. To protect those, add them to Files and Folders above."

    var body: some View {
        Form {
            if exclusions.exclusions.isUnreadable {
                Notice(
                    title: Text("Peel couldn’t read your exclusions"),
                    detail: Text(verbatim: unreadableDetail)
                ) {
                    StartOverButton(file: ExclusionStore.defaultURL, startedOver: "Started the list of exclusions over.") {
                        await exclusions.startOver()
                    }
                }
            }
            if exclusions.couldNotSave {
                Notice(
                    title: Text("Your exclusions couldn’t be saved"),
                    detail: Text(verbatim: notSavedDetail)
                ) {}
            }
            Section {
                if paths.isEmpty {
                    emptyList("No file or folder is on this list yet.")
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
                ListEditingButtons {
                    Button("Add Files or Folders…", systemImage: "plus") {
                        isChoosingPaths = true
                    }
                    .help(Text("Add Files or Folders…"))
                    Button("Remove", systemImage: "minus") {
                        let removed = selectedPaths
                        selectedPaths = []
                        Task { await exclusions.remove(paths: Array(removed)) }
                    }
                    .disabled(selectedPaths.isEmpty)
                    .help(Text("Remove"))
                }
            } header: {
                heading("Files and Folders", Self.filesAndFoldersNote)
            }

            Section {
                if apps.isEmpty {
                    emptyList("No app is on this list yet.")
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
                                        .accessibilityRepresentation { Text("Not installed") }
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
                ListEditingButtons {
                    Button("Add App…", systemImage: "plus") {
                        isChoosingApp = true
                    }
                    .help(Text("Add App…"))
                    .popover(isPresented: $isChoosingApp, arrowEdge: .bottom) {
                        // An app with no identifier is left alone by where it is, as its Control-click menu does.
                        AppChooser(
                            apps: library.apps.filter { app in
                                app.bundleIdentifier.map { !exclusions.exclusions.excludes(bundleIdentifier: $0) }
                                    ?? !exclusions.exclusions.excludes(app.url)
                            }
                        ) { app in
                            isChoosingApp = false
                            Task {
                                if let identifier = app.bundleIdentifier {
                                    await exclusions.add(bundleIdentifier: identifier)
                                } else {
                                    await exclusions.add(paths: [app.url])
                                }
                            }
                        }
                        .frame(width: 280)
                        .padding(10)
                    }
                    Button("Remove", systemImage: "minus") {
                        let removed = selectedApps
                        selectedApps = []
                        Task { await exclusions.remove(bundleIdentifiers: Array(removed)) }
                    }
                    .disabled(selectedApps.isEmpty)
                    .help(Text("Remove"))
                }
            } header: {
                heading("Apps", Self.appsNote)
            }

            Section {
                if let owners = orphans.owners {
                    let groups = owners.keys.sorted()
                    if groups.isEmpty {
                        Text("No orphaned files are said to belong to an app or a tool.")
                            .foregroundStyle(.secondary)
                    } else {
                        List(selection: $selectedGroups) {
                            ForEach(groups, id: \.self) { group in
                                HStack(spacing: 8) {
                                    Text(verbatim: group)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    switch owners[group] {
                                    case .app(let identifier)?:
                                        let name = library.apps.first { $0.bundleIdentifier == identifier }?.name
                                        Text(verbatim: name ?? identifier)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    case .formula(let name)?, .command(let name)?:
                                        HStack(spacing: 4) {
                                            Image(systemName: "terminal")
                                            Text(verbatim: name)
                                                .lineLimit(1)
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    case nil:
                                        EmptyView()
                                    }
                                }
                                .tag(group)
                            }
                        }
                        .frame(height: settingsListHeight(rows: groups.count))
                        .scrollContentBackground(.hidden)
                        .onDeleteCommand { forgetSelectedGroups() }
                    }
                    ListEditingButtons {
                        Button("Remove", systemImage: "minus") { forgetSelectedGroups() }
                            .disabled(selectedGroups.isEmpty)
                            .help(Text("Remove"))
                    }
                } else {
                    HStack(spacing: 8) {
                        Text(verbatim: ownersUnreadable)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        StartOverButton(
                            file: OrphanOwners.defaultURL,
                            startedOver: "Started the list of orphaned files that belong to an app or a tool over."
                        ) {
                            orphans.startOwnersOver()
                        }
                    }
                }
            } header: {
                heading("Orphaned Files That Belong to an App or a Tool", "Orphaned Files doesn’t list these while the app or the command-line tool you said they belong to is installed. Nothing of them was moved. Remove one to list it again.")
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
        .alert(
            "Peel couldn’t list these files again",
            isPresented: Binding(get: { notForgotten != nil }, set: { if !$0 { notForgotten = nil } })
        ) {
            Button("OK") {}
        } message: {
            if case .notSaved(let why) = notForgotten { Text(verbatim: orphans.ownersNotSaved(why)) }
        }
        .alert(refused.count == 1 ? "That folder can’t be excluded." : "These folders can’t be excluded.", isPresented: isShowingRefusal) {
            Button("OK") {}
        } message: {
            let paths = RemovalFailureAlert.firstItems(refused).joined(separator: "\n")
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
        Task {
            let change = await orphans.forget(forgotten, from: library)
            if change != .saved { notForgotten = change }
        }
    }
}
