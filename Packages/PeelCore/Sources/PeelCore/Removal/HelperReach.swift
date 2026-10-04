import Foundation
internal import PeelPrivileged

/// Tells whether Peel's helper would move an item, using the helper's own rule
/// (`PrivilegedPathPolicy.refusal(of:)`) with its folders placed under the environment's root.
struct HelperReach: Sendable {
    private let policy: PrivilegedPathPolicy

    init(environment: SearchEnvironment) {
        let root = PathPattern.comparablePath(of: environment.rootDirectory)
        let base = root == "/" ? "" : root
        policy = PrivilegedPathPolicy(
            homeDirectory: PathPattern.comparablePath(of: environment.homeDirectory),
            systemLocations: PrivilegedPathPolicy.systemLocations.map { base + $0 },
            applicationLocations: [base + "/Applications"],
            restoreLocations: PrivilegedPathPolicy.restoreLocations.map { base + $0 },
            linkLocations: PrivilegedPathPolicy.linkLocations.map { base + $0 }
        )
    }

    /// True for an item in a folder command-line tools are linked into, which the helper takes only once the link
    /// leads nowhere.
    func takesOnlyALink(at url: URL) -> Bool {
        policy.takesOnlyALink(at: url.path(percentEncoded: false))
    }

    /// True when the helper would refuse `url` for where it is: outside the folders it serves, in `/Applications`
    /// without being an app, or in a folder command-line tools are linked into as anything but a link that leads
    /// nowhere, or into `leaving`, which moves first. `RemovalGuard` judges what the item itself is.
    func isBeyond(_ url: URL, leaving: URL? = nil) -> Bool {
        let path = url.path(percentEncoded: false)
        if let refusal = policy.refusal(of: path) {
            return refusal == .outsideAllowedLocations || refusal == .notAnApplication
        }
        guard policy.takesOnlyALink(at: path) else { return false }
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFLNK else { return true }
        guard let destination = PrivilegedPathPolicy.resolvedPath(path) else { return false }
        guard let leaving, let app = PrivilegedPathPolicy.resolvedPath(leaving.path(percentEncoded: false)) else {
            return true
        }
        return !PathComponents.isPath(destination, atOrInside: app)
    }
}
