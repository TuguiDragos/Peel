public import Foundation
internal import PeelPrivileged

/// Some apps ship their own uninstaller, install through a package, or carry a system extension.
/// Peel points at those instead of guessing, because the vendor's own tool knows more than any scanner.
public enum VendorRemoval {
    /// An uninstaller for `app`: one inside its bundle or beside it, or else one named for the app in the
    /// folders where makers keep their uninstallers.
    public static func uninstaller(for app: InstalledApp, applicationsFolders: [URL] = AppCatalog.defaultDirectories) -> URL? {
        shippedOrBeside(app) ?? namedForIt(app, in: applicationsFolders)
    }

    private static func shippedOrBeside(_ app: InstalledApp) -> URL? {
        let fileManager = FileManager.default
        let insideBundle = ["Contents/Resources", "Contents/MacOS", "Contents/Helpers"].map {
            app.url.appending(path: $0, directoryHint: .isDirectory)
        }
        let parent = app.url.deletingLastPathComponent()
        // Inside the bundle, an uninstaller is the app's own even without the app's name. Beside the bundle it
        // must carry the app's name, because a vendor's folder holds its other products and their uninstallers.
        let folders = insideBundle.map { ($0, true) } + (isApplicationsFolder(parent) ? [] : [(parent, false)])

        for (folder, isInsideTheBundle) in folders {
            let names = (try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
            if let match = names.sorted().first(where: { isUninstallerName($0, app: app, isInsideTheBundle: isInsideTheBundle) }) {
                return folder.appending(path: match)
            }
        }
        return nil
    }

    /// An uninstaller named for `app` at the top of an Applications folder (Chrome Remote Desktop Host
    /// Uninstaller), in its `Utilities` folder, or in a maker's folder inside `Utilities` (Adobe Installers).
    /// These folders hold every maker's uninstallers, so the name must be the app's name plus only the word
    /// Uninstall or Uninstaller: Uninstall Photoshop contains "Photos" but is not an uninstaller for Photos.
    private static func namedForIt(_ app: InstalledApp, in applicationsFolders: [URL]) -> URL? {
        let fileManager = FileManager.default
        let utilities = applicationsFolders.map { $0.appending(path: "Utilities", directoryHint: .isDirectory) }
        let makers = utilities.flatMap { folder in
            ((try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
                .filter { $0.pathExtension != "app" && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        }
        for folder in applicationsFolders + utilities + makers {
            let names = (try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
            if let match = names.sorted().first(where: { isUninstallerNamedExactly($0, for: app) }) {
                return folder.appending(path: match)
            }
        }
        return nil
    }

    static func isUninstallerNamedExactly(_ name: String, for app: InstalledApp) -> Bool {
        guard name.lowercased().hasSuffix(".app") else { return false }
        let words = name.dropLast(4).lowercased().split(separator: " ")
        let rest = words.filter { $0 != "uninstall" && $0 != "uninstaller" }
        guard rest.count < words.count, !rest.isEmpty else { return false }
        let named = rest.joined(separator: " ")
        return app.names.contains { $0.lowercased() == named }
    }

    static func isUninstallerName(_ name: String, app: InstalledApp, isInsideTheBundle: Bool = true) -> Bool {
        guard name.hasSuffix(".app") else { return false }
        let lowercased = name.lowercased()
        guard lowercased.contains("uninstall") else { return false }
        let base = lowercased.replacingOccurrences(of: ".app", with: "")
        guard !app.names.contains(where: { base.contains($0.lowercased()) }) else { return true }
        return isInsideTheBundle && (base.hasPrefix("uninstall") || base.hasSuffix("uninstaller"))
    }

    /// Whether `url` is an Applications folder. A folder URL's path ends in a slash, so the path is read through
    /// `comparablePath`.
    static func isApplicationsFolder(_ url: URL) -> Bool {
        let path = PathPattern.comparablePath(of: url)
        return path == "/Applications" || path.hasSuffix("/Applications")
    }

    /// The system extensions and DriverKit extensions inside the app's bundle. macOS manages them, so moving
    /// files does not remove them.
    public static func systemExtensions(in app: InstalledApp) -> [String] {
        let folder = app.url.appending(path: "Contents/Library/SystemExtensions", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasSuffix(".systemextension") || $0.hasSuffix(".dext") }.sorted()
    }

    /// What a package installed outside the app's bundle and is still there, folders included: a support folder
    /// is the most common thing a package leaves outside. Items another receipt also lists are left out, since
    /// they are not this package's alone.
    public static func filesOutsideBundle(of receipt: PackageReceipt, app: InstalledApp, otherReceipts: [PackageReceipt]) -> [PackageReceipt.Item] {
        // Compared as paths: the catalog writes an app's URL with a trailing slash, and a receipt's items without.
        let bundle = PathPattern.comparablePath(of: app.url)
        let claimedElsewhere = Set(otherReceipts.filter { $0.identifier != receipt.identifier }.flatMap(\.items).map { PathPattern.comparablePath(of: $0.url) })
        return receipt.items.filter { item in
            let path = PathPattern.comparablePath(of: item.url)
            guard !PathComponents.isPath(path, atOrInside: bundle) else { return false }
            return !claimedElsewhere.contains(path) && item.url.isThere
        }
    }
}
