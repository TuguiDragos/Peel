public import Foundation

public enum OpenRequest {
    public static func application(amongSelected items: [URL]) -> URL? {
        guard items.count == 1, items[0].pathExtension == "app" else { return nil }
        return items[0]
    }

    public static func link(toApplicationAt path: String) -> URL? {
        var components = URLComponents(string: "peel://open")
        components?.queryItems = [URLQueryItem(name: "path", value: path)]
        return components?.url
    }

    public static func hostApplication(ofExtensionAt bundle: URL) -> URL? {
        let host = bundle.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return host.pathExtension == "app" ? host : nil
    }

    /// The app bundle to show for a dropped or opened file, or a `peel://open?path=…` link.
    public static func applicationURL(from url: URL) -> URL? {
        if url.isFileURL {
            return url.pathExtension == "app" ? url : nil
        }
        // A scheme and a host are case insensitive (RFC 3986), and macOS hands Peel the link however they are
        // written. Any app or web page can send one, so a path a control character would make read as another
        // is refused.
        guard
            url.scheme?.lowercased() == "peel",
            url.host()?.lowercased() == "open",
            let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "path" })?.value,
            path.hasPrefix("/"),
            !path.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { return nil }
        // The extension is read from a URL, not from the string: a bundle is a folder, and every sender of this
        // link writes its path with a trailing slash.
        let application = URL(filePath: path, directoryHint: .isDirectory)
        return application.pathExtension == "app" ? application : nil
    }
}
