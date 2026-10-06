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
    /// The package the app sits inside, such as the app it is a helper of. Moved alone, the app would be cut out
    /// of that package, so it stays with it.
    public let enclosingPackage: URL?
    /// When the app was last opened, as Spotlight records it. Nil when it never was, or when nothing records it.
    public let lastUsedDate: Date?
    /// Whether Spotlight records when the app is opened, so that no `lastUsedDate` means it never was. Spotlight
    /// keeps no record for an app in a folder it does not index.
    public let isUseRecorded: Bool
    public let dateAdded: Date?
    public let updateFeed: UpdateFeed?
    /// Whether this is Peel, which is removed only from its own Settings, where the helper and the login item
    /// are unregistered first. Also true for the bundle the running code sits inside, such as the Peel that
    /// embeds the `peel` tool, whatever its name or identifier.
    public let isPeelItself: Bool
    /// Whether this is the very bundle the running code was started from: the copy of Peel that is running.
    public let isTheRunningCopy: Bool
    /// Whether this is a web app Safari made (`SafariWebApp`), whose identifier names it and nothing of Apple's.
    public let isASafariWebApp: Bool

    /// Whether `other`, a reading of the same path, is the same build. Not `==`: the date an app was last opened
    /// changes every time it is opened, which is no reason to forget its size or check it for updates again.
    public func isTheSameBuild(as other: InstalledApp) -> Bool {
        version == other.version && buildVersion == other.buildVersion && architectures == other.architectures
            && teamIdentifier == other.teamIdentifier
    }

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
        enclosingPackage: URL? = nil,
        lastUsedDate: Date? = nil,
        isUseRecorded: Bool = true,
        dateAdded: Date? = nil,
        updateFeed: UpdateFeed? = nil,
        isASafariWebApp: Bool = false
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
        self.enclosingPackage = enclosingPackage
        self.lastUsedDate = lastUsedDate
        self.isUseRecorded = isUseRecorded
        self.dateAdded = dateAdded
        self.isASafariWebApp = isASafariWebApp
        self.updateFeed = updateFeed
        let path = PathPattern.comparablePath(of: url)
        isPeelItself = Self.isPeel(bundleIdentifier, at: path)
        isTheRunningCopy = path == Self.runningBundle
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

    /// Returns a copy with what Spotlight records of the app's use, which can change while the bundle stays the same.
    func withUse(lastUsedDate date: Date?, isUseRecorded isRecorded: Bool) -> InstalledApp {
        guard date != lastUsedDate || isRecorded != isUseRecorded else { return self }
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
            enclosingPackage: enclosingPackage,
            lastUsedDate: date,
            isUseRecorded: isRecorded,
            dateAdded: dateAdded,
            updateFeed: updateFeed,
            isASafariWebApp: isASafariWebApp
        )
    }

    private static let runningBundle = PathPattern.comparablePath(of: Bundle.main.bundleURL)

    private static func isPeel(_ bundleIdentifier: String, at path: String) -> Bool {
        let own = HelperIdentity.appIdentifier.lowercased()
        let identifier = bundleIdentifier.lowercased()
        if identifier == own || identifier.hasPrefix(own + ".") { return true }
        return PathComponents.isPath(runningBundle, inside: path)
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
