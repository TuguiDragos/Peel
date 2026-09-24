import Foundation
import PeelCore

enum AppLookup {
    enum Failure: Error, Equatable, CustomStringConvertible {
        case notFound(String)
        case ambiguous(String, [String])
        case notAnApp(String)
        case excluded(String)
        case exclusionsUnreadable(String)

        var description: String {
            switch self {
            case .notFound(let query):
                "No installed app matches \"\(query)\". Run `peel apps` to see installed apps."
            case .ambiguous(let query, let paths):
                "Several apps match \"\(query)\". Use one of these paths:\n" + paths.map { "  \($0)" }.joined(separator: "\n")
            case .notAnApp(let path):
                "\(path) isn't an app."
            case .excluded(let name):
                "\(name) is excluded in Peel's settings, so Peel leaves it alone."
            case .exclusionsUnreadable(let path):
                "Peel couldn't read your exclusions at \(path), so it left everything alone. Open Peel and click Start Over in Settings > Exclusions."
            }
        }
    }

    /// Throws when `app` is excluded in Peel's settings, so the command line leaves it alone as the app does.
    /// While the saved list can't be read, it throws for every app, since what the user excluded is unknown.
    static func refuseIfExcluded(_ app: InstalledApp, by exclusions: Exclusions, savedAt url: URL = ExclusionStore.defaultURL) throws(Failure) {
        guard !exclusions.isUnreadable else { throw .exclusionsUnreadable(url.path(percentEncoded: false)) }
        guard exclusions.excludes(app) else { return }
        throw .excluded(app.name)
    }

    /// Reads a bundle that isn't among the installed apps from the disk. Injected so a test doesn't depend on
    /// the folder it runs from.
    typealias Inspect = (URL) -> InstalledApp?

    /// Finds an app by path, bundle identifier, or name, tried in that order. A name may end in `.app`, like
    /// the bundle's file name.
    static func app(matching query: String, in apps: [InstalledApp], inspect: Inspect = AppInspector.inspect) throws(Failure) -> InstalledApp {
        if query.contains("/") {
            return try app(at: query, in: apps, inspect: inspect)
        }
        // Two bundles can share an identifier: a copy in `~/Applications` beside one in `/Applications`, or a
        // beta beside the release. Taking the first match would remove whichever sorted first, so this throws.
        let byIdentifier = apps.filter { $0.bundleIdentifier.caseInsensitiveCompare(query) == .orderedSame }
        switch byIdentifier.count {
        case 0: break
        case 1: return byIdentifier[0]
        default: throw .ambiguous(query, byIdentifier.map { normalizedPath($0.url) })
        }
        // Compared without the user's locale: under Turkish rules, `iina` wouldn't match `IINA`.
        let named = apps.filter { names(of: $0).contains { $0.compare(bareName(query), options: [.caseInsensitive, .widthInsensitive]) == .orderedSame } }
        switch named.count {
        case 0: break
        case 1: return named[0]
        default: throw .ambiguous(query, named.map { normalizedPath($0.url) })
        }
        // A name ending in `.app` may still be a bundle sitting in the current folder.
        guard query.lowercased().hasSuffix(".app"), let app = try? app(at: query, in: apps, inspect: inspect) else {
            throw .notFound(query)
        }
        return app
    }

    /// Finds the app at a path, which may be a bundle that isn't installed, such as one in the current folder.
    private static func app(at query: String, in apps: [InstalledApp], inspect: Inspect) throws(Failure) -> InstalledApp {
        let path = normalizedPath(URL(argument: query))
        if let app = apps.first(where: { normalizedPath($0.url) == path }) {
            return app
        }
        if let app = AppCatalog.app(at: URL(filePath: path), among: apps) {
            return app
        }
        guard let app = inspect(URL(filePath: path, directoryHint: .isDirectory)) else { throw .notAnApp(query) }
        return app
    }

    /// The names an app answers to: the name the Finder shows, the bundle's file name, and `CFBundleName`.
    private static func names(of app: InstalledApp) -> [String] {
        [app.name, app.url.deletingPathExtension().lastPathComponent, app.bundleName].compactMap(\.self)
    }

    private static func bareName(_ query: String) -> String {
        query.lowercased().hasSuffix(".app") ? String(query.dropLast(".app".count)) : query
    }

    private static func normalizedPath(_ url: URL) -> String {
        PathPattern.comparablePath(of: url)
    }
}
