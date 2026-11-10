public import Foundation
internal import PeelPrivileged

/// Some apps ship their own uninstaller or install through a package. Peel points at those instead of guessing,
/// because the vendor's own tool knows more than any scanner.
public enum VendorRemoval {
    /// An uninstaller for `app`: one inside its bundle or beside it, or else one named for the app in the
    /// folders where makers keep their uninstallers. Outside the bundle, a name says nothing of who made it, and other
    /// programs can write those folders, so one counts only when `isTheMakers` says so.
    public static func uninstaller(
        for app: InstalledApp,
        applicationsFolders: [URL] = AppCatalog.defaultDirectories
    ) -> URL? {
        uninstaller(for: app, applicationsFolders: applicationsFolders, isTheMakers: isSignedByTheSameTeam)
    }

    static func uninstaller(
        for app: InstalledApp,
        applicationsFolders: [URL],
        isTheMakers: (URL, InstalledApp) -> Bool
    ) -> URL? {
        shippedOrBeside(app, applicationsFolders: applicationsFolders, isTheMakers: isTheMakers)
            ?? namedForIt(app, in: applicationsFolders, isTheMakers: isTheMakers)
    }

    /// Whether the uninstaller at `url` is signed by `app`'s team, as its checked signature says.
    static func isSignedByTheSameTeam(_ url: URL, as app: InstalledApp) -> Bool {
        guard let team = app.teamIdentifier else { return false }
        return CodeSignature.teamIdentifier(at: url) == team
    }

    private static func shippedOrBeside(
        _ app: InstalledApp, applicationsFolders: [URL], isTheMakers: (URL, InstalledApp) -> Bool
    ) -> URL? {
        let fileManager = FileManager.default
        let insideBundle = ["Contents/Resources", "Contents/MacOS", "Contents/Helpers"].map {
            app.url.appending(path: $0, directoryHint: .isDirectory)
        }
        let parent = app.url.deletingLastPathComponent()
        // Inside the bundle, an uninstaller is the app's own even without the app's name. Beside the bundle it
        // must be named for the app exactly, because a vendor's folder holds its other products and their
        // uninstallers: Uninstall Acme Pro holds Acme's name and is not Acme's.
        let isEveryMakers = isApplicationsFolder(parent) || applicationsFolders.contains {
            PathPattern.comparablePath(of: $0) == PathPattern.comparablePath(of: parent)
        }
        let folders = insideBundle.map { ($0, true) } + (isEveryMakers ? [] : [(parent, false)])

        for (folder, isInsideTheBundle) in folders {
            let names = (try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
            let isTheAppsUninstaller = { (name: String) in
                guard !isInsideTheBundle else { return isUninstallerName(name, app: app) }
                let isNamedForIt = isUninstallerNamedExactly(name, for: app)
                    || isUninstaller(name, ofTheProductIn: folder, for: app)
                return isNamedForIt && isTheMakers(folder.appending(path: name), app)
            }
            if let match = names.sorted().first(where: isTheAppsUninstaller) {
                return folder.appending(path: match)
            }
        }
        return nil
    }

    /// An uninstaller named for `app` at the top of an Applications folder (Chrome Remote Desktop Host
    /// Uninstaller), in its `Utilities` folder, or in a maker's folder inside `Utilities` (Adobe Installers).
    /// These folders hold every maker's uninstallers, so the name must be the app's name plus only the word
    /// Uninstall or Uninstaller: Uninstall Photoshop contains "Photos" but is not an uninstaller for Photos.
    private static func namedForIt(
        _ app: InstalledApp, in applicationsFolders: [URL], isTheMakers: (URL, InstalledApp) -> Bool
    ) -> URL? {
        let fileManager = FileManager.default
        let utilities = applicationsFolders.map { $0.appending(path: "Utilities", directoryHint: .isDirectory) }
        let makers = utilities.flatMap { folder in
            ((try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
                .filter {
                    $0.pathExtension != "app"
                        && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                }
        }
        for folder in applicationsFolders + utilities + makers {
            let names = (try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
            // A maker's folder named for the app holds its uninstaller under no name at all, as Krisp's does.
            let isTheAppsOwn = makers.contains(folder)
                && app.names.contains { $0.lowercased() == folder.lastPathComponent.lowercased() }
            let isTheAppsUninstaller = { (name: String) in
                (isUninstallerNamedExactly(name, for: app) || isTheAppsOwn && uninstalledName(name) == "")
                    && isTheMakers(folder.appending(path: name), app)
            }
            if let match = names.sorted().first(where: isTheAppsUninstaller) {
                return folder.appending(path: match)
            }
        }
        return nil
    }

    static func isUninstallerNamedExactly(_ name: String, for app: InstalledApp) -> Bool {
        guard let named = uninstalledName(name), !named.isEmpty else { return false }
        return app.names.contains { $0.lowercased() == named }
    }

    /// Whether `name` uninstalls the product a folder of its own is named for, as TurboVNC's `Uninstall TurboVNC`
    /// sits beside `TurboVNC Viewer`: only for an app whose name begins with the folder's.
    static func isUninstaller(_ name: String, ofTheProductIn folder: URL, for app: InstalledApp) -> Bool {
        let product = folder.lastPathComponent.lowercased()
        guard !product.isEmpty, uninstalledName(name) == product else { return false }
        let words = product.split(separator: " ")
        return app.names.contains { $0.lowercased().split(separator: " ").starts(with: words) }
    }

    /// What an uninstaller's name says it removes, lowercased: its words but Uninstall and Uninstaller, empty for
    /// one called only that, and nil for a name without either word or for no app.
    private static func uninstalledName(_ name: String) -> String? {
        guard name.lowercased().hasSuffix(".app") else { return nil }
        let words = name.dropLast(4).lowercased().split(separator: " ")
        let rest = words.filter { $0 != "uninstall" && $0 != "uninstaller" }
        return rest.count < words.count ? rest.joined(separator: " ") : nil
    }

    static func isUninstallerName(_ name: String, app: InstalledApp) -> Bool {
        guard name.hasSuffix(".app") else { return false }
        let lowercased = name.lowercased()
        guard lowercased.contains("uninstall") else { return false }
        let base = lowercased.replacingOccurrences(of: ".app", with: "")
        guard !app.names.contains(where: { base.contains($0.lowercased()) }) else { return true }
        return base.hasPrefix("uninstall") || base.hasSuffix("uninstaller")
    }

    /// Whether `url` is an Applications folder. A folder URL's path ends in a slash, so the path is read through
    /// `comparablePath`.
    static func isApplicationsFolder(_ url: URL) -> Bool {
        let path = PathPattern.comparablePath(of: url)
        return path == "/Applications" || path.hasSuffix("/Applications")
    }

    /// What a package installed outside the app's bundle and is still there, folders included: a support folder
    /// is the most common thing a package leaves outside. Items another receipt also lists are left out, since
    /// they are not this package's alone.
    public static func filesOutsideBundle(
        of receipt: PackageReceipt,
        app: InstalledApp,
        otherReceipts: [PackageReceipt]
    ) -> [PackageReceipt.Item] {
        // Compared as paths: the catalog writes an app's URL with a trailing slash, and a receipt's items without.
        let bundle = PathPattern.comparablePath(of: app.url)
        let claimedElsewhere = Set(
            otherReceipts.filter { $0.identifier != receipt.identifier }.flatMap(\.items)
                .map { PathPattern.comparablePath(of: $0.url) }
        )
        return receipt.items.filter { item in
            let path = PathPattern.comparablePath(of: item.url)
            guard !PathComponents.isPath(path, atOrInside: bundle) else { return false }
            return !claimedElsewhere.contains(path) && item.url.isThere
        }
    }
}
