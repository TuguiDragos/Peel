public import AppKit
internal import PeelPrivileged

/// Finds the running processes that belong to an app, so they can be quit before its files are moved and
/// nothing rewrites those files meanwhile.
public enum RunningCopies {
    public struct Process: Sendable, Hashable {
        public let identifier: pid_t
        public let bundleIdentifier: String?
        public let bundleURL: URL?

        public init(identifier: pid_t, bundleIdentifier: String?, bundleURL: URL?) {
            self.identifier = identifier
            self.bundleIdentifier = bundleIdentifier
            self.bundleURL = bundleURL
        }
    }

    @MainActor
    public static var current: [Process] {
        NSWorkspace.shared.runningApplications.compactMap { running in
            guard running.bundleIdentifier != nil || running.bundleURL != nil else { return nil }
            return Process(
                identifier: running.processIdentifier,
                bundleIdentifier: running.bundleIdentifier,
                bundleURL: running.bundleURL
            )
        }
    }

    /// Returns the processes in `running` that belong to `app`. The app itself is known by where it runs from:
    /// a copy elsewhere is another app, and quitting it would close the one in use. The app's helpers run from
    /// inside its bundle, or carry an identifier the bundle embeds or one that extends the app's, unless another
    /// installed app owns that identifier (Chrome Canary beside Chrome) or it runs as an app of its own outside a
    /// Library, as Canary does on another disk. A process whose location is unknown is judged by its identifier.
    /// Identifiers are compared without case, as bundle identifiers are.
    ///
    /// `sharingItsSettings` is for a reset: every copy of the app writes the same preference domain, wherever
    /// it runs from, so all of them count.
    public static func belonging(
        to app: InstalledApp,
        among running: [Process],
        installedApps: [InstalledApp],
        sharingItsSettings: Bool = false,
        environment: SearchEnvironment = .current
    ) -> [Process] {
        let bundle = PathPattern.comparablePath(of: app.url)
        let identifier = app.bundleIdentifier?.lowercased()
        let embedded = Set(app.embeddedBundleIdentifiers.map { $0.lowercased() })
        let others = installedApps
            .filter { PathPattern.comparablePath(of: $0.url) != bundle }
            .compactMap { $0.bundleIdentifier?.lowercased() }
            .filter { $0 != identifier }

        return running.filter { process in
            let place = process.bundleURL.map(PathPattern.comparablePath)
            if let place, PathComponents.isPath(place, atOrInside: bundle) { return true }
            guard let identifier, let name = process.bundleIdentifier?.lowercased() else { return false }
            if name == identifier { return sharingItsSettings || place == nil }
            guard embedded.contains(name) || name.hasPrefix(identifier + ".") else { return false }
            if let place, environment.keepsOnItsOwn(appAt: place) { return false }
            // Leaves out what another installed app owns: its own identifier, or one that extends an identifier
            // longer than this app's. So Canary's helpers belong to Canary, never to Chrome.
            return !others.contains { other in
                name == other || (other.count > identifier.count && name.hasPrefix(other + "."))
            }
        }
    }
}
