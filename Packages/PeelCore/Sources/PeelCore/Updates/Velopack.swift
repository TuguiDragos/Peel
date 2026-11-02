import Foundation

/// Velopack, an update framework, as its locator reads an app on macOS (`locator.rs` at 4419cd4f).
enum Velopack {
    /// Where it keeps each app's update packages, in a folder named for the app's Velopack id.
    static let place = "Library/Caches/velopack"

    /// The id an app's Velopack manifest declares, when the app carries Velopack's updater, `UpdateMac`: the text of
    /// the last element named `id` in `sq.version`, read in `Contents/MacOS`, else in `Contents/Resources`, as Velopack
    /// reads it. Nil for an id that couldn't name a folder.
    static func id(in contents: URL) -> String? {
        var info = stat()
        guard lstat(contents.appending(path: "MacOS/UpdateMac").path(percentEncoded: false), &info) == 0,
              info.st_mode & S_IFMT == S_IFREG
        else { return nil }
        for folder in ["MacOS", "Resources"] {
            let manifest = contents.appending(path: "\(folder)/sq.version")
            guard let data = BoundedRead.data(at: manifest, maximum: 64 * 1_024),
                  let last = String(decoding: data, as: UTF8.self)
                    .matches(of: /<(?:[A-Za-z_][\w.-]*:)?id>([^<]*)<\/(?:[A-Za-z_][\w.-]*:)?id>/).last
            else { continue }
            let id = String(last.output.1).trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty || id.contains("/") || id == "." || id == ".." ? nil : id
        }
        return nil
    }

    /// Whether an app's folder holds an update package Velopack downloaded.
    static func holdsAnUpdate(_ folder: URL) -> Bool {
        let packages = folder.appending(path: "packages", directoryHint: .isDirectory).path(percentEncoded: false)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: packages)) ?? []
        return names.contains { $0.lowercased().hasSuffix(".nupkg") }
    }
}
