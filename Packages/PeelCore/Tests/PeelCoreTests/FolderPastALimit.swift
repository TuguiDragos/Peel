import Foundation
import Testing

extension Trait where Self == ConditionTrait {
    /// For a test that fills a folder past one of the limits Peel reads by, with ten thousand entries or more, and
    /// takes it away again. GitHub's runner has three processors, and there making and removing such folders holds the
    /// threads every other test waits for, so these tests are skipped on GitHub and run on a Mac.
    static var fillsAFolderPastALimit: Self {
        .disabled(if: ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true", "too heavy for GitHub's runner")
    }
}
