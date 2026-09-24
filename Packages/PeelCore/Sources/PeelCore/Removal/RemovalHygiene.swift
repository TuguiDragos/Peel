import Foundation
internal import PeelPrivileged

enum LaunchdCleanup {
    struct Job: Sendable, Hashable {
        let label: String
        let isDaemon: Bool
        /// The file that declares it.
        let plist: URL
    }

    /// Stops jobs whose configuration has gone, so launchd doesn't keep them running or restart them.
    @concurrent
    static func stop(_ jobs: [Job], canUseHelper: Bool) async {
        for job in jobs {
            if job.isDaemon {
                guard canUseHelper, PrivilegedHelper.status == .enabled else { continue }
                _ = await PrivilegedHelper.runDaemonCommand(.bootout, label: job.label)
            } else {
                _ = await Launchctl.run(["bootout", "gui/\(getuid())/\(job.label)"])
            }
        }
    }

    /// The jobs these plists declare. launchd knows a job by the `Label` inside its file, and the file name does
    /// not always repeat it, so a file that cannot be read gives no job.
    static func jobs(for urls: [URL], environment: SearchEnvironment = .current) -> [Job] {
        // Only the folders launchd actually reads. A copy of a plist kept anywhere else, in a backup or in a
        // folder that merely shares the name, must not make Peel stop the job that is really running.
        let folders = environment.locations.filter { $0.kind == .launchAgents || $0.kind == .launchDaemons }
        let daemons = Set(folders.filter { $0.kind == .launchDaemons }.map { PathPattern.comparablePath(of: $0.url) })
        let all = Set(folders.map { PathPattern.comparablePath(of: $0.url) })

        return urls.compactMap { url -> Job? in
            guard url.path(percentEncoded: false).hasSuffix(".plist") else { return nil }
            let parent = PathPattern.comparablePath(of: url.deletingLastPathComponent())
            guard all.contains(parent) else { return nil }
            // A label macOS itself uses would reach macOS's own job, whatever file declared it.
            guard
                let label = BoundedRead.propertyList(at: url)?["Label"] as? String, PrivilegedPathPolicy.isValidLabel(label),
                !SystemDaemons.shipped.contains(label), !SystemAgents.shipped.contains(label)
            else { return nil }
            return Job(label: label, isDaemon: daemons.contains(parent), plist: url)
        }
    }
}

enum PreferenceCleanup {
    /// Runs `defaults delete` for the preference domains of files that moved, so cfprefsd forgets them: it keeps
    /// preferences in memory, and a removed plist can come back. Apple's guidance:
    /// https://developer.apple.com/forums/thread/20595
    /// `owner` is the bundle identifier of the app being reset. Its own domain is forgotten even when Apple wrote
    /// the app; every other `com.apple.` domain is left alone.
    @concurrent
    static func forgetDomains(for urls: [URL], ownedBy owner: String?) async {
        // The files have already moved, and the removal is recorded only after this returns, so each call has a
        // timeout: a `defaults` that never exits must not leave the removal unrecorded.
        for domain in domains(for: urls, ownedBy: owner) {
            _ = await Subprocess.run("/usr/bin/defaults", domain.command("delete"), timeout: 10)
        }
    }

    struct Domain: Sendable, Hashable {
        let name: String
        let isByHost: Bool

        /// The arguments for `defaults`. Only `-currentHost` reaches a ByHost domain (`-host` gets the any-host
        /// one), and only before the verb: after it, `defaults` takes it for the domain and the domain for a key.
        func command(_ verb: String, _ file: String? = nil) -> [String] {
            (isByHost ? ["-currentHost"] : []) + [verb, name] + (file.map { [$0] } ?? [])
        }
    }

    /// The UUID the current Mac's ByHost files carry in their names. Empty when it cannot be read, so no file matches.
    static let hostIdentifier: String = {
        var bytes = [UInt8](repeating: 0, count: 16)
        var wait = timespec(tv_sec: 1, tv_nsec: 0)
        guard gethostuuid(&bytes, &wait) == 0 else { return "" }
        return NSUUID(uuidBytes: bytes).uuidString
    }()

    static func domains(
        for urls: [URL],
        ownedBy owner: String? = nil,
        home: URL = .homeDirectory,
        host: String = PreferenceCleanup.hostIdentifier
    ) -> [Domain] {
        // Only the user's `Library/Preferences` and its `ByHost` folder, plus the settings file in the container
        // of the app being reset. `defaults` reads a name as this user's domain, so a file from
        // `/Library/Preferences` or a copy in a backup must not clear the settings in use.
        let plain = PathPattern.comparablePath(of: home.appending(path: "Library/Preferences", directoryHint: .isDirectory))
        let byHost = plain + "/ByHost"

        var seen: Set<Domain> = []
        return urls.compactMap { url -> Domain? in
            let path = url.path(percentEncoded: false)
            guard path.hasSuffix(".plist") else { return nil }
            let parent = PathPattern.comparablePath(of: url.deletingLastPathComponent())
            let isByHost = parent == byHost
            let name = LeftoverMatcher.key(from: url.lastPathComponent, kind: isByHost ? .preferencesByHost : .preferences)
            guard isByHost || parent == plain || isTheSettingsFile(name, in: parent, ofTheAppBeingReset: owner, home: home) else { return nil }
            guard isUsableName(name) else { return nil }
            // A ByHost file is named `<domain>.<host UUID>.plist`. `-currentHost` always means the current Mac, so
            // a file another Mac left behind names no domain here.
            let fileHost = url.lastPathComponent.removingSuffix(".plist").dropFirst(name.count + 1)
            guard !isByHost || (!host.isEmpty && fileHost.caseInsensitiveCompare(host) == .orderedSame) else { return nil }
            // The disk ignores case, so `COM.APPLE.DOCK` is the Dock's domain too.
            guard !name.lowercased().hasPrefix("com.apple.") || isOwned(name, by: owner) else { return nil }
            let domain = Domain(name: name, isByHost: isByHost)
            guard !seen.contains(domain), !containerKeeps(domain, apartFrom: urls, home: home) else { return nil }
            seen.insert(domain)
            return domain
        }
    }

    /// Whether `name` is the settings file of the app being reset, inside that app's container. A sandboxed app
    /// keeps its settings there, and `defaults` reads the app's domain from that file. No other file in a
    /// container has a name `defaults` would find it by.
    private static func isTheSettingsFile(_ name: String, in parent: String, ofTheAppBeingReset owner: String?, home: URL) -> Bool {
        guard isOwned(name, by: owner) else { return false }
        let container = PathPattern.comparablePath(of: home.appending(path: "Library/Containers/\(name)/Data/Library/Preferences", directoryHint: .isDirectory))
        return parent.caseInsensitiveCompare(container) == .orderedSame
    }

    /// False for a name `defaults` would read as something other than one app's domain: an option, a path, a
    /// hidden file, or a name with no dot. The global domain answers to `.GlobalPreferences`, `NSGlobalDomain`,
    /// `Apple Global Domain`, and `kCFPreferencesAnyApplication`, and Apple's agents use one-word names
    /// (`loginwindow`, `pbs`).
    static func isUsableName(_ name: String) -> Bool {
        !name.hasPrefix("-") && !name.hasPrefix(".") && !name.contains("/") && name.contains(".")
    }

    /// True when the app's container holds a settings file for `domain` that is not among `urls`, or when the
    /// folder that would hold it cannot be read. `defaults` reads a name from the container when there is one,
    /// so forgetting the domain would clear those settings, which is only right when those files are going too.
    private static func containerKeeps(_ domain: Domain, apartFrom urls: [URL], home: URL) -> Bool {
        var folder = home.appending(path: "Library/Containers/\(domain.name)/Data/Library/Preferences", directoryHint: .isDirectory)
        if domain.isByHost {
            folder.append(path: "ByHost", directoryHint: .isDirectory)
        }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else {
            // A folder that exists but cannot be read may hold the file, and an unknown answer is not safe. It
            // does not matter whether TCC or the file permissions refused the read.
            var info = stat()
            return lstat(folder.path(percentEncoded: false), &info) == 0
        }
        let kind: SearchLocation.Kind = domain.isByHost ? .preferencesByHost : .preferences
        let kept = names.filter {
            $0.hasSuffix(".plist") && LeftoverMatcher.key(from: $0, kind: kind).caseInsensitiveCompare(domain.name) == .orderedSame
        }
        guard !kept.isEmpty else { return false }
        let going = urls.map(PathPattern.comparablePath)
        return kept.contains { name in
            let path = PathPattern.comparablePath(of: folder.appending(path: name))
            return !going.contains { PathComponents.isPath(path, atOrInside: $0) }
        }
    }

    private static func isOwned(_ name: String, by owner: String?) -> Bool {
        guard let owner, Identifier.isReverseDNS(owner) else { return false }
        return name == owner || name.hasPrefix(owner + ".")
    }
}
