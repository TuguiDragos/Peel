public import Foundation
internal import PeelPrivileged

public struct CloudFolder: Sendable, Hashable, Identifiable {
    public let url: URL
    public let names: [String]
    public let files: [CloudFile]
    public let size: Int64

    public var id: URL { url }

    init(url: URL, names: [String], files: [CloudFile]) {
        self.url = url
        self.names = names
        self.files = files.sorted { $0.size > $1.size }
        size = files.map(\.size).cappedSum
    }

    public func keeping(_ urls: Set<URL>) -> CloudFolder? {
        let kept = files.filter { urls.contains($0.url) }
        return kept.isEmpty ? nil : CloudFolder(url: url, names: names, files: kept)
    }

    public static func ordered(_ folders: [CloudFolder]) -> [CloudFolder] {
        folders.sorted { $0.size != $1.size ? $0.size > $1.size : $0.names.lexicographicallyPrecedes($1.names) }
    }

    /// A search over `files` that reads only what their rows and their folders' rows show, never the part of the path
    /// every file shares. A line end keeps a query from matching across two names.
    public static func searchable(_ files: [CloudFile], in folders: [CloudFolder]) -> SearchableList<CloudFile> {
        var shown: [URL: [String]] = [:]
        for folder in folders {
            for file in folder.files { shown[file.url] = folder.names }
        }
        return SearchableList(files) { ((shown[$0.url] ?? []) + [$0.name]).joined(separator: "\n") }
    }
}

extension CloudStorage {
    static func folders(of files: [CloudFile], home: URL) -> [CloudFolder] {
        let root = home.appending(path: "Library/Mobile Documents", directoryHint: .isDirectory)
        let grouped = Dictionary(grouping: files) {
            PathPattern.comparablePath(of: $0.url.deletingLastPathComponent())
        }
        return CloudFolder.ordered(grouped.values.map { files in
            let folder = files[0].url.deletingLastPathComponent()
            let shown = names(of: folder, container: files[0].container, under: root)
            return CloudFolder(url: folder, names: shown, files: files)
        })
    }

    /// Finder shows an app's `Documents` as the app's folder itself, so that name is left out.
    static func names(of folder: URL, container: String, under root: URL) -> [String] {
        let rootNames = PathComponents.of(PathPattern.comparablePath(of: root))
        let names = PathComponents.of(PathPattern.comparablePath(of: folder))
        guard names.count > rootNames.count, names.starts(with: rootNames) else { return [folder.lastPathComponent] }
        var place = root.appending(path: names[rootNames.count], directoryHint: .isDirectory)
        var shown = [container]
        for (depth, name) in names.dropFirst(rootNames.count + 1).enumerated() {
            place = place.appending(path: name, directoryHint: .isDirectory)
            let isAnAppsDocuments = depth == 0 && names[rootNames.count] != "com~apple~CloudDocs"
                && name.caseInsensitiveCompare("Documents") == .orderedSame
            if !isAnAppsDocuments {
                shown.append(FileManager.default.displayName(atPath: place.path(percentEncoded: false)))
            }
        }
        return shown
    }
}
