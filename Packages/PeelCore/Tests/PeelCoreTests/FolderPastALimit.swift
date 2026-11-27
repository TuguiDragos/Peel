import Foundation
import Testing

extension Trait where Self == ConditionTrait {
    /// Skipped on GitHub: folders this big hold the threads of its three processors.
    static var fillsAFolderPastALimit: Self {
        .disabled(if: ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true", "too heavy for GitHub's runner")
    }
}
