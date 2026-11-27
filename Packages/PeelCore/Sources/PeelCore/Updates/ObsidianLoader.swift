import Darwin
import Foundation

/// Obsidian's loader (`main.js` in its `app.asar`) runs the newest `obsidian-<version>.asar` in the account's data
/// folder that isn't older than the app, so the app keeps the version it was installed at.
enum ObsidianLoader {
    /// The version an Obsidian whose loader is at `bundleVersion` runs for the account at `home`, when it isn't the
    /// app's own. Only the account's data folder is read.
    static func runningVersion(loader bundleVersion: String, home: URL) -> String? {
        let folder = home.appending(path: "Library/Application Support/obsidian", directoryHint: .isDirectory)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        else { return nil }
        var newest: (version: String, parts: [Int])?
        for name in names where name.hasPrefix("obsidian-") && name.hasSuffix(".asar") {
            let version = String(name.dropFirst("obsidian-".count).dropLast(".asar".count))
            let path = folder.appending(path: name).path(percentEncoded: false)
            var info = stat()
            guard let parts = parts(of: version), lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
                continue
            }
            if newest.map({ isMoreRecent(parts, than: $0.parts) }) ?? true { newest = (version, parts) }
        }
        guard let newest, newest.version != bundleVersion else { return nil }
        if let bundle = parts(of: bundleVersion), !isMoreRecent(newest.parts, than: bundle) { return nil }
        return newest.version
    }

    /// The version of Obsidian's loader, from the `package.json` in `app.asar`, or nil for any other app.
    static func loaderVersion(ofAppAt url: URL) -> String? {
        let resources = url.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        guard BoundedRead.opens(resources.appending(path: "obsidian.asar"), maximum: .max),
              let archive = BoundedRead.data(at: resources.appending(path: "app.asar"), maximum: 1_048_576),
              let package = ElectronArchive.file(named: "package.json", in: archive),
              let manifest = (try? JSONSerialization.jsonObject(with: package)) as? [String: Any],
              manifest["name"] as? String == "obsidian"
        else { return nil }
        return manifest["version"] as? String
    }

    /// The whole number each part begins with, as the loader's `parseInt` reads a version.
    static func parts(of version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false).map { part -> Int? in
            let trimmed = part.drop { $0.isWhitespace }
            let sign = trimmed.first == "-" || trimmed.first == "+" ? 1 : 0
            guard let number = Int(trimmed.dropFirst(sign).prefix { $0.isASCII && $0.isNumber }) else { return nil }
            return trimmed.first == "-" ? -number : number
        }
        return parts.contains(nil) ? nil : parts.compactMap { $0 }
    }

    /// The loader's `isMoreRecent`.
    static func isMoreRecent(_ version: [Int], than other: [Int]) -> Bool {
        for (new, old) in zip(version, other) where new != old {
            return new > old
        }
        return version.count > other.count
    }
}
