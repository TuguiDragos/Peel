import Foundation
internal import AppKit
internal import UniformTypeIdentifiers

/// A kind of file or link that an app opens by default, and the apps that would open it if the app were gone.
/// Peel only reads this. The user changes a default in Finder's Get Info or in Settings.
public struct DefaultRole: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case fileKind
        case link
    }

    public let kind: Kind
    /// The uniform type identifier, or the scheme without its colon.
    public let identifier: String
    /// What a kind of file is called, such as "PDF document". For a link, the scheme and its colon, which the
    /// app replaces with its own words.
    public let name: String
    /// The apps that could take over, best first, without this one.
    public let others: [String]

    public var id: String { "\(kind.rawValue):\(identifier)" }
}

public enum DefaultApps {
    /// Returns the kinds of files and links `app` is currently the default for, sorted by name.
    @concurrent
    public static func roles(of app: InstalledApp) async -> [DefaultRole] {
        let contents = app.url.appending(path: "Contents", directoryHint: .isDirectory)
        guard let info = AppInspector.infoDictionary(in: contents) else { return [] }
        return (fileKinds(declaredIn: info, app: app) + links(declaredIn: info, app: app))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Returns the types a bundle declares it opens. An older app lists file extensions instead
    /// (`CFBundleTypeExtensions`), and each one is turned into the type it stands for.
    static func declaredTypes(in info: [String: Any]) -> [String] {
        (info["CFBundleDocumentTypes"] as? [[String: Any]] ?? []).flatMap { document -> [String] in
            if let types = document["LSItemContentTypes"] as? [String], !types.isEmpty { return types }
            return (document["CFBundleTypeExtensions"] as? [String] ?? [])
                .filter { $0 != "*" }
                .compactMap { UTType(filenameExtension: $0.lowercased())?.identifier }
        }
    }

    static func fileKinds(declaredIn info: [String: Any], app: InstalledApp) -> [DefaultRole] {
        var seen: Set<String> = []

        return declaredTypes(in: info).compactMap { identifier -> DefaultRole? in
            guard seen.insert(identifier).inserted, let type = UTType(identifier) else { return nil }
            guard isDefault(app, for: NSWorkspace.shared.urlForApplication(toOpen: type)) else { return nil }
            return DefaultRole(
                kind: .fileKind,
                identifier: identifier,
                name: type.localizedDescription ?? identifier,
                others: names(of: NSWorkspace.shared.urlsForApplications(toOpen: type), without: app)
            )
        }
    }

    static func links(declaredIn info: [String: Any], app: InstalledApp) -> [DefaultRole] {
        let declared = (info["CFBundleURLTypes"] as? [[String: Any]] ?? [])
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        var seen: Set<String> = []

        return declared.compactMap { scheme -> DefaultRole? in
            let scheme = scheme.lowercased()
            guard seen.insert(scheme).inserted, let url = URL(string: scheme + ":") else { return nil }
            guard isDefault(app, for: NSWorkspace.shared.urlForApplication(toOpen: url)) else { return nil }
            return DefaultRole(
                kind: .link,
                identifier: scheme,
                name: scheme + ":",
                others: names(of: NSWorkspace.shared.urlsForApplications(toOpen: url), without: app)
            )
        }
    }

    /// The real path of an app, with links resolved. macOS reports Safari at its path inside a cryptex, and
    /// `/Applications/Safari.app` is a link to it.
    private static func place(of url: URL) -> String {
        PathPattern.comparablePath(of: PathPattern.canonical(url))
    }

    static func isDefault(_ app: InstalledApp, for handler: URL?) -> Bool {
        guard let handler else { return false }
        return place(of: handler) == place(of: app.url)
    }

    static func names(of handlers: [URL], without app: InstalledApp) -> [String] {
        let own = place(of: app.url)
        return handlers
            .filter { place(of: $0) != own }
            .map(AppInspector.displayName)
    }
}
