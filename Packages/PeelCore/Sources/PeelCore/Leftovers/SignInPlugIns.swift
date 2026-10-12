import Foundation

/// The authorization plug-ins macOS loads from `/Library/Security/SecurityAgentPlugins` when a rule of the
/// authorization database names one, at login among others (Apple's NullAuthPlugin sample). No public tool lists every
/// rule, and a plug-in a rule still names, once gone, can keep anyone from logging in, so Peel lists them and never
/// moves them.
enum SignInPlugIns {
    static let folder = "Security/SecurityAgentPlugins"

    static func isOne(_ url: URL, root: URL) -> Bool {
        let folder = root.appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: Self.folder, directoryHint: .isDirectory)
        return PathPattern.comparablePath(of: url.deletingLastPathComponent()) == PathPattern.comparablePath(of: folder)
    }
}
