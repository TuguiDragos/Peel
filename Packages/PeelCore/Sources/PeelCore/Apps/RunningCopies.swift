public import AppKit
internal import PeelPrivileged

/// Finds the running processes that belong to an app, so they can be quit before its files are moved and
/// nothing rewrites those files meanwhile.
public enum RunningCopies {
    public struct Process: Sendable, Hashable {
        public let identifier: pid_t
        public let bundleIdentifier: String
        public let bundleURL: URL?

        public init(identifier: pid_t, bundleIdentifier: String, bundleURL: URL?) {
            self.identifier = identifier
            self.bundleIdentifier = bundleIdentifier
            self.bundleURL = bundleURL
        }
    }

    @MainActor
    public static var current: [Process] {
        NSWorkspace.shared.runningApplications.compactMap { running in
            running.bundleIdentifier.map { Process(identifier: running.processIdentifier, bundleIdentifier: $0, bundleURL: running.bundleURL) }
        }
    }

    /// Returns the processes in `running` that belong to `app`. The app itself is known by where it runs from:
    /// a copy elsewhere is another app, and quitting it would close the one in use. The app's helpers run from
    /// inside its bundle, or carry an identifier the bundle embeds or one that extends the app's, unless another
    /// installed app owns that identifier (Chrome Canary beside Chrome). A process whose location is unknown is
    /// judged by its identifier.
    ///
    /// `sharingItsSettings` is for a reset: every copy of the app writes the same preference domain, wherever
    /// it runs from, so all of them count.
    public static func belonging(
        to app: InstalledApp,
        among running: [Process],
        installedApps: [InstalledApp],
        sharingItsSettings: Bool = false
    ) -> [Process] {
        let bundle = PathPattern.comparablePath(of: app.url)
        let embedded = Set(app.embeddedBundleIdentifiers)
        let others = installedApps
            .filter { PathPattern.comparablePath(of: $0.url) != bundle && $0.bundleIdentifier != app.bundleIdentifier }
            .map(\.bundleIdentifier)

        return running.filter { process in
            let place = process.bundleURL.map(PathPattern.comparablePath)
            if let place, PathComponents.isPath(place, inside: bundle) { return true }
            if process.bundleIdentifier == app.bundleIdentifier { return sharingItsSettings || place == nil || place == bundle }
            guard embedded.contains(process.bundleIdentifier) || process.bundleIdentifier.hasPrefix(app.bundleIdentifier + ".") else { return false }
            // Leaves out what another installed app owns: its own identifier, or one that extends an identifier
            // longer than this app's. So Canary's helpers belong to Canary, never to Chrome.
            return !others.contains { other in
                process.bundleIdentifier == other
                    || (other.count > app.bundleIdentifier.count && process.bundleIdentifier.hasPrefix(other + "."))
            }
        }
    }
}
