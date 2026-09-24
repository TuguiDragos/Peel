public import Foundation

public enum OpenRequest {
    /// The app bundle to show for a dropped or opened file, or a `peel://open?path=…` link.
    public static func applicationURL(from url: URL) -> URL? {
        if url.isFileURL {
            return url.pathExtension == "app" ? url : nil
        }
        guard
            url.scheme == "peel",
            url.host() == "open",
            let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "path" })?.value,
            path.hasPrefix("/")
        else { return nil }
        // The extension is read from a URL, not from the string: a bundle is a folder, and every sender of this
        // link writes its path with a trailing slash.
        let application = URL(filePath: path, directoryHint: .isDirectory)
        return application.pathExtension == "app" ? application : nil
    }
}
