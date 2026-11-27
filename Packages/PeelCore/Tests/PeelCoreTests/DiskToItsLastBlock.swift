import Foundation
import Testing

extension Trait where Self == ConditionTrait {
    /// Skipped on GitHub: under its load a full disk image can take a file again, and the test proves nothing.
    static var fillsADiskToItsLastBlock: Self {
        .disabled(
            if: ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
            "a full disk does not stay full on GitHub's runner"
        )
    }
}
