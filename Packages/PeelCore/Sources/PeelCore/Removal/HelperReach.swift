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
            restoreLocations: PrivilegedPathPolicy.restoreLocations.map { base + $0 }
        )
    }

    /// True when the helper would refuse `url` for where it is: outside the folders it serves, or in
    /// `/Applications` without being an app. `RemovalGuard` judges what the item itself is.
    func isBeyond(_ url: URL) -> Bool {
        guard let refusal = policy.refusal(of: url.path(percentEncoded: false)) else { return false }
        return refusal == .outsideAllowedLocations || refusal == .notAnApplication
    }
}
