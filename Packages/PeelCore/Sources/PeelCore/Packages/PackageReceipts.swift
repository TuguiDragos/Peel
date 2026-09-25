public import Foundation
internal import PeelPrivileged

public enum PackageReceipts {
    private static let concurrentReceipts = 4

    /// Directories many packages install into; they never belong to a single package.
    static let sharedDirectories: Set<String> = [
        "/", "/Applications", "/Applications/Utilities", "/Library", "/Library/Application Support", "/Library/Audio",
        "/Library/Audio/Plug-Ins", "/Library/Audio/Plug-Ins/Components", "/Library/Audio/Plug-Ins/HAL",
        "/Library/Audio/Plug-Ins/VST", "/Library/Audio/Plug-Ins/VST3", "/Library/Caches", "/Library/ColorSync",
        "/Library/ColorSync/Profiles", "/Library/Extensions", "/Library/Fonts", "/Library/Frameworks",
        "/Library/Input Methods", "/Library/Internet Plug-Ins", "/Library/LaunchAgents", "/Library/LaunchDaemons",
        "/Library/Logs", "/Library/PreferencePanes", "/Library/Preferences", "/Library/Printers",
        "/Library/PrivilegedHelperTools", "/Library/QuickLook", "/Library/Screen Savers", "/Library/Services",
        "/Library/Spotlight", "/Library/SystemExtensions", "/System", "/Users", "/Users/Shared", "/etc", "/opt",
        "/private", "/private/etc", "/private/tmp", "/private/var", "/tmp", "/usr", "/usr/local", "/usr/local/bin",
        "/usr/local/etc", "/usr/local/include", "/usr/local/lib", "/usr/local/libexec", "/usr/local/sbin",
        "/usr/local/share", "/usr/local/share/doc", "/usr/local/share/man", "/usr/local/share/man/man1", "/var",
    ]

    /// Returns whether `receipt` is the installer receipt of the app whose bundle identifier is `identifier`:
    /// the identifier itself, or the identifier followed by `.`, `-`, or `_`. A shared prefix is not enough,
    /// so `com.adguard.mac.vpn-pkg` (AdGuard VPN) never proves `com.adguard.mac.adguard` (AdGuard), and
    /// `com.example.app2.pkg` never proves `com.example.app`. Both arguments must be in lowercase.
    public static func proves(_ receipt: String, isThe identifier: String) -> Bool {
        guard !identifier.isEmpty else { return false }
        return receipt == identifier || [".", "-", "_"].contains { receipt.hasPrefix(identifier + $0) }
    }

    /// Returns the identifiers of all installed packages, in lowercase, without reading each receipt. That is
    /// enough to find an app's own receipt and to tell whether a cask really belongs to an app.
    @concurrent
    public static func identifiers() async -> Set<String> {
        Set((packageList(in: await pkgutil(["--pkgs-plist"])) ?? []).map { $0.lowercased() })
    }

    /// Reads what `pkgutil --pkgs-plist` prints: an array of package identifiers. Nil for no answer, or an answer
    /// in any other form, which says nothing about what is installed.
    static func packageList(in answer: String?) -> [String]? {
        guard let answer else { return nil }
        return (try? PropertyListSerialization.propertyList(from: Data(answer.utf8), format: nil)) as? [String]
    }

    /// Nil when the tool could not be run, failed, or timed out: no answer is not "nothing installed".
    typealias Pkgutil = @Sendable ([String]) async -> String?

    public static func list(exclusions: Exclusions = .none) async -> PackageScan {
        await list(exclusions: exclusions, pkgutil: pkgutil)
    }

    /// Lists every installed package except Apple's, sorted by identifier. `pkgutil` is a parameter so a test
    /// can say what is installed instead of asking the real tool.
    @concurrent
    static func list(exclusions: Exclusions, pkgutil: @escaping Pkgutil, environment: SearchEnvironment = .current) async -> PackageScan {
        let removalGuard = RemovalGuard(environment: environment, exclusions: exclusions)
        let reach = HelperReach(environment: environment)
        guard let packages = packageList(in: await pkgutil(["--pkgs-plist"])) else {
            return PackageScan(receipts: [], couldNotAsk: true)
        }
        let identifiers = packages.filter { !$0.hasPrefix("com.apple.") }

        let receipts = await withTaskGroup(of: PackageReceipt.self) { group in
            var pending = identifiers.makeIterator()
            var results: [PackageReceipt] = []
            for _ in 0..<concurrentReceipts {
                guard let identifier = pending.next() else { break }
                group.addTask { await Self.receipt(identifier, exclusions: exclusions, pkgutil: pkgutil, removalGuard: removalGuard, reach: reach).receipt }
            }
            while let result = await group.next() {
                results.append(result)
                if let identifier = pending.next() {
                    group.addTask { await Self.receipt(identifier, exclusions: exclusions, pkgutil: pkgutil, removalGuard: removalGuard, reach: reach).receipt }
                }
            }
            return results
        }
        return PackageScan(receipts: receipts.sorted { $0.identifier.localizedStandardCompare($1.identifier) == .orderedAscending })
    }

    /// Returns the receipts of the packages that installed `url`, asking `pkgutil` about that one path instead
    /// of listing every package.
    @concurrent
    public static func receipts(installing url: URL, exclusions: Exclusions = .none) async -> [PackageReceipt] {
        await receipts(installing: url, exclusions: exclusions, pkgutil: pkgutil)
    }

    /// `pkgutil --file-info-plist` matches a path against the receipt's file list, which is relative to the
    /// package's install location: with the install location `Applications`, an app is found as `/Example.app`. So
    /// the leading folders are dropped one at a time until a package answers, and the answer counts only if that
    /// package really installed this path.
    @concurrent
    static func receipts(installing url: URL, exclusions: Exclusions, pkgutil: @escaping Pkgutil) async -> [PackageReceipt] {
        let wanted = PathPattern.comparablePath(of: PathPattern.canonical(url))
        var identifiers: Set<String> = []
        for path in Self.spellings(of: wanted) where identifiers.isEmpty && !Task.isCancelled {
            identifiers = Set(Self.packageIdentifiers(in: await pkgutil(["--file-info-plist", path])))
        }

        var receipts: [PackageReceipt] = []
        let removalGuard = RemovalGuard(environment: .current, exclusions: exclusions)
        let reach = HelperReach(environment: .current)
        for identifier in identifiers.sorted() where !Task.isCancelled {
            let found = await receipt(identifier, exclusions: exclusions, pkgutil: pkgutil, removalGuard: removalGuard, reach: reach)
            guard found.installs(wanted) else { continue }
            receipts.append(found.receipt)
        }
        return receipts
    }

    /// Returns `path`, then the same path with its leading folders dropped one at a time (`/a/b/c`, `/b/c`,
    /// `/c`), since a receipt lists what it installed relative to its install location. Any of these can also
    /// match another package's file, so each answer is checked against what that package really installed.
    static func spellings(of path: String) -> [String] {
        let components = PathComponents.of(path)
        return (0..<max(1, components.count)).map { "/" + components.dropFirst($0).joined(separator: "/") }
    }

    /// Reads what `pkgutil --file-info-plist` prints: a `path-info` array with the `pkgid` of each package that
    /// lists the path. Apple's own packages are left out.
    static func packageIdentifiers(in answer: String?) -> [String] {
        guard let answer,
              let plist = try? PropertyListSerialization.propertyList(from: Data(answer.utf8), format: nil),
              let packages = (plist as? [String: Any])?["path-info"] as? [[String: Any]] else { return [] }
        return packages.compactMap { $0["pkgid"] as? String }.filter { !$0.hasPrefix("com.apple.") }
    }

    /// A receipt and the full paths of everything it lists, so `installs(_:)` can tell whether it installed a path.
    struct Found {
        let receipt: PackageReceipt
        let paths: [String]

        func installs(_ path: String) -> Bool {
            paths.contains { PathPattern.comparablePath(of: PathPattern.canonical(URL(filePath: $0))) == path }
        }
    }

    private static func receipt(_ identifier: String, exclusions: Exclusions = .none, pkgutil: Pkgutil, removalGuard: RemovalGuard, reach: HelperReach) async -> Found {
        guard
            let data = await pkgutil(["--pkg-info-plist", identifier])?.data(using: .utf8),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            // `pkgutil` named the package but did not describe it. It stays listed, with what it installed unknown,
            // rather than vanishing from the page.
            let unknown = PackageReceipt(
                identifier: identifier, version: nil, installDate: nil, volume: URL(filePath: "/", directoryHint: .isDirectory),
                items: [], nothingLeftOnDisk: false, isFileListKnown: false
            )
            return Found(receipt: unknown, paths: [])
        }

        let volume = URL(filePath: info["volume"] as? String ?? "/", directoryHint: .isDirectory)
        let location = info["install-location"] as? String ?? ""
        let installLocation = volume.appending(path: location, directoryHint: .isDirectory)
        let listing = await pkgutil(["--files", identifier])
        let files = (listing ?? "").split(whereSeparator: \.isNewline).map(String.init)

        let found = topLevel(files: files, installLocation: installLocation.path(percentEncoded: false))
        var items: [PackageReceipt.Item] = []
        var seen: Set<String> = []
        for path in found.offered {
            // `located` resolves the folders on the way but not the last component: when a receipt lists a
            // link, the item is the link itself, not what it leads to.
            let url = URL(filePath: PathPattern.located(path) ?? path)
            guard !exclusions.excludes(url), seen.insert(PathPattern.comparablePath(of: url)).inserted else { continue }
            let requiresPrivileges = FileAccess.requiresPrivilegesToRemove(url)
            items.append(PackageReceipt.Item(
                url: url,
                size: await FileSize.measure(url),
                requiresPrivileges: requiresPrivileges,
                isLeftAlone: !removalGuard.allowsRemoval(of: url) || (requiresPrivileges && reach.isBeyond(url))
            ))
        }

        return Found(
            receipt: PackageReceipt(
                identifier: identifier,
                version: info["pkg-version"] as? String,
                installDate: (info["install-time"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) },
                volume: volume,
                items: items,
                // Judged from the disk: `items` leaves out what is excluded or protected, even while it is there.
                nothingLeftOnDisk: listing != nil && found.onDisk.isEmpty,
                isFileListKnown: listing != nil
            ),
            paths: files.map { file in
                let relative = file.hasPrefix("./") ? String(file.dropFirst(2)) : file
                return installLocation.appending(path: relative).path(percentEncoded: false)
            }
        )
    }

    /// How many levels deep the search goes into a folder that also holds files this package did not install.
    private static let deepestDescent = 6

    /// Returns the outermost existing paths that are this package's own, never a shared directory such as
    /// `/Library`. `onDisk` holds all of them. `offered` leaves out protected data (`ProtectedData.refuses`),
    /// which Peel never lists at all.
    static func topLevel(
        files: [String],
        installLocation: String,
        home: String = URL.homeDirectory.path(percentEncoded: false),
        namesInside: (String) -> [String]? = { try? FileManager.default.contentsOfDirectory(atPath: $0) },
        exists: (String) -> Bool = { URL(filePath: $0).isThere }
    ) -> (onDisk: [String], offered: [String]) {
        let root = (installLocation as NSString).standardizingPath
        let paths = files.map { file -> String in
            let relative = file.hasPrefix("./") ? String(file.dropFirst(2)) : file
            return ((root as NSString).appendingPathComponent(relative) as NSString).standardizingPath
        }
        let listed = Set(paths)
        // A Mac disk is case-insensitive unless formatted otherwise, so `library/...` in a receipt is `/Library`.
        let shared = Set(sharedDirectories.map { $0.lowercased() })
        let isShared = { (path: String) in shared.contains(path.lowercased()) }

        let outermost = Set(paths.filter { path in
            guard !isShared(path), path != root else { return false }
            let parent = (path as NSString).deletingLastPathComponent
            return parent == root || isShared(parent) || !listed.contains(parent)
        })
        .filter(exists)

        let onDisk = outermost
            .flatMap { onlyWhatThisPackageWrote($0, listed: listed, namesInside: namesInside) }
            .sorted()
        return (onDisk, onDisk.filter { !ProtectedData.refuses($0, home: home) })
    }

    /// Returns `path` when this package installed everything inside it, and otherwise the parts inside it that
    /// the package did install, so a vendor folder that two of its products share is never offered whole. A
    /// bundle is always one item: an app that updated itself does not match its receipt file by file, and
    /// its parts are never listed on their own.
    static func onlyWhatThisPackageWrote(
        _ path: String,
        listed: Set<String>,
        namesInside: (String) -> [String]?,
        depth: Int = 0
    ) -> [String] {
        guard (path as NSString).pathExtension.isEmpty, depth < deepestDescent else { return [path] }
        guard let names = namesInside(path) else { return [path] }
        let inside = names.map { (path as NSString).appendingPathComponent($0) }
        let folded = Set(listed.map { $0.lowercased() })
        guard inside.contains(where: { !folded.contains($0.lowercased()) }) else { return [path] }
        let own = inside.filter { folded.contains($0.lowercased()) }
        // Nothing inside is listed: the package installed the folder and something else filled it, so the
        // folder is still the only thing this receipt can name.
        guard !own.isEmpty else { return [path] }
        return own.flatMap { onlyWhatThisPackageWrote($0, listed: listed, namesInside: namesInside, depth: depth + 1) }
    }

    /// A tool that could not be run, or that failed, says nothing about what is installed.
    private static func pkgutil(_ arguments: [String]) async -> String? {
        guard case .success(let output) = await Subprocess.run("/usr/sbin/pkgutil", arguments, timeout: 30) else { return nil }
        return output.status == 0 ? output.text : nil
    }
}
