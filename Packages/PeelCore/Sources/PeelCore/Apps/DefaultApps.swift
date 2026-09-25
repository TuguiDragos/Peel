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
    /// What a kind of file is called, such as "PDF document", or what the app calls it when macOS has no name for
    /// it. For a link, the scheme and its colon, which the app replaces with its own words.
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

    /// A type an app declares it opens, with the name the app gives that kind of document (`CFBundleTypeName`).
    struct DeclaredType {
        let identifier: String
        let appName: String?
    }

    /// Returns the types a bundle declares it opens. An older app lists file extensions instead
    /// (`CFBundleTypeExtensions`), and each one is turned into the type it stands for.
    static func declaredTypes(in info: [String: Any]) -> [DeclaredType] {
        (info["CFBundleDocumentTypes"] as? [[String: Any]] ?? []).flatMap { document -> [DeclaredType] in
            let appName = document["CFBundleTypeName"] as? String
            let types = document["LSItemContentTypes"] as? [String] ?? []
            let identifiers = !types.isEmpty ? types : (document["CFBundleTypeExtensions"] as? [String] ?? [])
                .filter { $0 != "*" }
                .compactMap { UTType(filenameExtension: $0.lowercased())?.identifier }
            return identifiers.map { DeclaredType(identifier: $0, appName: appName) }
        }
    }

    static func fileKinds(declaredIn info: [String: Any], app: InstalledApp) -> [DefaultRole] {
        var seen: Set<String> = []
        let bundle = Bundle(url: app.url)

        return declaredTypes(in: info).compactMap { declared -> DefaultRole? in
            guard seen.insert(declared.identifier).inserted, let type = UTType(declared.identifier) else { return nil }
            guard isDefault(app, for: NSWorkspace.shared.urlForApplication(toOpen: type)) else { return nil }
            return DefaultRole(
                kind: .fileKind,
                identifier: declared.identifier,
                name: name(of: type, calledByTheApp: declared.appName, in: bundle),
                others: names(of: NSWorkspace.shared.urlsForApplications(toOpen: type), without: app)
            )
        }
    }

    /// What a kind of file is called. A type macOS made up from an extension that no app registers has no
    /// description, and Finder calls such a file by the name the app that opens it gives that kind of document, in
    /// the app's own translation. Without one, the extension says more than Finder's "Document".
    static func name(of type: UTType, calledByTheApp appName: String?, in bundle: Bundle?) -> String {
        if let description = type.localizedDescription { return description }
        if let appName {
            return bundle?.localizedString(forKey: appName, value: appName, table: "InfoPlist") ?? appName
        }
        if let fileExtension = type.preferredFilenameExtension { return "." + fileExtension }
        return type.identifier
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
