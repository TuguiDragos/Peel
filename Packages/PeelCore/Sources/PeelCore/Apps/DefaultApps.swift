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
    /// What a kind of file is called, such as "PDF document". For a link, the scheme and its colon, which the app
    /// replaces with its own words.
    public let name: String
    /// The apps that could take over, best first, without this one.
    public let others: [String]
    /// The extension macOS prefers for a kind of file, without its dot, or nil for a link or a kind with none.
    public let fileExtension: String?

    init(kind: Kind, identifier: String, name: String, others: [String], fileExtension: String? = nil) {
        self.kind = kind
        self.identifier = identifier
        self.name = name
        self.others = others
        self.fileExtension = fileExtension
    }

    public var id: String { "\(kind.rawValue):\(identifier)" }
}

/// The kinds of files, or of links, an app opens by default that one other app would open once it is gone, or none.
public struct DefaultHandOver: Sendable, Hashable, Identifiable {
    /// The app that would open them, the best that can, or nil when nothing else on this Mac opens them.
    public let app: String?
    /// Their names, those that share one written once with their extensions, such as "Image File (.erf, .mos)".
    public let kinds: [String]
    /// How many kinds, counted before those of one name were joined.
    public let count: Int

    public init(app: String?, kinds: [String], count: Int) {
        self.app = app
        self.kinds = kinds
        self.count = count
    }

    public var id: String { app ?? "" }
}

public enum DefaultApps {
    /// Returns the kinds of files and links `app` is currently the default for, sorted by name.
    @concurrent
    public static func roles(of app: InstalledApp) async -> [DefaultRole] {
        guard let info = AppInspector.infoDictionary(in: AppBundleLayout(of: app.url).infoFolder) else { return [] }
        return (fileKinds(declaredIn: info, app: app) + links(declaredIn: info, app: app))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The roles of `kind` among `roles`, by the app that would take each over: the apps that take more first, then by
    /// name, and what nothing else opens last.
    public static func handOvers(_ roles: [DefaultRole], of kind: DefaultRole.Kind) -> [DefaultHandOver] {
        Dictionary(grouping: roles.filter { $0.kind == kind }) { $0.others.first }
            .map { app, roles in DefaultHandOver(app: app, kinds: joined(roles), count: roles.count) }
            .sorted { first, second in
                guard let one = first.app else { return false }
                guard let other = second.app else { return true }
                guard first.count == second.count else { return first.count > second.count }
                return one.localizedStandardCompare(other) == .orderedAscending
            }
    }

    /// The names of `roles` by name, those that share one written once with their extensions.
    static func joined(_ roles: [DefaultRole]) -> [String] {
        var extensions: [String: [String]] = [:]
        var counts: [String: Int] = [:]
        for role in roles {
            counts[role.name, default: 0] += 1
            let found = extensions[role.name, default: []]
            let written = role.fileExtension.map { "." + $0 }
            extensions[role.name] = written.map { found.contains($0) ? found : found + [$0] } ?? found
        }
        return counts.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { name in
            guard counts[name, default: 0] > 1, let found = extensions[name], !found.isEmpty else { return name }
            return "\(name) (\(found.joined(separator: ", ")))"
        }
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
                others: names(of: NSWorkspace.shared.urlsForApplications(toOpen: type), without: app),
                fileExtension: type.preferredFilenameExtension
            )
        }
    }

    /// What a kind of file is called: macOS's description, or, for a type no app registers, the name the app that
    /// opens it gives that kind of document, as Finder does, or else its extension.
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
        PathPattern.comparablePath(of: PathPattern.canonicalWithoutOpening(url))
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
