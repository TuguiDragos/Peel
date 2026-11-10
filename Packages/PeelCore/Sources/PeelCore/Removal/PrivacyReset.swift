import CoreServices
public import Foundation
internal import PeelPrivileged

/// Makes macOS forget the privacy permissions given to an app, so a reinstalled app asks again. Peel only
/// runs Apple's `tccutil` and never writes the privacy database itself.
///
/// It must run while the app is still in place: `tccutil` finds the app through Launch Services
/// (`LSCopyApplicationURLsForBundleIdentifier`), which answers -10814 for an app whose only copy is in the
/// Trash. So it is never offered for the files an app left behind.
public enum PrivacyReset {
    public enum Result: Sendable, Hashable {
        case reset
        case notKnownToTheSystem
        /// Peel refused the identifier (see `isAllowed`), so `tccutil` never ran.
        case refused
        /// `tccutil` ran and did not reset. Carries what it printed, or an empty string.
        case failed(String)
        /// `tccutil` could not be started or did not finish. Carries Peel's own explanation, not words from macOS.
        case couldNotAsk(String)
    }

    /// Makes macOS forget what `app` was allowed to access. An app Launch Services knows no copy of, such as one kept
    /// outside the Applications folders and never opened, is registered there first, at its own place, as Finder
    /// registers an app it shows, since `tccutil` finds an app only through Launch Services.
    @concurrent
    public static func reset(_ app: InstalledApp) async -> Result {
        await reset(app) { _ = LSRegisterURL($0 as CFURL, false) }
    }

    @concurrent
    static func reset(
        _ app: InstalledApp,
        isKnown: @Sendable (String) -> Bool = { !AppInspector.applicationURLs(forBundleIdentifier: $0).isEmpty },
        register: @Sendable (URL) -> Void
    ) async -> Result {
        guard let bundleIdentifier = app.bundleIdentifier, isAllowed(bundleIdentifier: bundleIdentifier) else {
            return .refused
        }
        if !isKnown(bundleIdentifier) { register(app.url) }

        switch await Subprocess.run("/usr/bin/tccutil", ["reset", "All", bundleIdentifier], timeout: 10) {
        case .success(let output):
            return result(
                status: output.status,
                output: (output.text + output.errorText).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        case .failure(let failure):
            return .couldNotAsk(failure.explanation)
        }
    }

    /// Resets each of `apps` that `service` would move now, in turn. Call it just before the removal moves them:
    /// `tccutil` only finds an app still in place, and an app something keeps in place stays, with its permissions.
    @concurrent
    public static func reset(
        _ apps: [InstalledApp],
        beforeMovingWith service: TrashService
    ) async -> [(app: InstalledApp, result: Result)] {
        var results: [(app: InstalledApp, result: Result)] = []
        for app in await goingNow(apps, with: service) {
            results.append((app, await reset(app)))
        }
        return results
    }

    static func goingNow(_ apps: [InstalledApp], with service: TrashService) async -> [InstalledApp] {
        var running: Set<URL> = []
        for app in apps {
            if await UninstallsItself.of(app, environment: service.environment)?.letsItsProgramsRun == true {
                running.insert(app.url)
            }
        }
        let refused = await service.refusalsNow(ofApps: apps.map(\.url), lettingTheirProgramsRun: running)
        return apps.filter { refused[$0.url] == nil }
    }

    /// Returns the resets worth reporting once the removal is over: those that did not happen, and those that did
    /// for an app that then stayed. A reset whose app was moved is what the user asked for.
    public static func worthTelling(
        _ resets: [(app: InstalledApp, result: Result)],
        after removal: TrashResult
    ) -> [(app: InstalledApp, result: Result)] {
        let stayed = Set(removal.failures.map(\.url))
        return resets.filter { $0.result != .reset || stayed.contains($0.app.url) }
    }

    /// Returns the apps a removal resets: those whose own bundle is selected, that `isAllowed` accepts, and whose
    /// other copies (`copies`) all go too, since macOS keeps one set of permissions for every copy. An app whose
    /// leftovers alone are removed stays installed, and nobody asked to reset it.
    public static func apps(
        among apps: [InstalledApp], moving selected: Set<URL>, copies: (InstalledApp) -> [URL] = { _ in [] }
    ) -> [InstalledApp] {
        let moving = Set(selected.map(PathPattern.comparablePath))
        return apps.filter { app in
            moving.contains(PathPattern.comparablePath(of: app.url)) && isAllowed(for: app)
                && copies(app).allSatisfy { moving.contains(PathPattern.comparablePath(of: $0)) }
        }
    }

    /// Interprets `tccutil`'s exit status and output. Kept apart from running it so it can be tested.
    static func result(status: Int32, output: String) -> Result {
        if status == 0 { return .reset }
        if output.contains("No such bundle identifier") { return .notKnownToTheSystem }
        return .failed(output)
    }

    /// True when `app` has an identifier that may be handed to `tccutil`.
    public static func isAllowed(for app: InstalledApp) -> Bool {
        app.bundleIdentifier.map(isAllowed(bundleIdentifier:)) ?? false
    }

    /// True when `bundleIdentifier` may be handed to `tccutil`. Apple's own apps and every part of Peel are
    /// refused, and any other identifier must read as exactly one app's (`Identifier.isValid`). This matters
    /// because `tccutil reset All` with no identifier resets every app.
    public static func isAllowed(bundleIdentifier: String) -> Bool {
        guard !bundleIdentifier.lowercased().hasPrefix("com.apple."), !Identifier.isPeels(bundleIdentifier) else {
            return false
        }
        return Identifier.isValid(bundleIdentifier)
    }
}
