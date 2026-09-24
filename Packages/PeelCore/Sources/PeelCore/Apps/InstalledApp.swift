public import Foundation
internal import PeelPrivileged

public struct InstalledApp: Sendable, Hashable, Identifiable {
    public let url: URL
    public let bundleIdentifier: String
    public let name: String
    public let bundleName: String?
    public let version: String?
    public let buildVersion: String?
    public let teamIdentifier: String?
    /// The maker, as the app's signature names it. Nil when the signature names nobody, as for an App Store
    /// app, which Apple signs again.
    public let developer: String?
    public let applicationGroups: [String]
    public let embeddedBundleIdentifiers: [String]
    public let architectures: Set<Architecture>
    public let isFromAppStore: Bool
    public let isSystemProtected: Bool
    public let lastUsedDate: Date?
    public let dateAdded: Date?
    public let updateFeed: UpdateFeed?

    public init(
        url: URL,
        bundleIdentifier: String,
        name: String,
        bundleName: String? = nil,
        version: String? = nil,
        buildVersion: String? = nil,
        teamIdentifier: String? = nil,
        developer: String? = nil,
        applicationGroups: [String] = [],
        embeddedBundleIdentifiers: [String] = [],
        architectures: Set<Architecture> = [.arm64],
        isFromAppStore: Bool = false,
        isSystemProtected: Bool = false,
        lastUsedDate: Date? = nil,
        dateAdded: Date? = nil,
        updateFeed: UpdateFeed? = nil
    ) {
        self.url = url
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.bundleName = bundleName
        self.version = version
        self.buildVersion = buildVersion
        self.teamIdentifier = teamIdentifier
        self.developer = developer
        self.applicationGroups = applicationGroups
        self.embeddedBundleIdentifiers = embeddedBundleIdentifiers
        self.architectures = architectures
        self.isFromAppStore = isFromAppStore
        self.isSystemProtected = isSystemProtected
        self.lastUsedDate = lastUsedDate
        self.dateAdded = dateAdded
        self.updateFeed = updateFeed
    }

    public var id: URL { url }

    public var isIntelOnly: Bool { architectures == [.x86_64] }

    /// Whether the app came from Setapp. Setapp's documentation says a bundle identifier "must use the -setapp
    /// suffix", and Setapp installs apps in an `Applications/Setapp` folder, the system's or the user's.
    public var isFromSetapp: Bool {
        let folder = url.deletingLastPathComponent()
        return bundleIdentifier.lowercased().hasSuffix("-setapp")
            || (folder.lastPathComponent == "Setapp" && folder.deletingLastPathComponent().lastPathComponent == "Applications")
    }

    /// Returns a copy with `date` as the last used date, which can change while the bundle stays the same.
    func withLastUsedDate(_ date: Date?) -> InstalledApp {
        guard date != lastUsedDate else { return self }
        return InstalledApp(
            url: url,
            bundleIdentifier: bundleIdentifier,
            name: name,
            bundleName: bundleName,
            version: version,
            buildVersion: buildVersion,
            teamIdentifier: teamIdentifier,
            developer: developer,
            applicationGroups: applicationGroups,
            embeddedBundleIdentifiers: embeddedBundleIdentifiers,
            architectures: architectures,
            isFromAppStore: isFromAppStore,
            isSystemProtected: isSystemProtected,
            lastUsedDate: date,
            dateAdded: dateAdded,
            updateFeed: updateFeed
        )
    }

    /// Whether this is Peel, which is removed only from its own Settings, where the helper and the login item
    /// are unregistered first. Also true for the bundle the running code sits inside, such as the Peel that
    /// embeds the `peel` tool, whatever its name or identifier.
    public var isPeelItself: Bool {
        let own = HelperIdentity.appIdentifier.lowercased()
        let identifier = bundleIdentifier.lowercased()
        if identifier == own || identifier.hasPrefix(own + ".") { return true }
        return PathPattern.comparablePath(of: Bundle.main.bundleURL).hasPrefix(PathPattern.comparablePath(of: url) + "/")
    }

    /// The name Finder shows, which follows the user's language when the app translates it, and the bundle's file
    /// name, which does not. Anything that decides by name checks both, so the app and `peel`, which always sees
    /// English names, reach the same answer.
    public var names: [String] {
        let fileName = url.deletingPathExtension().lastPathComponent
        return fileName == name ? [name] : [name, fileName]
    }

    var matchingNames: Set<String> {
        var names: Set<String> = [name, url.deletingPathExtension().lastPathComponent]
        if let bundleName { names.insert(bundleName) }
        for name in names {
            if let withoutVersion = Naming.withoutTrailingVersion(name) { names.insert(withoutVersion) }
        }
        return names
    }
}

public enum Architecture: String, Sendable, Hashable, CaseIterable {
    case arm64
    case x86_64
}
