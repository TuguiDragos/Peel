import Darwin
public import Foundation

/// Intel-only software, which needs Rosetta on Apple silicon. macOS 27 is the last release to offer Rosetta.
public struct IntelFinding: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case app
        case insideApp
        case plugin
        case driver
        case backgroundItem
        case commandLineTool
    }

    public let url: URL
    public let kind: Kind
    public let name: String
    /// What it belongs to: the app it sits inside, or the launchd property list that starts it.
    public let owner: String?
    /// Nil when the size is not known because measuring it timed out or was refused. Unknown is not zero.
    public let size: Int64?

    public var id: URL { url }
}

public struct IntelScan: Sendable {
    public let findings: [IntelFinding]

    public func findings(of kind: IntelFinding.Kind) -> [IntelFinding] {
        findings.filter { $0.kind == kind }
    }
}

public enum IntelInspector {
    /// Folders searched in both the user's Library and the system's, because printer drivers and audio plug-ins
    /// can be installed for one user or for everyone. The macOS 27 release notes point to these folders for
    /// Intel plug-ins that may not appear in System Settings: `~/Library/Audio/Plug-Ins/*`,
    /// `~/Library/Printers/`, and `~/Library/ColorPickers/`.
    static let driverFolders = [
        "Image Capture/Devices",
        "Image Capture/TWAIN Data Sources",
        "Printers",
        "Audio/Plug-Ins",
        "ColorPickers",
    ]

    static func driverDirectories(_ environment: SearchEnvironment) -> [String] {
        [environment.homeDirectory.appending(path: "Library", directoryHint: .isDirectory),
         environment.rootDirectory.appending(path: "Library", directoryHint: .isDirectory)]
            .flatMap { library in driverFolders.map { library.appending(path: $0).path(percentEncoded: false) } }
    }

    static let toolDirectories = ["/usr/local/bin", "/usr/local/sbin", "/usr/local/libexec"]

    /// Folders inside an app whose contents run as processes of their own, so an Intel-only one really does
    /// need Rosetta.
    ///
    /// `Contents/Frameworks` is not one of them: a library there is loaded into the app's own process, so an
    /// Intel-only one matters only when the app itself runs as Intel code. The bundles beside the libraries are
    /// processes, and `frameworkProcesses` finds those.
    static let embeddedDirectories = [
        "Contents/Library/LoginItems", "Contents/PlugIns", "Contents/Extensions", "Contents/XPCServices",
        "Contents/Helpers", "Contents/Library/LaunchServices",
    ]

    /// The extensions of bundles that run as a process of their own.
    static let processExtensions: Set<String> = ["app", "xpc"]

    @concurrent
    public static func scan(
        installedApps: [InstalledApp],
        plugins: [Plugin] = [],
        backgroundItems: [BackgroundItem] = [],
        exclusions: Exclusions = .none,
        environment: SearchEnvironment = .current
    ) async -> IntelScan {
        await scan(
            installedApps: installedApps,
            plugins: plugins,
            backgroundItems: backgroundItems,
            exclusions: exclusions,
            environment: environment,
            measure: FileSize.measure
        )
    }

    @concurrent
    static func scan(
        installedApps: [InstalledApp],
        plugins: [Plugin],
        backgroundItems: [BackgroundItem],
        exclusions: Exclusions,
        environment: SearchEnvironment = .current,
        measure: FileSize.Measure
    ) async -> IntelScan {
        // A path can be found twice: `/Library/Audio/Plug-Ins/HAL` is a plug-in folder and sits inside a driver
        // folder, and two launchd jobs often run the same program. The first kind to find a path keeps it.
        var findings: [IntelFinding] = []
        var seen: Set<String> = []
        func isNew(_ url: URL) -> Bool { seen.insert(PathPattern.comparablePath(of: url)).inserted }

        for app in installedApps where !exclusions.excludes(app) {
            guard !Task.isCancelled else { break }
            if app.isIntelOnly, isNew(app.url) {
                findings.append(IntelFinding(
                    url: app.url,
                    kind: .app,
                    name: app.name,
                    owner: nil,
                    size: await measure(app.url),
                ))
                continue
            }
            for url in intelOnlyBundles(inside: app.url) where !Task.isCancelled && !exclusions.excludes(url) && isNew(url) {
                findings.append(IntelFinding(
                    url: url,
                    kind: .insideApp,
                    name: url.lastPathComponent,
                    owner: app.name,
                    size: await measure(url),
                ))
            }
        }

        for plugin in plugins where !Task.isCancelled && !exclusions.excludes(plugin.url) && isIntelOnly(bundle: plugin.url) && isNew(plugin.url) {
            findings.append(IntelFinding(
                url: plugin.url,
                kind: .plugin,
                name: plugin.name,
                owner: nil,
                size: plugin.size,
            ))
        }

        for url in bundles(in: driverDirectories(environment)) where !Task.isCancelled && !exclusions.excludes(url) && isIntelOnly(bundle: url) && isNew(url) {
            findings.append(IntelFinding(
                url: url,
                kind: .driver,
                name: url.lastPathComponent,
                owner: nil,
                size: await measure(url),
            ))
        }

        for item in backgroundItems where !Task.isCancelled {
            guard let program = item.program.map({ URL(filePath: $0) }), !exclusions.excludes(program) else { continue }
            guard isIntelOnly(executable: program), isNew(program) else { continue }
            findings.append(IntelFinding(
                url: program,
                kind: .backgroundItem,
                name: item.label,
                owner: item.plistURL?.lastPathComponent,
                size: await measure(program),
            ))
        }

        for url in tools(in: toolDirectories) where !Task.isCancelled && !exclusions.excludes(url) && isIntelOnly(executable: url) && isNew(url) {
            findings.append(IntelFinding(
                url: url,
                kind: .commandLineTool,
                name: url.lastPathComponent,
                owner: nil,
                size: await measure(url),
            ))
        }

        return IntelScan(findings: findings.sorted { $0.size != $1.size ? SizeTotal([$0.size]) > SizeTotal([$1.size]) : $0.name < $1.name })
    }

    /// Helpers, plug-ins, and plain binaries inside an app that only have Intel code.
    static func intelOnlyBundles(inside bundle: URL) -> [URL] {
        frameworkProcesses(inside: bundle).filter(isIntelOnly(bundle:)) + embeddedDirectories.flatMap { directory -> [URL] in
            let folder = bundle.appending(path: directory, directoryHint: .isDirectory)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
            return names.map { folder.appending(path: $0) }.filter { url in
                var info = stat()
                guard lstat(url.path(percentEncoded: false), &info) == 0 else { return false }
                if info.st_mode & S_IFMT == S_IFDIR {
                    return !url.pathExtension.isEmpty && isIntelOnly(bundle: url)
                }
                return info.st_mode & S_IFMT == S_IFREG && isIntelOnly(executable: url)
            }
        }
    }

    /// Returns the processes under `Contents/Frameworks`: apps and XPC services kept there directly, as every
    /// Electron app keeps its helpers, and those in each framework's `XPCServices` and `Helpers` folders.
    /// `Versions/Current` is skipped: it is a link to one of the versions beside it, so following it would
    /// report the same bundle twice.
    static func frameworkProcesses(inside bundle: URL) -> [URL] {
        let frameworks = bundle.appending(path: "Contents/Frameworks", directoryHint: .isDirectory)
        return entries(of: frameworks).flatMap { url -> [URL] in
            if processExtensions.contains(url.pathExtension.lowercased()) { return [url] }
            guard url.pathExtension.lowercased() == "framework" else { return [] }
            let versions = entries(of: url.appending(path: "Versions", directoryHint: .isDirectory))
                .filter { $0.lastPathComponent != "Current" }
            return (versions + [url]).flatMap { version in
                ["XPCServices", "Helpers"].flatMap { name in
                    // At the top of a versioned framework these are links into `Versions/Current`, already read.
                    let folder = version.appending(path: name, directoryHint: .isDirectory)
                    guard version != url || folder.isRealFolder else { return [URL]() }
                    return entries(of: folder).filter { processExtensions.contains($0.pathExtension.lowercased()) }
                }
            }
        }
    }

    private static func entries(of directory: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        return names.map { directory.appending(path: $0) }
    }

    static func isIntelOnly(bundle url: URL) -> Bool {
        guard let executable = executable(of: url) else { return false }
        return isIntelOnly(executable: executable)
    }

    static func isIntelOnly(executable url: URL) -> Bool {
        MachOHeader.architectures(ofExecutableAt: url) == [.x86_64]
    }

    /// The binary a bundle runs, from its Info.plist or, failing that, the name of the bundle.
    static func executable(of bundle: URL) -> URL? {
        let contents = bundle.appending(path: "Contents", directoryHint: .isDirectory)
        let info = BoundedRead.propertyList(at: contents.appending(path: "Info.plist"))
        let name = (info?["CFBundleExecutable"] as? String) ?? bundle.deletingPathExtension().lastPathComponent
        // The second place is for a flat bundle, which keeps its binary at its top level.
        let candidates = [contents.appending(path: "MacOS/\(name)"), bundle.appending(path: name)]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false)) }
    }

    static func bundles(in directories: [String]) -> [URL] {
        directories.flatMap { directory -> [URL] in
            let url = URL(filePath: directory, directoryHint: .isDirectory)
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return [] }
            return enumerator.compactMap { $0 as? URL }.filter { ["app", "plugin", "bundle", "driver", "qlgenerator", "mdimporter"].contains($0.pathExtension) }
        }
    }

    static func tools(in directories: [String]) -> [URL] {
        directories.flatMap { directory -> [URL] in
            let url = URL(filePath: directory, directoryHint: .isDirectory)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            return names.map { url.appending(path: $0) }.filter { candidate in
                // Only plain files, not links: a link takes a few bytes, and the binary it points to
                // belongs to something else.
                var info = stat()
                let path = candidate.path(percentEncoded: false)
                guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return false }
                return FileManager.default.isExecutableFile(atPath: path)
            }
        }
    }
}

extension IntelFinding {
    /// Whether `query` matches what the row shows: the name, or what the finding belongs to.
    public func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return SearchText.matches(name, query) || owner.map { SearchText.matches($0, query) } == true
    }
}
