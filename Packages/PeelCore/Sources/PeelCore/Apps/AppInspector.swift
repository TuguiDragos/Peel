import CoreServices
import Darwin
import AppKit
public import Foundation
import Security
internal import PeelPrivileged

public enum AppInspector {
    /// Where macOS thinks an app is, including folders Peel doesn't scan, such as a build folder.
    /// A copy in the Trash doesn't count as installed.
    public static func applicationURL(forBundleIdentifier identifier: String) -> URL? {
        applicationURLs(forBundleIdentifier: identifier).first
    }

    /// Every copy of the app with `identifier` that macOS knows, wherever it is, best first. A copy in the Trash
    /// doesn't count as installed.
    static func applicationURLs(forBundleIdentifier identifier: String) -> [URL] {
        NSWorkspace.shared.urlsForApplications(withBundleIdentifier: identifier).filter { url in
            !isInATrash(url) && FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        }
    }

    static func isInATrash(_ url: URL) -> Bool {
        let names = PathComponents.of(url.path(percentEncoded: false))
        return names.contains(".Trash") || names.contains(".Trashes")
    }

    /// The identifiers of the apps Spotlight has indexed whose identifier begins with one of `prefixes`, wherever they
    /// are, such as every app of one maker. Empty when Spotlight is off, has none, or does not answer within `budget`,
    /// and when a prefix is not made of an identifier's characters, since each goes into the query as it is.
    static func indexedIdentifiers(
        beginningWith prefixes: [String],
        within budget: TimeInterval = spotlightBudget
    ) async -> Set<String> {
        let isAnIdentifiersStart = { (prefix: String) in
            !prefix.isEmpty && prefix.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
        }
        guard !prefixes.isEmpty, prefixes.allSatisfy(isAnIdentifiersStart) else { return [] }
        let identifiers = prefixes.map { "kMDItemCFBundleIdentifier == \"\($0)*\"c" }.joined(separator: " || ")
        let text = "kMDItemContentTypeTree == \"com.apple.application-bundle\" && (\(identifiers))"
        let found = await SlowRead.answer(within: budget) { _ -> Set<String> in
            guard let query = MDQueryCreate(kCFAllocatorDefault, text as CFString, nil, nil),
                  MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue))
            else { return [] }
            return Set((0..<MDQueryGetResultCount(query)).compactMap { index in
                guard let result = MDQueryGetResultAtIndex(query, index) else { return nil }
                return MDItemCopyAttribute(Unmanaged<MDItem>.fromOpaque(result).takeUnretainedValue(), kMDItemCFBundleIdentifier) as? String
            })
        }
        return found ?? []
    }

    /// How long a scan waits for Spotlight. It answers a query on one attribute at once unless it is rebuilding its
    /// index, and a scan can do without the apps it would name.
    private static let spotlightBudget: TimeInterval = 2

    public static func inspect(_ url: URL) -> InstalledApp? {
        let contents = url.appending(path: "Contents", directoryHint: .isDirectory)
        guard
            let info = infoDictionary(in: contents),
            let bundleIdentifier = info["CFBundleIdentifier"] as? String,
            !bundleIdentifier.isEmpty
        else { return nil }

        let signing = signingInformation(for: url)
        let executable = (info["CFBundleExecutable"] as? String).map {
            contents.appending(path: "MacOS", directoryHint: .isDirectory).appending(path: $0)
        }
        let isFromAppStore = FileManager.default.fileExists(
            atPath: contents.appending(path: "_MASReceipt/receipt").path(percentEncoded: false)
        )
        let isSystemProtected = isSystemProtected(url)
        let use = use(of: url)

        return InstalledApp(
            url: url,
            bundleIdentifier: bundleIdentifier,
            name: displayName(of: url),
            bundleName: info["CFBundleName"] as? String,
            // Falls back to the build number when the short version is empty or is not a string, such as a number.
            version: (info["CFBundleShortVersionString"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? info["CFBundleVersion"] as? String,
            buildVersion: info["CFBundleVersion"] as? String,
            teamIdentifier: signing.teamIdentifier,
            developer: signing.developer,
            applicationGroups: signing.applicationGroups,
            embeddedBundleIdentifiers: embeddedBundleIdentifiers(in: contents),
            architectures: executable.map(MachOHeader.architectures(ofExecutableAt:)) ?? [],
            isFromAppStore: isFromAppStore,
            isSystemProtected: isSystemProtected,
            enclosingPackage: url.enclosingPackage,
            lastUsedDate: use.lastUsedDate,
            isUseRecorded: use.isRecorded,
            dateAdded: dateAdded(of: url),
            updateFeed: UpdateFeed.detect(info: info, contents: contents, isFromAppStore: isFromAppStore, isSystemProtected: isSystemProtected)
        )
    }

    private static let embeddedBundleDirectories = [
        "Library/LoginItems",
        "Library/SystemExtensions",
        "PlugIns",
        "Extensions",
        "XPCServices",
        "Helpers",
        "Frameworks",
    ]

    private static let embeddedBundleExtensions: Set<String> = ["app", "appex", "xpc", "systemextension"]

    static func infoDictionary(in contents: URL) -> [String: Any]? {
        guard let data = BoundedRead.data(at: contents.appending(path: "Info.plist")) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    /// The name Finder shows for a bundle, in the user's language when the app translates its name.
    public static func displayName(of url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    private static func signingInformation(for url: URL) -> (teamIdentifier: String?, developer: String?, applicationGroups: [String]) {
        guard let information = CodeSignature.information(at: url) else { return (nil, nil, []) }
        let team = information[kSecCodeInfoTeamIdentifier as String] as? String
        let leaf = (information[kSecCodeInfoCertificates as String] as? [SecCertificate])?.first
        return (
            team,
            leaf.flatMap { SecCertificateCopySubjectSummary($0) as String? }.flatMap { CodeSignature.developer(fromLeaf: $0, team: team) },
            applicationGroups(in: information)
        )
    }

    /// The application groups the bundle's checked signature claims.
    static func applicationGroups(at url: URL) -> [String] {
        CodeSignature.information(at: url).map(applicationGroups(in:)) ?? []
    }

    private static func applicationGroups(in information: [String: Any]) -> [String] {
        let entitlements = information[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        return entitlements?["com.apple.security.application-groups"] as? [String] ?? []
    }

    private static func embeddedBundleIdentifiers(in contents: URL) -> [String] {
        let fileManager = FileManager.default
        var identifiers: [String] = []

        for directory in embeddedBundleDirectories {
            let folder = contents.appending(path: directory, directoryHint: .isDirectory)
            guard let children = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
                continue
            }
            for child in children where embeddedBundleExtensions.contains(child.pathExtension.lowercased()) {
                let childContents = child.appending(path: "Contents", directoryHint: .isDirectory)
                if let identifier = infoDictionary(in: childContents)?["CFBundleIdentifier"] as? String {
                    identifiers.append(identifier)
                }
            }
        }

        let launchServices = contents.appending(path: "Library/LaunchServices", directoryHint: .isDirectory)
        if let helpers = try? fileManager.contentsOfDirectory(atPath: launchServices.path(percentEncoded: false)) {
            identifiers += helpers.filter { $0.split(separator: ".").count >= 3 }
        }

        for directory in ["Library/LaunchAgents", "Library/LaunchDaemons"] {
            let folder = contents.appending(path: directory, directoryHint: .isDirectory)
            guard let plists = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
                continue
            }
            for plist in plists where plist.pathExtension == "plist" {
                guard let label = BoundedRead.propertyList(at: plist)?["Label"] as? String else { continue }
                identifiers.append(label)
            }
        }

        return Array(Set(identifiers)).sorted()
    }

    private static func isSystemProtected(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path(percentEncoded: false), &info) == 0 else { return false }
        return info.st_flags & UInt32(SF_RESTRICTED) != 0
    }

    /// When the app was last opened, and whether Spotlight records it at all. An item outside Spotlight's index holds
    /// only what the file system says (`kMDItemFS…`), yet asked for its last used date it answers with its
    /// modification date. So the date is read only when the item holds it, and the index holds the item when it holds
    /// a content type.
    static func use(of url: URL) -> (lastUsedDate: Date?, isRecorded: Bool) {
        guard
            let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
            let names = MDItemCopyAttributeNames(item) as? [String]
        else { return (nil, false) }
        let lastUsedDate = names.contains(kMDItemLastUsedDate as String)
            ? MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
            : nil
        return (lastUsedDate, names.contains(kMDItemContentType as String))
    }

    /// When the app appeared in its folder, which is the closest thing to an install date.
    private static func dateAdded(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate
    }
}
