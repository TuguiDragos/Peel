import Foundation
internal import PeelPrivileged

/// The background items an app registers for this user through ServiceManagement: its login items, in
/// `Contents/Library/LoginItems`, and its agents, in `Contents/Library/LaunchAgents` (`SMAppService.h`). Once
/// registered, macOS starts them at every login from wherever the app is, the Trash included, until it is emptied.
enum StartsAtLogin {
    /// What launchd holds of what an app registered.
    struct Registration: Sendable, Equatable {
        let identifier: String
        let labels: [String]
    }

    /// A bundle writes its labels itself, so only so many are asked about.
    static let mostAsked = 64

    /// The labels launchd gives an app's items: each login item's bundle identifier, each agent's `Label`.
    static func labels(declaredBy app: URL) -> [String] {
        let library = app.appending(path: "Contents/Library", directoryHint: .isDirectory)
        let loginItems = entries(of: library.appending(path: "LoginItems", directoryHint: .isDirectory))
            .filter { $0.pathExtension == "app" }
            .compactMap(identifier(of:))
        let agents = entries(of: library.appending(path: "LaunchAgents", directoryHint: .isDirectory))
            .filter { $0.pathExtension == "plist" }
            .compactMap { JobDefinition(contentsOf: $0)?.label }
        var seen: Set<String> = []
        return Array((loginItems + agents).filter { LaunchdCleanup.isAppsOwn($0) && seen.insert($0).inserted }
            .prefix(mostAsked))
    }

    /// Whether the job `label` that `app` registered starts as it loads and again after it exits, as far as the app's
    /// bundle says: a login item does both and the app itself starts at login (`SMAppService.h`), while an agent or a
    /// daemon says it in its plist.
    static func schedule(
        of label: String, kind: BackgroundItem.Kind, in app: URL
    ) -> (runsAtLoad: Bool?, keepsAlive: Bool?) {
        let library = app.appending(path: "Contents/Library", directoryHint: .isDirectory)
        if kind == .agent {
            if identifier(of: app) == label { return (true, nil) }
            let loginItems = entries(of: library.appending(path: "LoginItems", directoryHint: .isDirectory))
                .lazy.filter { $0.pathExtension == "app" }.prefix(mostAsked)
            if loginItems.contains(where: { identifier(of: $0) == label }) { return (true, true) }
        }
        let folder = library.appending(path: kind == .agent ? "LaunchAgents" : "LaunchDaemons", directoryHint: .isDirectory)
        let job = entries(of: folder).lazy.filter { $0.pathExtension == "plist" }.prefix(mostAsked)
            .compactMap(JobDefinition.init(contentsOf:)).first { $0.label == label }
        return (job?.runsAtLoad, job?.keepsAlive)
    }

    /// What launchd holds now of what `app` registered, or nil when it holds nothing.
    @concurrent
    static func registration(of app: URL) async -> Registration? {
        guard let identifier = identifier(of: app), Identifier.isValid(identifier) else { return nil }
        var registered: [String] = []
        for label in labels(declaredBy: app) {
            let printed = await Launchctl.run(["print", "gui/\(getuid())/\(label)"])
            if isRegistered(Launchctl.answer(status: printed.status, output: printed.output), for: identifier) {
                registered.append(label)
            }
        }
        return registered.isEmpty ? nil : Registration(identifier: identifier, labels: registered)
    }

    /// Whether `answer` is a job ServiceManagement manages for the app `identifier` names.
    static func isRegistered(_ answer: Launchctl.Answer, for identifier: String) -> Bool {
        guard case .details(let details) = answer else { return false }
        return details.managedBy == BackgroundItems.serviceManagement
            && details.parentBundleIdentifier?.caseInsensitiveCompare(identifier) == .orderedSame
    }

    private static func identifier(of bundle: URL) -> String? {
        BoundedRead.propertyList(at: bundle.appending(path: "Contents/Info.plist"))?["CFBundleIdentifier"] as? String
    }

    private static func entries(of folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.sorted().map { folder.appending(path: $0) }
    }
}
