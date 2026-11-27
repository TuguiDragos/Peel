import Darwin
public import Foundation

public enum OpenRequest {
    public static func application(amongSelected items: [URL]) -> URL? {
        guard items.count == 1, isNamedAsAnApp(items[0]) else { return nil }
        // Nothing moves from the sealed system, so the item would only lead to a page saying so. `/System/Volumes`
        // is where a disk's own data shows, and a person's app may be reached through it.
        let path = items[0].path(percentEncoded: false)
        guard !path.hasPrefix("/System/") || path.hasPrefix("/System/Volumes/") else { return nil }
        return items[0]
    }

    public static func link(toApplicationAt path: String) -> URL? {
        var components = URLComponents(string: "peel://open")
        components?.queryItems = [URLQueryItem(name: "path", value: path)]
        return components?.url
    }

    /// The folders the Finder extension watches: the startup disk, and on every other writable volume its Applications
    /// folder and, when `home` is there, the account's own.
    public static func foldersToWatch(_ volumes: [(url: URL, isReadOnly: Bool)], home: URL?) -> Set<URL> {
        // The startup disk's system volume is sealed and read only, and its apps are on the data volume it shows.
        let others = volumes.filter { !$0.isReadOnly && $0.url.path(percentEncoded: false) != "/" }.map(\.url)
        // Finder's sidebar shows a watched folder with the extension's icon, so another disk's top is never watched.
        let inside = others.flatMap { volume in
            var places = [volume]
            if let home, home.pathComponents.starts(with: volume.pathComponents) { places.append(home) }
            return places.map { $0.appending(path: "Applications", directoryHint: .isDirectory) }
        }
        return Set([URL(filePath: "/", directoryHint: .isDirectory)] + inside)
    }

    /// The folders to watch among the volumes mounted now.
    public static func foldersToWatchNow() -> Set<URL> {
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsReadOnlyKey], options: [.skipHiddenVolumes]
        ) ?? []
        return foldersToWatch(volumes.map { volume in
            (volume, (try? volume.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? true)
        }, home: accountsHome())
    }

    /// The account's real home: a sandboxed process's own home is its container.
    private static func accountsHome() -> URL? {
        var capacity = 1_024
        while capacity <= 65_536 {
            var entry = passwd()
            var found: UnsafeMutablePointer<passwd>?
            var buffer = [CChar](repeating: 0, count: capacity)
            // `pw_dir` points into the buffer, which stays pinned only for this call.
            let (result, home) = buffer.withUnsafeMutableBufferPointer { bytes -> (Int32, String?) in
                let result = getpwuid_r(getuid(), &entry, bytes.baseAddress, bytes.count, &found)
                guard result == 0, found != nil, let directory = entry.pw_dir else { return (result, nil) }
                return (result, String(cString: directory))
            }
            if result == 0 { return home.map { URL(filePath: $0, directoryHint: .isDirectory) } }
            guard result == ERANGE else { return nil }
            capacity *= 4
        }
        return nil
    }

    public static func hostApplication(ofExtensionAt bundle: URL) -> URL? {
        let host = bundle.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return isNamedAsAnApp(host) ? host : nil
    }

    /// The app bundle to show for a dropped or opened file, or a `peel://open?path=…` link.
    public static func applicationURL(from url: URL) -> URL? {
        if url.isFileURL {
            return isNamedAsAnApp(url) ? url : nil
        }
        // A scheme and a host are case insensitive (RFC 3986), and macOS hands Peel the link however they are
        // written. Any app or web page can send one, so a path a control character would make read as another
        // is refused, and so is one longer than a file's path can be, which its alert would show whole.
        guard
            url.scheme?.lowercased() == "peel",
            url.host()?.lowercased() == "open",
            let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "path" })?.value,
            path.hasPrefix("/"),
            path.utf8.count <= Int(PATH_MAX),
            !path.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { return nil }
        // The extension is read from a URL, not from the string: a bundle is a folder, and every sender of this
        // link writes its path with a trailing slash.
        let application = URL(filePath: path, directoryHint: .isDirectory)
        return isNamedAsAnApp(application) ? application : nil
    }

    /// Peel's rule for an app's name, `PathComponents.isNamedAsAnApp`, written again here: this module goes into the
    /// Finder extension, which carries nothing of the helper's module.
    private static func isNamedAsAnApp(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }
}
