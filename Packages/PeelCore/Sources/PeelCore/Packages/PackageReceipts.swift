public import Foundation
internal import PeelPrivileged

public enum PackageReceipts {
    static let concurrentReceipts = 4

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

    /// The identifier among `identifiers` whose app `receipt` belongs to: the longest that proves it, since a receipt
    /// named for one identifier and a separator can carry on into another app's (`…synth-fx.app.pkg` is Synth FX's,
    /// not Synth's). All in lowercase.
    public static func owner(of receipt: String, among identifiers: some Sequence<String>) -> String? {
        identifiers.filter { proves(receipt, isThe: $0) }.max { $0.count < $1.count }
    }

    /// Returns the identifiers of all installed packages, in lowercase, without reading each receipt. That is
    /// enough to find an app's own receipt and to tell whether a cask really belongs to an app.
    @concurrent
    public static func identifiers() async -> Set<String> {
        await identifiers(pkgutil: pkgutil)
    }

    static func identifiers(pkgutil: Pkgutil) async -> Set<String> {
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
    static func list(
        exclusions: Exclusions,
        pkgutil: @escaping Pkgutil,
        environment: SearchEnvironment = .current,
        systemExtensions: @escaping AppExtensions.SystemExtensionsAnswer = AppExtensions.askingMacOS
    ) async -> PackageScan {
        let removalGuard = RemovalGuard(environment: environment, exclusions: exclusions)
        let reach = HelperReach(environment: environment)
        let shared = sharedFolders(in: environment)
        let installed = InstalledSystemExtensions(asking: systemExtensions)
        guard let packages = packageList(in: await pkgutil(["--pkgs-plist"])) else {
            return PackageScan(receipts: [], couldNotAsk: true)
        }
        let identifiers = packages.filter { !$0.hasPrefix("com.apple.") }

        let receipts = await withTaskGroup(of: PackageReceipt.self) { group in
            var pending = identifiers.makeIterator()
            var results: [PackageReceipt] = []
            for _ in 0..<concurrentReceipts {
                guard let identifier = pending.next() else { break }
                group.addTask {
                    await Self.receipt(
                        identifier,
                        exclusions: exclusions,
                        pkgutil: pkgutil,
                        removalGuard: removalGuard,
                        reach: reach,
                        shared: shared,
                        installed: installed,
                        environment: environment
                    ).receipt
                }
            }
            while let result = await group.next() {
                results.append(result)
                if let identifier = pending.next() {
                    group.addTask {
                        await Self.receipt(
                            identifier,
                            exclusions: exclusions,
                            pkgutil: pkgutil,
                            removalGuard: removalGuard,
                            reach: reach,
                            shared: shared,
                            installed: installed,
                            environment: environment
                        ).receipt
                    }
                }
            }
            return results
        }
        return PackageScan(
            receipts: receipts.sorted { $0.identifier.localizedStandardCompare($1.identifier) == .orderedAscending }
        )
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
    static func receipts(
        installing url: URL,
        exclusions: Exclusions,
        pkgutil: @escaping Pkgutil,
        systemExtensions: @escaping AppExtensions.SystemExtensionsAnswer = AppExtensions.askingMacOS
    ) async -> [PackageReceipt] {
        let wanted = PathPattern.comparablePath(of: PathPattern.canonical(url))
        var identifiers: Set<String> = []
        for path in Self.spellings(of: wanted) where identifiers.isEmpty && !Task.isCancelled {
            identifiers = Set(Self.packageIdentifiers(in: await pkgutil(["--file-info-plist", path])))
        }

        var receipts: [PackageReceipt] = []
        let removalGuard = RemovalGuard(environment: .current, exclusions: exclusions)
        let reach = HelperReach(environment: .current)
        let shared = sharedFolders(in: .current)
        let installed = InstalledSystemExtensions(asking: systemExtensions)
        for identifier in identifiers.sorted() where !Task.isCancelled {
            let found = await receipt(
                identifier,
                exclusions: exclusions,
                pkgutil: pkgutil,
                removalGuard: removalGuard,
                reach: reach,
                shared: shared,
                installed: installed,
                environment: .current
            )
            guard found.installs(wanted) else { continue }
            receipts.append(found.receipt)
        }
        return receipts
    }

    /// The packages that wrote `app` and nothing outside it, the folders on the way to it aside. Once the app is gone,
    /// such a receipt describes nothing on the disk. A receipt lists its files relative to its install location, and
    /// they are compared name by name in that form, since most of them need not exist.
    static func receipts(writingOnly app: URL, pkgutil: Pkgutil) async -> [String] {
        let bundle = PathPattern.canonical(app)
        let spellings = Self.spellings(of: PathPattern.comparablePath(of: bundle))
        var identifiers: Set<String> = []
        for path in spellings where identifiers.isEmpty && !Task.isCancelled {
            identifiers = Set(Self.packageIdentifiers(in: await pkgutil(["--file-info-plist", path])))
        }
        let names = PathComponents.of(bundle.path(percentEncoded: false))
        var found: [String] = []
        for identifier in identifiers.sorted() where !Task.isCancelled {
            guard let (_, _, installLocation) = await description(of: identifier, pkgutil: pkgutil),
                  let listing = await pkgutil(["--files", identifier])
            else { continue }
            let location = PathComponents.of(PathPattern.canonical(installLocation).path(percentEncoded: false))
            guard names.starts(with: location) else { continue }
            let wanted = Array(names.dropFirst(location.count))
            let entries = lines(of: listing).map { PathComponents.of($0).filter { $0 != "." } }
            let isTheAppOrOnTheWay = { (entry: [String]) in entry.starts(with: wanted) || wanted.starts(with: entry) }
            if entries.contains(wanted), entries.allSatisfy(isTheAppOrOnTheWay) { found.append(identifier) }
        }
        return found
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
        installers(in: answer).filter { !$0.hasPrefix("com.apple.") }
    }

    private static func installers(in answer: String?) -> [String] {
        guard let answer,
              let plist = try? PropertyListSerialization.propertyList(from: Data(answer.utf8), format: nil),
              let packages = (plist as? [String: Any])?["path-info"] as? [[String: Any]] else { return [] }
        return packages.compactMap { $0["pkgid"] as? String }
    }

    /// Whether one of Apple's packages installed `url`: a receipt of macOS or of one of Apple's tools lists it, and
    /// that package installs at the root, the only place where the path a receipt lists is the path asked about.
    @concurrent
    public static func isInstalledByApple(_ url: URL) async -> Bool {
        await isInstalledByApple(url, pkgutil: pkgutil)
    }

    static func isInstalledByApple(_ url: URL, pkgutil: Pkgutil) async -> Bool {
        let path = PathPattern.comparablePath(of: PathPattern.canonical(url))
        let apples = installers(in: await pkgutil(["--file-info-plist", path])).filter { $0.hasPrefix("com.apple.") }
        for identifier in apples.sorted() where !Task.isCancelled {
            guard let installLocation = await description(of: identifier, pkgutil: pkgutil)?.installLocation else {
                continue
            }
            if PathPattern.comparablePath(of: installLocation) == "/" { return true }
        }
        return false
    }

    /// A receipt and the full paths of everything it lists, so `installs(_:)` can tell whether it installed a path.
    struct Found {
        let receipt: PackageReceipt
        let paths: [String]

        func installs(_ path: String) -> Bool {
            paths.contains { PathPattern.comparablePath(of: PathPattern.canonical(URL(filePath: $0))) == path }
        }
    }

    private static func receipt(
        _ identifier: String,
        exclusions: Exclusions = .none,
        pkgutil: Pkgutil,
        removalGuard: RemovalGuard,
        reach: HelperReach,
        shared: [String],
        installed: InstalledSystemExtensions,
        environment: SearchEnvironment
    ) async -> Found {
        guard let (info, volume, installLocation) = await description(of: identifier, pkgutil: pkgutil) else {
            // `pkgutil` named the package but did not describe it. It stays listed, with what it installed unknown,
            // rather than vanishing from the page.
            let unknown = PackageReceipt(
                identifier: identifier,
                version: nil,
                installDate: nil,
                volume: URL(filePath: "/", directoryHint: .isDirectory),
                items: [], nothingLeftOnDisk: false, isFileListKnown: false
            )
            return Found(receipt: unknown, paths: [])
        }

        let listing = await pkgutil(["--files", identifier])
        let files = lines(of: listing)

        let found = topLevel(files: files, installLocation: installLocation.path(percentEncoded: false))
        // An app's own rules reach the rest of its package, as they reach its files on its page.
        let apps = found.offered
            .filter { ($0 as NSString).pathExtension.caseInsensitiveCompare("app") == .orderedSame }
            .compactMap { AppInspector.inspect(URL(filePath: PathPattern.located($0) ?? $0)) }
        var removedApps: [String: RemovedElsewhere] = [:]
        for app in apps {
            let carried = await AppExtensions.installed(carriedBy: app) { await installed.answer() }
            let removed = RemovedElsewhere.of(app, installedSystemExtensions: carried)
            removedApps[PathPattern.comparablePath(of: app.url)] = removed
        }
        let removedWithItsApp = apps.lazy.compactMap { removedApps[PathPattern.comparablePath(of: $0.url)] }.first
        let uninstaller = apps.lazy.compactMap { UninstallsItself.of($0, environment: environment) }.first
        var items: [PackageReceipt.Item] = []
        var seen: Set<String> = []
        for path in found.offered {
            // `located` resolves the folders on the way but not the last component: when a receipt lists a
            // link, the item is the link itself, not what it leads to.
            let url = URL(filePath: PathPattern.located(path) ?? path)
            guard !exclusions.excludes(url), seen.insert(PathPattern.comparablePath(of: url)).inserted else { continue }
            let requiresPrivileges = FileAccess.requiresPrivilegesToRemove(url)
            let contents = await FileSize.contents(of: url)
            let place = PathPattern.comparablePath(of: url)
            let isShared = shared.contains { PathComponents.isPath(place, atOrInside: $0) }
            let isFilledByOthers = found.othersFilled.contains(path)
            let heldBack: HoldBack? = if SignInPlugIns.isOne(url, root: volume) {
                .signInPlugIn
            } else if requiresPrivileges && reach.isBeyond(url) {
                .beyondTheHelper
            } else if uninstaller?.removes(url) == true {
                .leftToItsUninstaller
            } else {
                KeptOnlyHere.reason(
                    for: url.path(percentEncoded: false), home: environment.homeDirectory.path(percentEncoded: false),
                    root: volume.path(percentEncoded: false)
                ) ?? HoldBack.seen(in: contents) ?? contents.flatMap(KeptOnlyHere.reason(seenIn:))
                    ?? (isShared ? .sharedWithEveryone : nil) ?? (isFilledByOthers ? .holdsWhatOthersPut : nil)
            }
            items.append(PackageReceipt.Item(
                url: url,
                size: contents.flatMap { $0.couldNotBeRead ? nil : $0.size },
                requiresPrivileges: requiresPrivileges,
                refusal: removalGuard.refusal(of: url),
                heldBack: heldBack,
                removedElsewhere: url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
                    ? removedApps[place] : removedWithItsApp
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
            paths: files.map { path(of: $0, in: installLocation).path(percentEncoded: false) }
        )
    }

    /// What `pkgutil --pkg-info-plist` says of a package, with the volume and the folder its file list is relative to.
    private static func description(
        of identifier: String,
        pkgutil: Pkgutil
    ) async -> (info: [String: Any], volume: URL, installLocation: URL)? {
        guard
            let data = await pkgutil(["--pkg-info-plist", identifier])?.data(using: .utf8),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        let volume = URL(filePath: info["volume"] as? String ?? "/", directoryHint: .isDirectory)
        let location = info["install-location"] as? String ?? ""
        return (info, volume, volume.appending(path: location, directoryHint: .isDirectory))
    }

    private static func path(of file: String, in installLocation: URL) -> URL {
        installLocation.appending(path: file.hasPrefix("./") ? String(file.dropFirst(2)) : file)
    }

    /// Where the packages `patterns` name wrote apps, finding the packages as Homebrew does for a cask's `pkgutil`
    /// entries: `pkgutil --pkgs=` matches each pattern against whole identifiers.
    static func apps(installedByPackagesMatching patterns: [String], pkgutil: Pkgutil) async -> [String] {
        var identifiers: Set<String> = []
        for pattern in patterns {
            identifiers.formUnion(lines(of: await pkgutil(["--pkgs=\(pattern)"])))
        }
        var apps: Set<String> = []
        for identifier in identifiers where !Task.isCancelled {
            guard let (_, _, installLocation) = await description(of: identifier, pkgutil: pkgutil) else { continue }
            for folder in lines(of: await pkgutil(["--files", identifier, "--only-dirs"])) {
                let app = path(of: folder, in: installLocation)
                if app.pathExtension.lowercased() == "app" { apps.insert(PathPattern.comparablePath(of: app)) }
            }
        }
        return apps.sorted()
    }

    private static func lines(of answer: String?) -> [String] {
        (answer ?? "").split(whereSeparator: \.isNewline).map(String.init)
    }

    /// The folders every account on the Mac uses, `/Users/Shared`, spelled to be compared.
    private static func sharedFolders(in environment: SearchEnvironment) -> [String] {
        environment.locations.filter { $0.kind == .sharedFolder }.map { PathPattern.comparablePath(of: $0.url) }
    }

    /// How many levels deep the search goes into a folder that also holds files this package did not install.
    private static let deepestDescent = 6

    /// Returns the outermost existing paths that are this package's own, never a shared directory such as
    /// `/Library`. `onDisk` holds all of them. `offered` leaves out protected data (`ProtectedData.refuses`),
    /// which Peel never lists at all. `othersFilled` holds the folders offered whole that hold what something
    /// besides this package put there.
    static func topLevel(
        files: [String],
        installLocation: String,
        home: String = URL.homeDirectory.path(percentEncoded: false),
        namesInside: (String) -> [String]? = PackageReceipts.namesInside,
        exists: (String) -> Bool = { URL(filePath: $0).isThere }
    ) -> (onDisk: [String], offered: [String], othersFilled: Set<String>) {
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

        let folded = Set(paths.map { $0.lowercased() })
        var othersFilled: Set<String> = []
        let onDisk = outermost
            .flatMap {
                onlyWhatThisPackageWrote(
                    $0, listed: folded, namesInside: namesInside, exists: exists, othersFilled: &othersFilled
                )
            }
            .sorted()
        return (onDisk, onDisk.filter { !ProtectedData.refuses($0, home: home) }, othersFilled)
    }

    /// Returns `path` when this package installed everything inside it, at any depth, and otherwise the parts
    /// inside it that the package did install, so a vendor folder that two of its products share is never offered
    /// whole. A bundle is always one item: an app that updated itself does not match its receipt file by file, and
    /// its parts are never listed on their own. `listed` holds the package's paths in lowercase.
    static func onlyWhatThisPackageWrote(
        _ path: String,
        listed: Set<String>,
        namesInside: (String) -> [String]?,
        exists: (String) -> Bool,
        depth: Int = 0,
        othersFilled: inout Set<String>
    ) -> [String] {
        guard let names = namesInside(path), !isBundle(path, exists: exists) else { return [path] }
        let inside = names.map { (path as NSString).appendingPathComponent($0) }
        let own = inside.filter { listed.contains($0.lowercased()) }
        func parts(_ depth: Int) -> [String] {
            own.flatMap {
                onlyWhatThisPackageWrote(
                    $0, listed: listed, namesInside: namesInside, exists: exists, depth: depth,
                    othersFilled: &othersFilled
                )
            }
        }
        if own.count == inside.count {
            let found = parts(depth)
            return found == own && !own.contains(where: othersFilled.contains) ? [path] : found
        }
        // Nothing inside is listed, or the search went as deep as it goes: the folder is still the only thing this
        // receipt can name, and what else is in it is not this package's.
        guard !own.isEmpty, depth < deepestDescent else {
            othersFilled.insert(path)
            return [path]
        }
        return parts(depth + 1)
    }

    /// What is inside a folder, or nil for a file or a link, which is one item whatever it leads to.
    static func namesInside(_ path: String) -> [String]? {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return nil }
        return try? FileManager.default.contentsOfDirectory(atPath: path)
    }

    /// A folder with an extension and an `Info.plist` in `Contents`, or in `Resources` for a framework. A dot alone
    /// is no bundle: `Logitech.localized` is a plain folder.
    private static func isBundle(_ path: String, exists: (String) -> Bool) -> Bool {
        guard !(path as NSString).pathExtension.isEmpty else { return false }
        return ["Contents/Info.plist", "Resources/Info.plist"].contains {
            exists((path as NSString).appendingPathComponent($0))
        }
    }

    /// A tool that could not be run, or that failed, says nothing about what is installed.
    static func pkgutil(_ arguments: [String]) async -> String? {
        guard case .success(let output) = await Subprocess.run("/usr/sbin/pkgutil", arguments, timeout: 30) else { return nil }
        return output.status == 0 ? output.text : nil
    }
}

/// Which system extensions macOS has installed, asked at most once for a scan, and only once an app carries one.
actor InstalledSystemExtensions {
    private let asking: AppExtensions.SystemExtensionsAnswer
    private var asked: Task<[AppExtension]?, Never>?

    init(asking: @escaping AppExtensions.SystemExtensionsAnswer) {
        self.asking = asking
    }

    func answer() async -> [AppExtension]? {
        if let asked { return await asked.value }
        let asking = asking
        let task = Task { await asking() }
        asked = task
        return await task.value
    }
}
