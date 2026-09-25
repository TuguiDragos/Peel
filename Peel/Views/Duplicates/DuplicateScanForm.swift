import PeelCore
import SwiftUI
import UniformTypeIdentifiers

/// What a scan looks at, in a popover from the toolbar: a change applies to the next scan and costs no results.
struct DuplicateScanForm: View {
    private static let sizes: [Int64] = [100_000, 1_000_000, 10_000_000, 100_000_000]

    @Environment(DuplicateLibrary.self) private var duplicates
    @State private var isChoosingFolders = false
    @State private var rejectedFolders: [URL] = []
    let onScan: () -> Void

    var body: some View {
        @Bindable var duplicates = duplicates

        VStack(spacing: 0) {
            Form {
                Section {
                    // Only the rows are disabled, so the note beside the Folders heading still opens during a scan.
                    Group {
                        ForEach(duplicates.folders, id: \.self) { folder in
                            FolderRow(folder: folder)
                        }
                        Button {
                            isChoosingFolders = true
                        } label: {
                            Label("Add Folder…", systemImage: "plus")
                                .minimumTarget()
                        }
                        .buttonStyle(.borderless)
                    }
                    .disabled(duplicates.isScanning)
                } header: {
                    heading("Folders", "Peel compares files by their full contents. A folder is a copy only when every file in it matches, hidden ones included. Repositories (Git, Mercurial, Subversion), projects with a build file such as package.json or Cargo.toml, node_modules, and libraries such as Photos and Music are left alone, and an app is never offered on its own. A build file at the top of a folder you chose doesn’t make it a project.")
                }

                Section {
                    Picker("Kind", selection: $duplicates.kind) {
                        ForEach(FileKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    Picker("Size", selection: $duplicates.minimumSize) {
                        Text("Any size").tag(Int64(1))
                        ForEach(Self.sizes, id: \.self) { size in
                            Text("At least \(size.byteCount)").tag(size)
                        }
                    }
                }
                .disabled(duplicates.isScanning)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Scan", action: onScan)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(duplicates.folders.isEmpty || duplicates.isScanning)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 420, height: 460)
        .fileImporter(isPresented: $isChoosingFolders, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            rejectedFolders = duplicates.add(urls)
        }
        .alert(
            rejectedFolders.count == 1 ? "Peel can’t look for duplicates in this folder." : "Peel can’t look for duplicates in these folders.",
            isPresented: isShowingRejectedFolders
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            let paths = rejectedFolders.map(\.abbreviatedPath).joined(separator: "\n")
            Text("Choose a folder in your home folder, /Users/Shared, or a disk Peel can write to. iCloud Drive, app data, the Music and TV apps’ media folders, and system folders aren’t scanned.\n\n\(paths)")
        }
    }

    private var isShowingRejectedFolders: Binding<Bool> {
        Binding(
            get: { !rejectedFolders.isEmpty },
            set: { if !$0 { rejectedFolders = [] } }
        )
    }
}

/// A row for a folder chosen for the scan. It is a separate view so that its display name, which comes from
/// Launch Services, is looked up once per row rather than on every redraw of the form.
private struct FolderRow: View {
    @Environment(DuplicateLibrary.self) private var duplicates
    let folder: URL

    var body: some View {
        HStack(spacing: 8) {
            AppIcon(url: folder)
                .frame(width: 18, height: 18)
            Text(verbatim: FileManager.default.displayName(atPath: folder.path(percentEncoded: false)))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button {
                duplicates.folders.removeAll { $0 == folder }
            } label: {
                Label("Remove", systemImage: "minus.circle")
                    .labelStyle(.iconOnly)
                    .minimumTarget()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(Text("Don’t scan this folder"))
        }
        .help(folder.abbreviatedPath)
    }
}
